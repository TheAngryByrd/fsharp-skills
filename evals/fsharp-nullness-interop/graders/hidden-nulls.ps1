#Requires -Version 7.4
param(
    [Parameter(Mandatory)][string]$Workspace,
    [Parameter(Mandatory)][string]$OutDir,
    [switch]$SkipNative
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../../lib/Grading.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Nullness.psm1') -Force

$checks = @()
$copy = Join-Path $OutDir 'ws'
Copy-Workspace $Workspace $copy
if (-not (Test-Path (Join-Path $copy 'global.json'))) { Set-Content (Join-Path $copy 'global.json') (Get-NullnessGlobalJson) }
$project = Join-Path $copy 'Accounts/Accounts.fsproj'
$source = Join-Path $copy 'Accounts/Accounts.fs'

if (-not (Test-Path $project) -or -not (Test-Path $source)) {
    $checks += New-Check 'Accounts/Accounts.fsproj and Accounts/Accounts.fs exist' $false 'missing'
    Write-Checks (Join-Path $OutDir 'grading.json') $checks
    return
}

$checks += Get-NullnessSettingsCheck $project
$checks += Get-ProjectBuildCheck $project
$checks += Get-SuppressionCheck $copy

$r = Invoke-NullnessDriver -Project $project -Driver (Join-Path $PSScriptRoot 'AccountsDriver.fs') -OutDir $OutDir
$sigOk = $r.Built -and $r.DriverDiagnostics.Count -eq 0
$checks += New-Check 'Function types are unchanged, except the tryEmail return type' $sigOk $(if (-not $r.Built) { Get-LastLines $r.BuildLog } else { $r.DriverDiagnostics -join "`n" })
$checks += Get-BehaviorChecks $r (Join-Path $PSScriptRoot 'hidden-nulls-expected.txt')

Write-Checks (Join-Path $OutDir 'grading.json') $checks
