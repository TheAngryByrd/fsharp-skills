#Requires -Version 7.4
param(
    [Parameter(Mandatory)][string]$Workspace,
    [Parameter(Mandatory)][string]$OutDir,
    [switch]$SkipNative,
    [int]$TestTimeoutSeconds = 300,
    [int]$BenchTimeoutSeconds = 900
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../../lib/Grading.psm1') -Force

$benchChecks = @(
    'summarize gives the same stats as the original code'
    'render gives the same text as the original code under the de-DE culture'
    'summarize of 200,000 readings allocates no more than 2 x the reference + 64 KB'
    'summarize of 200,000 readings median run time is no more than 3 x the reference + 1 ms'
    'render of 1,000 sensors allocates no more than 2 x the reference + 64 KB'
    'render of 1,000 sensors median run time is no more than 3 x the reference + 1 ms'
)
$checks = @()
$copy = Join-Path $OutDir 'ws'
Copy-Workspace $Workspace $copy
$globalJson = Get-Content -Raw (Join-Path $PSScriptRoot 'global.json')
if (-not (Test-Path (Join-Path $copy 'global.json'))) { Set-Content (Join-Path $copy 'global.json') $globalJson }

$project = Join-Path $copy 'Telemetry/Telemetry.fsproj'
if (-not (Test-Path $project)) {
    $checks += New-Check 'Telemetry builds' $false 'Telemetry/Telemetry.fsproj missing'
    $checks += New-Check 'The original Telemetry.Tests build and pass' $null 'skipped: Telemetry is missing'
    $checks += New-Check 'The public signatures did not change (the grader bench builds against them)' $null 'skipped: Telemetry is missing'
    $checks += $benchChecks | ForEach-Object { New-Check $_ $null 'skipped: Telemetry is missing' }
    Write-Checks (Join-Path $OutDir 'grading.json') $checks
    return
}

$tests = Join-Path $copy 'Telemetry.Tests'
if (Test-Path $tests) { Remove-Item -Recurse -Force $tests }
Copy-Item (Join-Path $PSScriptRoot '../inputs/Telemetry.Tests') $tests -Recurse

function Invoke-Bounded([string]$Directory, [string[]]$Arguments, [int]$TimeoutSeconds, [long]$MaxOutputBytes = 16MB) {
    $stdout = Join-Path $Directory "bounded-$([guid]::NewGuid().ToString('N')).out"
    $stderr = "$stdout.err"
    $process = Start-Process dotnet -ArgumentList $Arguments -WorkingDirectory $Directory -RedirectStandardOutput $stdout -RedirectStandardError $stderr -NoNewWindow -PassThru
    $null = $process.Handle
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    $size = { (Get-Item $stdout -ErrorAction SilentlyContinue).Length + (Get-Item $stderr -ErrorAction SilentlyContinue).Length }
    $problem = $null
    while (-not $process.WaitForExit(250)) {
        if ($clock.Elapsed.TotalSeconds -ge $TimeoutSeconds) { $problem = "the process did not finish in $TimeoutSeconds seconds"; break }
        if ((& $size) -gt $MaxOutputBytes) { $problem = "the process wrote more than $MaxOutputBytes bytes"; break }
    }
    if ($problem) {
        $process.Kill($true)
        $process.WaitForExit()
    } elseif ((& $size) -gt $MaxOutputBytes) {
        $problem = "the process wrote more than $MaxOutputBytes bytes"
    } elseif ($process.ExitCode -ne 0) {
        $problem = "the process exited with code $($process.ExitCode)"
    }
    $text = if ($problem -and (& $size) -gt $MaxOutputBytes) { '' } else { (Get-Content -Raw $stdout) + (Get-Content -Raw $stderr) }
    [pscustomobject]@{ Problem = $problem; Lines = @("$text" -split '\r?\n'); Text = "$text" }
}

$build = Invoke-Capture dotnet @('build', $project, '-c', 'Release') -WorkingDirectory (Split-Path $project)
$built = $build.ExitCode -eq 0
$checks += New-Check 'Telemetry builds' $built $(if (-not $built) { Get-LastLines (($build.Lines | Where-Object { $_ -match ' error ' } | Sort-Object -Unique) -join "`n") })

$testsPassed = $null
$testEvidence = ''
if ($built) {
    $testBuild = Invoke-Capture dotnet @('build', 'Telemetry.Tests.fsproj', '-c', 'Release', '-o', 'out') -WorkingDirectory $tests
    if ($testBuild.ExitCode -ne 0) {
        $testsPassed = $false
        $testEvidence = Get-LastLines $testBuild.Text 8
    } else {
        $test = Invoke-Bounded $tests @('out/Telemetry.Tests.dll') $TestTimeoutSeconds
        $passCount = @($test.Lines | Where-Object { $_ -match '^PASS ' }).Count
        $testsPassed = -not $test.Problem -and $passCount -eq 8
        $testEvidence = (@($test.Problem) + @(Get-LastLines $test.Text 8) | Where-Object { $_ }) -join "`n"
    }
}
$checks += New-Check 'The original Telemetry.Tests build and pass' $testsPassed $testEvidence

$bench = Join-Path $OutDir 'bench'
New-Item -ItemType Directory -Force -Path $bench | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'Bench/*.fs') $bench
Set-Content (Join-Path $bench 'global.json') $globalJson
Set-Content (Join-Path $bench 'Bench.fsproj') @"
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net10.0</TargetFramework>
    <TieredCompilation>false</TieredCompilation>
    <ServerGarbageCollector>false</ServerGarbageCollector>
    <ConcurrentGarbageCollection>false</ConcurrentGarbageCollection>
  </PropertyGroup>
  <ItemGroup>
    <Compile Include="Original.fs" />
    <Compile Include="Reference.fs" />
    <Compile Include="Bench.fs" />
    <ProjectReference Include="$((Resolve-Path $project).Path)" />
  </ItemGroup>
