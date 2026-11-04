#Requires -Version 7.4
param(
    [Parameter(Mandatory)][string]$Workspace,
    [Parameter(Mandatory)][string]$OutDir,
    [switch]$SkipNative,
    [string]$LegacySource = (Join-Path $PSScriptRoot '../inputs/LegacyApp/Program.fs'),
    [string]$AppName = 'LegacyApp',
    [bool]$StatusOfReturnsHeld = $true
)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
Import-Module (Join-Path $PSScriptRoot '../../lib/Grading.psm1') -Force

$inputs = Join-Path $PSScriptRoot '../inputs'
$globalJson = Get-Content -Raw (Join-Path $PSScriptRoot 'global.json')
$missing = 'MissingMethodException|TypeLoadException|MissingFieldException|EntryPointNotFoundException'

$names = [ordered]@{
    build   = 'Shipping builds'
    version = 'The Shipping version is 1.1.0'
    load    = "$AppName compiled against 1.0.0 runs with the new Shipping.dll with no MissingMethodException, TypeLoadException, or MissingFieldException"
    output  = "$AppName compiled against 1.0.0 prints the same output with the new Shipping.dll"
    compat  = 'apicompat finds no break from Shipping 1.0.0'
    newapp  = 'NewApp references Shipping and prints the requested lines for express, insurance, and Held'
    tool    = 'The transcript shows an automated compatibility check: package validation, apicompat, or an F# signature diff'
}
# The baseline package is on no feed. Without this, restore of a project with package validation fails with NU1101.
$noBaseline = '-p:DisablePackageBaselineValidation=true'
. (Join-Path $PSScriptRoot 'CompatibilityCommand.ps1')

$checks = @()
$copy = Join-Path $OutDir 'ws'
$build = Join-Path $OutDir 'build'
Copy-Workspace $Workspace $copy
if (-not (Test-Path (Join-Path $copy 'global.json'))) { Set-Content (Join-Path $copy 'global.json') $globalJson }
$released = Join-Path $build 'release-1.0.0'
Copy-Item (Join-Path $inputs 'release-1.0.0') $released -Recurse
Set-Content (Join-Path $build 'global.json') $globalJson
Copy-Item (Join-Path $PSScriptRoot 'legacy') (Join-Path $build 'legacy') -Recurse
Copy-Item $LegacySource (Join-Path $build 'legacy/Program.fs')
$legacyProject = Join-Path $build 'legacy/LegacyApp.fsproj'

function Invoke-Run([string]$Dll) {
    $r = Invoke-Capture dotnet @($Dll) -WorkingDirectory $build
    [pscustomobject]@{ ExitCode = $r.ExitCode; Text = $r.Text; Output = (($r.Lines | ForEach-Object { $_.TrimEnd() }) -join "`n").Trim() }
}

$v1Dir = Join-Path $build 'shipping-1.0.0'
$v1 = Invoke-Capture dotnet @('build', (Join-Path $released 'Shipping/Shipping.fsproj'), '-c', 'Release', '-o', $v1Dir, '-nologo') -WorkingDirectory $released
$legacyDir = Join-Path $build 'legacy-1.0.0'
$legacy = Invoke-Capture dotnet @('build', $legacyProject, '-c', 'Release', '-o', $legacyDir, '-nologo', "-p:ShippingDll=$(Join-Path $v1Dir 'Shipping.dll')") -WorkingDirectory (Split-Path $legacyProject)
if ($v1.ExitCode -ne 0 -or $legacy.ExitCode -ne 0) { throw "The grader could not build Shipping 1.0.0 and LegacyApp:`n$($v1.Text)`n$($legacy.Text)" }
$baseline = Invoke-Run (Join-Path $legacyDir 'LegacyApp.dll')
if ($baseline.ExitCode -ne 0) { throw "$AppName failed against Shipping 1.0.0:`n$($baseline.Text)" }

