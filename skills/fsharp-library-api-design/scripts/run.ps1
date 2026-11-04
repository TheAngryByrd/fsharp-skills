#Requires -Version 7.4
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$failures = [System.Collections.Generic.List[string]]::new()
$artifacts = Join-Path ([IO.Path]::GetTempPath()) "fsharp-library-api-design-proof-$PID"
$work = Join-Path ([IO.Path]::GetTempPath()) "fsharp-library-api-design-work-$PID"
$feed = Join-Path $work 'feed'
$packages = Join-Path $work 'packages'
New-Item -ItemType Directory -Force -Path $feed | Out-Null
$previousPackages = $env:NUGET_PACKAGES
$previousRoot = $env:FSHARP_API_PROOF_ROOT
$env:FSHARP_API_PROOF_ROOT = Join-Path $artifacts 'v1'
$env:NUGET_PACKAGES = $packages
$shared = 'global.json', 'Directory.Build.props', 'Directory.Build.targets', 'Directory.Packages.props'
foreach ($name in $shared) { Copy-Item (Join-Path $PSScriptRoot $name) $work }

function Invoke-Dotnet([string]$Directory, [string[]]$Arguments) {
    Push-Location $Directory
    try {
        $output = dotnet @Arguments 2>&1 | ForEach-Object { "$_" }
        [pscustomobject]@{ ExitCode = $LASTEXITCODE; Lines = @($output); Text = ($output -join "`n") }
    } finally { Pop-Location }
}

