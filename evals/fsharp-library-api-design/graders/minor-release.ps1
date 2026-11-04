#Requires -Version 7.4
param(
    [Parameter(Mandatory)][string]$Workspace,
    [Parameter(Mandatory)][string]$OutDir,
    [switch]$SkipNative
)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
Import-Module (Join-Path $PSScriptRoot '../../lib/Grading.psm1') -Force

$globalJson = Get-Content -Raw (Join-Path $PSScriptRoot 'global.json')
$surfaceScript = Join-Path $PSScriptRoot '../../../skills/fsharp-signature-files/scripts/public-surface.ps1'
$inputs = Join-Path $PSScriptRoot '../inputs'
$consumers = 'Checkout', 'CheckoutCs'
$expected = @{
    Checkout = @(Get-Content (Join-Path $PSScriptRoot 'checkout-expected.txt') | Where-Object { $_ })
    CheckoutCs = @(Get-Content (Join-Path $PSScriptRoot 'checkoutcs-expected.txt') | Where-Object { $_ })
}
$probes = [ordered]@{
    IdempotencyKey = [pscustomobject]@{
        Build = 'A C# probe that calls client.Charge(request, "order-42") and client.Charge(request) builds against the new Payments'
        Checks = @(
            'A second charge with the same key returns the first receipt and does not call the gateway'
            'A charge with a new key calls the gateway'
            'Charges without a key call the gateway each time')
    }
    AnySequence = [pscustomobject]@{
        Build = 'A C# probe that passes an array and a List<ChargeRequest> to ChargeAll builds against the new Payments'
        Checks = @(
            'ChargeAll charges each request of a C# array'
            'ChargeAll charges each request of a List<ChargeRequest>')
    }
}

function Get-OutputLines($Result) {
    @($Result.Lines | Where-Object { $_ -notmatch ': (warning|error) ' -and $_.Trim() } | ForEach-Object { $_.TrimEnd() })
}

function Test-Output([string]$Name, $Result) {
    $Result.ExitCode -eq 0 -and ((Get-OutputLines $Result) -join "`n") -ceq ($expected[$Name] -join "`n")
}

function Get-BuildErrors($Result) {
    $errors = @($Result.Lines | Where-Object { $_ -match ' error ' } | ForEach-Object { $_ -replace '\s*\[.*$', '' } | Sort-Object -Unique)
    Get-LastLines $(if ($errors) { $errors -join "`n" } else { $Result.Text })
}

$checks = @()

$v1 = Join-Path $OutDir 'v1'
New-Item -ItemType Directory -Force -Path $v1 | Out-Null
Set-Content (Join-Path $v1 'global.json') $globalJson
foreach ($name in @('Payments') + $consumers) { Copy-Item (Join-Path $inputs $name) (Join-Path $v1 $name) -Recurse }
$v1Out = @{}
foreach ($name in $consumers) {
    $out = Join-Path $OutDir "v1-out/$name"
    $r = Invoke-Capture dotnet @('build', '-c', 'Release', '-o', $out) -WorkingDirectory (Join-Path $v1 $name)
    if ($r.ExitCode -ne 0) { throw "The 1.0.0 consumer $name did not build. The grader inputs are broken.`n$($r.Text)" }
    $v1Out[$name] = $out
}

$copy = Join-Path $OutDir 'ws'
Copy-Workspace $Workspace $copy
if (-not (Test-Path (Join-Path $copy 'global.json'))) { Set-Content (Join-Path $copy 'global.json') $globalJson }
$project = Join-Path $copy 'Payments/Payments.fsproj'
if (-not (Test-Path $project)) {
    $checks += New-Check 'Payments/Payments.fsproj exists' $false 'missing'
    Write-Checks (Join-Path $OutDir 'grading.json') $checks
    return
}
foreach ($name in $consumers) {
    $target = Join-Path $copy $name
    if (Test-Path $target) { Remove-Item -Recurse -Force $target }
    Copy-Item (Join-Path $inputs $name) $target -Recurse
}

$newOut = Join-Path $OutDir 'new-out'
$build = Invoke-Capture dotnet @('build', $project, '-c', 'Release', '-o', $newOut) -WorkingDirectory (Split-Path $project)
$newDll = Join-Path $newOut 'Payments.dll'
$built = $build.ExitCode -eq 0 -and (Test-Path $newDll)
$checks += New-Check 'Payments builds' $built $(if (-not $built) { Get-BuildErrors $build })

$version = Invoke-Capture dotnet @('msbuild', $project, '-getProperty:Version') -WorkingDirectory (Split-Path $project)
$versionText = $version.Text.Trim()
$checks += New-Check 'The Payments version is 1.1.0' ($version.ExitCode -eq 0 -and $versionText -eq '1.1.0') "Version: $versionText"

$notesPath = Join-Path $copy 'Payments/RELEASE_NOTES.md'
$notes = if (Test-Path $notesPath) { Get-Content -Raw $notesPath } else { '' }
$checks += New-Check 'RELEASE_NOTES.md has a 1.1.0 entry' ($notes -match '(?m)^#+.*\b1\.1\.0\b') $(if (-not $notes) { 'Payments/RELEASE_NOTES.md is missing' })