$project = Join-Path $copy 'Shipping/Shipping.fsproj'
$newDir = Join-Path $build 'shipping-new'
$built = $false
$versionText = ''
if (Test-Path $project) {
    $lib = Invoke-Capture dotnet @('build', $project, '-c', 'Release', '-o', $newDir, '-nologo', $noBaseline) -WorkingDirectory (Split-Path $project)
    $built = $lib.ExitCode -eq 0 -and (Test-Path (Join-Path $newDir 'Shipping.dll'))
    $checks += New-Check $names.build $built $(if (-not $built) { Get-LastLines (($lib.Lines | Where-Object { $_ -match ': error ' } | Sort-Object -Unique) -join "`n") })
    $version = Invoke-Capture dotnet @('msbuild', $project, '-getProperty:Version') -WorkingDirectory (Split-Path $project)
    if ($version.ExitCode -eq 0) { $versionText = $version.Text.Trim() }
} else {
    $checks += New-Check $names.build $false 'Shipping/Shipping.fsproj is missing'
}
$checks += New-Check $names.version ($versionText -eq '1.1.0') "Version: '$versionText'"

if ($built) {
    $oldDir = Join-Path $build 'legacy-with-new'
    Copy-Item $legacyDir $oldDir -Recurse
    Copy-Item (Join-Path $newDir 'Shipping.dll') (Join-Path $oldDir 'Shipping.dll') -Force
    $old = Invoke-Run (Join-Path $oldDir 'LegacyApp.dll')
    $loadError = $old.Text -match $missing
    $checks += New-Check $names.load (-not $loadError -and $old.ExitCode -eq 0) (Get-LastLines $old.Text 6)
    $same = $old.ExitCode -eq 0 -and $old.Output -ceq $baseline.Output
    $diff = if (-not $same) { (Compare-Object ($baseline.Output -split "`n") ($old.Output -split "`n") | ForEach-Object { "$($_.SideIndicator) $($_.InputObject)" }) -join "`n" } else { '' }
    $checks += New-Check $names.output $same $diff

    $restore = Invoke-Capture dotnet @('tool', 'restore') -WorkingDirectory $PSScriptRoot
    if ($restore.ExitCode -ne 0) {
        $checks += New-Check $names.compat $null "skipped: dotnet tool restore failed: $(Get-LastLines $restore.Text 3)"
    } else {
        $compat = Invoke-Capture dotnet @('apicompat', '--left', (Join-Path $v1Dir 'Shipping.dll'), '--right', (Join-Path $newDir 'Shipping.dll')) -WorkingDirectory $PSScriptRoot
        $clean = $compat.ExitCode -eq 0 -and $compat.Text -match 'without finding any breaking changes'
        $checks += New-Check $names.compat $clean (Get-LastLines (($compat.Lines | Where-Object { $_ -match 'CP\d{4}|without finding' }) -join "`n") 8)
    }
} else {
    foreach ($key in 'load', 'output', 'compat') { $checks += New-Check $names[$key] $null 'skipped: Shipping does not build' }
}