</Project>
"@

$benchBuild = if ($built) { Invoke-Capture dotnet @('build', 'Bench.fsproj', '-c', 'Release', '-o', 'out') -WorkingDirectory $bench } else { $null }
$benchBuilt = $benchBuild -and $benchBuild.ExitCode -eq 0
$benchErrors = if ($benchBuild) { @($benchBuild.Lines | Where-Object { $_ -match 'error FS' } | ForEach-Object { $_ -replace '\s*\[.*$', '' } | Sort-Object -Unique) -join "`n" } else { '' }
$checks += New-Check 'The public signatures did not change (the grader bench builds against them)' $(if ($built) { $benchBuilt } else { $null }) $benchErrors

$results = @()
$problem = $null
$run = $null
if ($benchBuilt) {
    $token = [guid]::NewGuid().ToString('N')
    $run = Invoke-Bounded $bench @('out/Bench.dll', $token) $BenchTimeoutSeconds
    $results = @(ConvertFrom-ProbeOutput $run.Lines)
    $evidence = @{}
    foreach ($line in $run.Lines) {
        if ($line -match '^(PASS|FAIL) (.*) \[(.*)\]$') { $evidence[$Matches[2]] = $Matches[3] }
    }
    foreach ($r in $results) { if ($evidence.ContainsKey($r.text)) { $r.evidence = $evidence[$r.text] } }
    $problem = if ($run.Problem) { "bench: $($run.Problem)" }
    elseif ($run.Lines -notcontains "BENCH DONE $token") { 'the bench exited before it printed its completion line' }
}
$correctnessFor = @{
    'summarize' = 'summarize gives the same stats as the original code'
    'render' = 'render gives the same text as the original code under the de-DE culture'
}
foreach ($name in $benchChecks) {
    $found = @($results | Where-Object text -EQ $name)
    if (-not $benchBuilt) {
        $checks += New-Check $name $null 'skipped: the grader bench did not build'
        continue
    }
    if ($problem) {
        $checks += New-Check $name $false "${problem}`n$(Get-LastLines $run.Text 6)"
        continue
    }
    if ($found.Count -gt 1) {
        $checks += New-Check $name $false "the bench output has $($found.Count) result lines for this check"
        continue
    }
    $function = ($name -split ' ')[0]
    $gate = @($results | Where-Object text -EQ $correctnessFor[$function])
    if ($found.Count -eq 1 -and $correctnessFor.ContainsKey($function) -and $name -ne $correctnessFor[$function] -and -not ($gate.Count -eq 1 -and $gate[0].passed -eq $true)) {
        $checks += New-Check $name $false "the bench output has a result line for this check, but the $function output check did not pass"
    } elseif ($found.Count -eq 1) {
        $checks += $found[0]
    } elseif ($gate.Count -eq 1 -and $gate[0].passed -eq $false) {
        $checks += New-Check $name $null "skipped: the $function output differs from the original code"
    } else {
        $checks += New-Check $name $false "the bench did not report this check`n$(Get-LastLines $run.Text 6)"
    }
}

Write-Checks (Join-Path $OutDir 'grading.json') $checks
