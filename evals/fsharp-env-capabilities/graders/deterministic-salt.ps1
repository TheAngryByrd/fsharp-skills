#Requires -Version 7.4
param(
    [Parameter(Mandatory)][string]$Workspace,
    [Parameter(Mandatory)][string]$OutDir,
    [switch]$SkipNative
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../../lib/Grading.psm1') -Force

$checks = @()
$script = Join-Path $Workspace 'Accounts.fsx'
$expected = (Get-Content (Join-Path $PSScriptRoot 'accounts-expected.txt')) -join "`n"
if (-not (Test-Path $script)) {
    Write-Checks (Join-Path $OutDir 'grading.json') @(New-Check 'Accounts.fsx runs under dotnet fsi without errors' $false 'Accounts.fsx missing')
    return
}
$text = Get-Content -Raw $script

$run = Invoke-Capture dotnet @('fsi', '--nowarn:3535', 'Accounts.fsx') -WorkingDirectory $Workspace
$errors = @($run.Lines | Select-String -Pattern 'error FS\d+' | ForEach-Object { $_.Line.Trim() })
$checks += New-Check 'Accounts.fsx runs under dotnet fsi without errors' ($run.ExitCode -eq 0 -and $errors.Count -eq 0) (($errors | Select-Object -First 3) -join "`n")

$actual = @($run.Lines | Where-Object { $_ -match '^(test |production)' } | ForEach-Object { $_.TrimEnd() }) -join "`n"
$checks += New-Check 'The test env gives the required salt and hash' ($actual -eq $expected) (Get-LastLines $actual 4)

$exposed = [regex]::Matches($text, 'abstract\s+\w+\s*:\s*(System\.)?Random\b') | ForEach-Object Value
$checks += New-Check 'No accessor exposes the System.Random class' ($exposed.Count -eq 0) ($exposed -join '; ')
$subclass = [regex]::Matches($text, 'inherit\s+(System\.)?Random\b|new\s+(System\.)?Random\s*\(\s*\)\s*with\b') | ForEach-Object Value
$checks += New-Check 'The fake does not subclass System.Random' ($subclass.Count -eq 0) ($subclass -join '; ')

$testEnv = [regex]::Match($text, '(?ms)^type\s+TestEnv\b.*?(?=^\S)')
$checks += New-Check 'TestEnv exists and does not implement IProvideClock' ($testEnv.Success -and $testEnv.Value -notmatch 'IProvideClock') $(if ($testEnv.Success) { '' } else { 'TestEnv missing' })

Write-Checks (Join-Path $OutDir 'grading.json') $checks