$newApp = Join-Path $copy 'NewApp/NewApp.fsproj'
if ($built -and (Test-Path $newApp)) {
    $refs = Invoke-Capture dotnet @('msbuild', $newApp, '-getItem:ProjectReference') -WorkingDirectory (Split-Path $newApp)
    $usesShipping = $refs.ExitCode -eq 0 -and $refs.Text -match 'Shipping\.fsproj'
    $run = Invoke-Capture dotnet @('run', '-c', 'Release', $noBaseline) -WorkingDirectory (Split-Path $newApp)
    $lines = @($run.Lines | Where-Object { $_ -notmatch ': (warning|error) ' -and $_.Trim() } | ForEach-Object { $_.TrimEnd() })
    $expected = @(Get-Content (Join-Path $PSScriptRoot 'newapp-expected.txt') | Where-Object { $_ })
    $source = (Get-ChildItem (Split-Path $newApp) -Recurse -File -Filter *.fs | Where-Object { $_.FullName -notmatch '[\\/](bin|obj)[\\/]' } | ForEach-Object { Get-Content -Raw $_.FullName }) -join "`n"
    $hardcoded = @([regex]::Matches($source, '(?<![\d.])(6\.90?|13\.80?|13\.50?)(?![\d])') | ForEach-Object { $_.Value })
    $features = @(ConvertFrom-ProbeOutput (Invoke-Capture dotnet @('fsi', '--nologo', (Join-Path $PSScriptRoot 'FeatureProbe.fsx'), (Join-Path $oldDir 'Shipping.dll')) -WorkingDirectory $PSScriptRoot).Lines)
    $feature = { param($name) [bool](@($features | Where-Object { $_.text -eq $name -and $_.passed }).Count) }
    $env:SHIPPING_PROBE_DIR = $oldDir
    try {
        $statusProbe = Invoke-Capture pwsh @('-NoProfile', '-Command', '[void][Reflection.Assembly]::LoadFrom((Join-Path $env:SHIPPING_PROBE_DIR "FSharp.Core.dll")); $r = [Reflection.Assembly]::LoadFrom((Join-Path $env:SHIPPING_PROBE_DIR "Shipping.dll")).GetType("Shipping").GetMethod("statusOf").Invoke($null, @("HD")); [bool]($null -ne $r -and $r.Value.IsHeld)') -WorkingDirectory $build
    } finally { Remove-Item Env:SHIPPING_PROBE_DIR -ErrorAction SilentlyContinue }
    $statusOfHeld = $statusProbe.Text.Trim() -eq 'True'
    $problems = @(
        if (-not $usesShipping) { 'NewApp has no ProjectReference to Shipping.fsproj.' }
        if ($hardcoded.Count) { "NewApp source holds result values: $($hardcoded -join ', ')." }
        if (-not (& $feature 'express')) { 'No public Shipping function, Parcel member, or class method gives the express price 13.80 for P1.' }
        if (-not (& $feature 'insured')) { 'No public Shipping function, Parcel member, or class method gives the insured price 13.50 for P4 with a declared value of 300.00.' }
        if (-not (& $feature 'reads HD as Held')) { 'No public Shipping function or class method reads HD as Held.' }
        if ($StatusOfReturnsHeld -and -not $statusOfHeld) { 'statusOf "HD" does not return Held.' }
    )
    $checks += New-Check $names.newapp ($problems.Count -eq 0 -and $run.ExitCode -eq 0 -and ($lines -join "`n") -ceq ($expected -join "`n")) "$($problems -join ' ') $(Get-LastLines $run.Text 8)".Trim()
} elseif ($built) {
    $checks += New-Check $names.newapp $false 'NewApp/NewApp.fsproj is missing'
} else {
    $checks += New-Check $names.newapp $null 'skipped: Shipping does not build'
}

$transcript = Join-Path (Split-Path $OutDir) 'transcript.jsonl'
if (Test-Path $transcript) {
    $validates = @(Get-ChildItem $copy -Recurse -File -Include *.fsproj, Directory.Build.props |
            Where-Object { $t = Get-Content -Raw $_.FullName; $t -match '<EnablePackageValidation>\s*true' -and $t -match '<PackageValidationBaseline(?:Version|Path)>' }).Count -gt 0
    # A shell call can skip a tool (false && apicompat ...) and still exit 0, so a comparison counts only when the tool's own result text is in the output.
    $results = @(Get-TranscriptCommandResults $transcript)
    $compared = '(?m)APICompat ran successfully|API compatibility errors|API breaking changes found|CP\d{4}|No F# signature change|The F# signature changed|Successfully created package|^@@ .* @@|^[+-]\s*val '
    $tools = @($results | Where-Object { $_.Output -match $compared -and (Test-CompatibilityCommand $_.Command $validates) } | ForEach-Object { $_.Command } | Select-Object -Unique)
    $signatureBuilds = @($results | Where-Object { -not $_.Failed } | ForEach-Object { Get-SignatureBuilds $_.Command })
    $baselineBuild = $signatureBuilds | Where-Object Baseline | Select-Object -First 1
    $newBuild = $signatureBuilds | Where-Object { -not $_.Baseline } | Select-Object -First 1
    $tools += @(if ($baselineBuild -and $newBuild) { $baselineBuild.Segment, $newBuild.Segment })
    $checks += New-Check $names.tool ($tools.Count -gt 0) (($tools | Select-Object -First 3) -join "`n")
} else {
    $checks += New-Check $names.tool $null 'skipped: no transcript.jsonl next to the grade folder'
}

Write-Checks (Join-Path $OutDir 'grading.json') $checks