foreach ($name in $consumers) {
    $run = Invoke-Capture dotnet @('run', '-c', 'Release') -WorkingDirectory (Join-Path $copy $name)
    $checks += New-Check "The 1.0.0 source of $name builds against the new Payments and prints the same output" (Test-Output $name $run) (Get-LastLines $run.Text)
}

foreach ($name in $consumers) {
    $text = "$name compiled against 1.0.0 runs with the new Payments.dll and prints the same output"
    if (-not $built) { $checks += New-Check $text $null 'skipped: Payments did not build'; continue }
    $swap = Join-Path $OutDir "swap/$name"
    Copy-Item $v1Out[$name] $swap -Recurse
    Copy-Item $newDll (Join-Path $swap 'Payments.dll') -Force
    Get-ChildItem $newOut -Filter *.dll | Where-Object { -not (Test-Path (Join-Path $swap $_.Name)) } | Copy-Item -Destination $swap
    # The host loads only the assemblies that deps.json lists, so a new dependency of Payments needs the app folder probe.
    Remove-Item (Join-Path $swap "$name.deps.json") -Force
    $run = Invoke-Capture dotnet @("$name.dll") -WorkingDirectory $swap
    $checks += New-Check $text (Test-Output $name $run) (Get-LastLines $run.Text)
}

$surfaceChecks = 'No public member of 1.0.0 is removed or changed', 'New public members take no F#-only parameter types (option, list, function, Async, Map, Set) and return no option, function, or Async'
if ($built) {
    $before = @(& $surfaceScript -Assembly (Join-Path $v1Out['Checkout'] 'Payments.dll'))
    $beforeExit = $LASTEXITCODE
    $after = @(& $surfaceScript -Assembly $newDll)
    $afterExit = $LASTEXITCODE
    if ($beforeExit -ne 0 -or $afterExit -ne 0) {
        foreach ($text in $surfaceChecks) { $checks += New-Check $text $null "skipped: public-surface.ps1 failed`n$(Get-LastLines (($before + $after) -join "`n"))" }
    } else {
        $removed = @($before | Where-Object { $after -cnotcontains $_ })
        $checks += New-Check $surfaceChecks[0] ($removed.Count -eq 0) (($removed | ForEach-Object { "removed: $_" }) -join "`n")
        $added = @($after | Where-Object { $before -cnotcontains $_ })
        $anyFSharp = 'Microsoft\.FSharp\.(Core\.FSharp(Option|ValueOption|Func)|Collections\.FSharp(List|Map|Set)|Control\.FSharpAsync)'
        $opaqueResult = 'Microsoft\.FSharp\.(Core\.FSharp(Option|ValueOption|Func)|Control\.FSharpAsync)'
        $fsharpOnly = @($added | Where-Object {
                if ($_ -match '\| [^(]*\((?<params>.*)\) : (?<result>.*)$') { $Matches.params -match $anyFSharp -or $Matches.result -match $opaqueResult }
                elseif ($_ -match '\| new\((?<params>.*)\)$') { $Matches.params -match $anyFSharp }
                elseif ($_ -match '\| [^:]* : (?<result>.*)$') { $Matches.result -match $opaqueResult }
                else { $false }
            })
        $checks += New-Check $surfaceChecks[1] ($fsharpOnly.Count -eq 0) (($fsharpOnly | ForEach-Object { "added: $_" }) -join "`n")
    }
} else {
    foreach ($text in $surfaceChecks) { $checks += New-Check $text $null 'skipped: Payments did not build' }
}

foreach ($name in $probes.Keys) {
    $spec = $probes[$name]
    if (-not $built) {
        $checks += New-Check $spec.Build $null 'skipped: Payments did not build'
        foreach ($text in $spec.Checks) { $checks += New-Check $text $null 'skipped: Payments did not build' }
        continue
    }
    $probeDir = Join-Path $OutDir "probes/$name"
    New-Item -ItemType Directory -Force -Path $probeDir | Out-Null
    Set-Content (Join-Path $probeDir 'global.json') $globalJson
    Copy-Item (Join-Path $PSScriptRoot "probes/$name/Program.cs") $probeDir
    (Get-Content -Raw (Join-Path $PSScriptRoot 'probes/Probe.csproj.txt')).Replace('PAYMENTS_PROJECT', (Resolve-Path $project).Path) |
        Set-Content (Join-Path $probeDir 'Probe.csproj')
    $probeBuild = Invoke-Capture dotnet @('build', 'Probe.csproj', '-c', 'Release', '-o', 'out') -WorkingDirectory $probeDir
    $checks += New-Check $spec.Build ($probeBuild.ExitCode -eq 0) $(if ($probeBuild.ExitCode -ne 0) { Get-BuildErrors $probeBuild })
    if ($probeBuild.ExitCode -ne 0) {
        foreach ($text in $spec.Checks) { $checks += New-Check $text $null 'skipped: the C# probe did not build' }
        continue
    }
    $probe = Invoke-Capture dotnet @('out/Probe.dll') -WorkingDirectory $probeDir
    $results = @(ConvertFrom-ProbeOutput $probe.Lines)
    foreach ($text in $spec.Checks) {
        $hit = @($results | Where-Object text -eq $text) | Select-Object -First 1
        $checks += if ($hit) { $hit } else { New-Check $text $false "the probe printed no result: $(Get-LastLines $probe.Text)" }
    }
}

Write-Checks (Join-Path $OutDir 'grading.json') $checks