function Get-Codes([string]$Text, [string]$Pattern) {
    @([regex]::Matches($Text, $Pattern) | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
}

function New-Lib([string]$Name, [string]$Source, [string]$Version, [string]$Flags) {
    $dir = Join-Path $work "$Name/Lib"
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $properties = "<Version>$Version</Version>" + $(if ($Flags) { "<OtherFlags>`$(OtherFlags) $Flags</OtherFlags>" })
    (Get-Content -Raw (Join-Path $PSScriptRoot 'V1/Lib.fsproj')).Replace('<Version>1.0.0</Version>', $properties) |
        Set-Content (Join-Path $dir 'Lib.fsproj')
    Copy-Item $Source (Join-Path $dir 'Lib.fs')
    Join-Path $dir 'Lib.fsproj'
}

function New-Consumer([string]$Name, [string]$Kind, [string]$LibProject) {
    $dir = Join-Path $work "$Name/$Kind"
    Copy-Item (Join-Path $PSScriptRoot $Kind) $dir -Recurse
    $proj = Get-ChildItem $dir -Filter "$Kind.*proj" | Select-Object -First 1
    (Get-Content -Raw $proj.FullName).Replace('LIB_PROJECT', $LibProject) | Set-Content $proj.FullName
    $dir
}

function Invoke-Program([string]$Directory, [string]$Dll) {
    $r = Invoke-Dotnet $Directory @($Dll)
    $exception = if ($r.Text -match 'Unhandled exception\. ([\w.]+)') { $Matches[1] -replace '^System\.', '' } else { '' }
    [pscustomobject]@{ ExitCode = $r.ExitCode; Output = ($r.Lines -join "`n").Trim(); Exception = $exception }
}

$consumers = [ordered]@{ fs = 'Consumer'; cs = 'ConsumerCs' }
$codePattern = @{ fs = 'error (FS\d+)'; cs = 'error (CS\d+)' }
$baselines = @{}

function Get-Baseline([string]$Flags) {
    if ($baselines.ContainsKey($Flags)) { return $baselines[$Flags] }
    $name = 'v1' + $(if ($Flags) { "-$($baselines.Count)" })
    $env:FSHARP_API_PROOF_ROOT = Join-Path $artifacts $name
    $project = New-Lib $name (Join-Path $PSScriptRoot 'V1/Lib.fs') '1.0.0' $Flags
    $result = @{ Project = $project }
    foreach ($kind in $consumers.Keys) {
        $consumer = $consumers[$kind]
        $dir = New-Consumer $name $consumer $project
        $out = Join-Path $work "$name/out-$kind"
        $b = Invoke-Dotnet $dir @('build', '-c', 'Release', '-o', $out)
        if ($b.ExitCode -ne 0) { throw "The 1.0.0 consumer $consumer did not build:`n$($b.Text)" }
        $run = Invoke-Program $out "$consumer.dll"
        if ($run.ExitCode -ne 0) { throw "The 1.0.0 consumer $consumer failed:`n$($run.Output)" }
        $result[$kind] = [pscustomobject]@{ Out = $out; Output = $run.Output }
    }
    $baselines[$Flags] = $result
    $result
}

try {
    $v1 = Get-Baseline ''
    $v1Project = $v1.Project
    $pack = Invoke-Dotnet (Split-Path $v1Project) @('pack', '-c', 'Release', '-o', $feed)
    if ($pack.ExitCode -ne 0) { throw "The 1.0.0 baseline package did not pack:`n$($pack.Text)" }

    Write-Output ('{0,-28} {1,-8} {2,-8} {3,-26} {4,-26} {5}' -f 'change', 'F# src', 'C# src', 'F# binary', 'C# binary', 'package validation')
    foreach ($case in Get-ChildItem (Join-Path $PSScriptRoot 'changes') -Directory) {
        $source = Join-Path $case.FullName 'Lib.fs'
        $text = Get-Content -Raw $source
        $expect = @{}
        foreach ($m in [regex]::Matches($text, '(?m)^//\s*expect-([\w-]+):\s*(.+?)\s*$')) { $expect[$m.Groups[1].Value] = $m.Groups[2].Value }
        $flags = if ($text -match '(?m)^//\s*flags:\s*(.+?)\s*$') { $Matches[1] } else { '' }
        $v1 = Get-Baseline $flags
        $env:FSHARP_API_PROOF_ROOT = Join-Path $artifacts $case.Name
        $project = New-Lib $case.Name $source '1.1.0' $flags
        $actual = [ordered]@{}

        $v2 = Invoke-Dotnet (Split-Path $project) @('pack', '-c', 'Release', '-o', (Join-Path $work "$($case.Name)/pkg"),
            '-p:EnablePackageValidation=true', '-p:PackageValidationBaselineVersion=1.0.0', "-p:RestoreAdditionalProjectSources=$feed")
        $cp = Get-Codes $v2.Text '(?:error|warning) (CP\d+)'
        $actual['package-validation'] = if ($cp) { $cp -join ',' } elseif ($v2.ExitCode -eq 0) { 'ok' } else { 'pack failed' }
        if ($v2.ExitCode -ne 0 -and -not $cp) { $failures.Add("$($case.Name) did not pack:`n$($v2.Text)"); continue }
        $libDir = Join-Path $work "$($case.Name)/libout"
        $lb = Invoke-Dotnet (Split-Path $project) @('build', '-c', 'Release', '-o', $libDir)
        if ($lb.ExitCode -ne 0) { $failures.Add("$($case.Name) did not build:`n$($lb.Text)"); continue }

        foreach ($kind in $consumers.Keys) {
            $name = $consumers[$kind]
            $dir = New-Consumer $case.Name $name $project
            $out = Join-Path $work "$($case.Name)/out-$kind"
            $b = Invoke-Dotnet $dir @('build', '-c', 'Release', '-o', $out)
            $rebuilt = $null
            if ($b.ExitCode -eq 0) {
                $rebuilt = Invoke-Program $out "$name.dll"
                $actual["source-$kind"] = if ($rebuilt.ExitCode -eq 0) { 'ok' } else { "run failed: $($rebuilt.Exception)" }
            } else {
                $codes = Get-Codes $b.Text $codePattern[$kind]
                $actual["source-$kind"] = if ($codes) { $codes -join ',' } else { 'build failed' }
            }

            $swap = Join-Path $work "$($case.Name)/swap-$kind"
            Copy-Item $v1[$kind].Out $swap -Recurse
            Copy-Item (Join-Path $libDir 'Lib.dll') (Join-Path $swap 'Lib.dll') -Force
            $old = Invoke-Program $swap "$name.dll"
            $actual["binary-$kind"] = if ($old.ExitCode -ne 0) { if ($old.Exception) { $old.Exception } else { "exit $($old.ExitCode)" } }
                elseif ($old.Output -cne $v1[$kind].Output) { 'differs' }
                elseif ($rebuilt -and $rebuilt.ExitCode -eq 0 -and $rebuilt.Output -cne $old.Output) { 'stale' }
                else { 'same' }
        }

        Write-Output ('{0,-28} {1,-8} {2,-8} {3,-26} {4,-26} {5}' -f $case.Name, $actual['source-fs'], $actual['source-cs'], $actual['binary-fs'], $actual['binary-cs'], $actual['package-validation'])
        foreach ($key in $actual.Keys) {
            if (-not $expect.ContainsKey($key)) { $failures.Add("$($case.Name) has no // expect-${key}: line. Actual: $($actual[$key])"); continue }
            if ($expect[$key] -cne $actual[$key]) { $failures.Add("$($case.Name) ${key}: expected $($expect[$key]), actual $($actual[$key]).") }
        }
    }

    foreach ($pin in @(
            @{ Name = 'default FSharp.Core'; Project = $v1Project; Expected = 'SDK' }
            @{ Name = 'FSharp.Core pinned to 6.0.7'; Project = (Join-Path $PSScriptRoot 'LowestCore/LowestCore.fsproj'); Expected = '6.0.7' })) {
        $dir = Join-Path $work "core-$($pin.Expected)"
        $p = Invoke-Dotnet (Split-Path $pin.Project) @('pack', $pin.Project, '-c', 'Release', '-o', $dir)
        if ($p.ExitCode -ne 0) { $failures.Add("$($pin.Name) did not pack:`n$($p.Text)"); continue }
        $nupkg = Get-ChildItem $dir -Filter *.nupkg | Select-Object -First 1
        $zip = [IO.Compression.ZipFile]::OpenRead($nupkg.FullName)
        try {
            $entry = $zip.Entries | Where-Object { $_.FullName -like '*.nuspec' } | Select-Object -First 1
            $reader = [IO.StreamReader]::new($entry.Open())
            $nuspec = $reader.ReadToEnd()
            $reader.Dispose()
        } finally { $zip.Dispose() }
        $version = if ($nuspec -match 'id="FSharp\.Core" version="([^"]+)"') { $Matches[1] } else { 'none' }
        Write-Output ("{0,-28} FSharp.Core dependency {1}" -f $pin.Name, $version)
        $ok = if ($pin.Expected -eq 'SDK') { $version -match '^(\d+)\.' -and [int]$Matches[1] -ge 10 } else { $version -eq $pin.Expected }
        if (-not $ok) { $failures.Add("$($pin.Name): the package depends on FSharp.Core $version. Expected $($pin.Expected).") }
    }
} finally {
    $env:FSHARP_API_PROOF_ROOT = $previousRoot
    $env:NUGET_PACKAGES = $previousPackages
    foreach ($path in $work, $artifacts) {
        if (Test-Path $path) { Remove-Item -Recurse -Force -LiteralPath $path -ErrorAction SilentlyContinue }
    }
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ -ErrorAction Continue }
    exit 1
}
Write-Output 'All library API design proofs passed.'
