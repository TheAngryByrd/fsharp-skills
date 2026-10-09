#Requires -Version 7.4
param(
    [Parameter(Mandatory)][string]$Workspace,
    [Parameter(Mandatory)][string]$OutDir,
    [switch]$SkipNative
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../../lib/Grading.psm1') -Force

$checks = @()
$script = Join-Path $Workspace 'Users.fsx'
$expected = (Get-Content (Join-Path $PSScriptRoot 'users-expected.txt')) -join "`n"
if (-not (Test-Path $script)) {
    Write-Checks (Join-Path $OutDir 'grading.json') @(New-Check 'Users.fsx runs under dotnet fsi without errors' $false 'Users.fsx missing')
    return
}
$text = Get-Content -Raw $script

$run = Invoke-Capture dotnet @('fsi', '--nowarn:3535', 'Users.fsx') -WorkingDirectory $Workspace
$errors = @($run.Lines | Select-String -Pattern 'error FS\d+' | ForEach-Object { $_.Line.Trim() })
$checks += New-Check 'Users.fsx runs under dotnet fsi without errors' ($run.ExitCode -eq 0 -and $errors.Count -eq 0) (($errors | Select-Object -First 3) -join "`n")
$fs0064 = @($run.Lines | Select-String -Pattern 'warning FS0064')
$checks += New-Check 'No FS0064 warning remains' ($run.ExitCode -eq 0 -and $fs0064.Count -eq 0) (($fs0064 | Select-Object -First 1) -join '')

$actual = @($run.Lines | Where-Object { $_ -match '^(test|app)' } | ForEach-Object { $_.TrimEnd() }) -join "`n"
$checks += New-Check 'Both envs produce the expected demo output' ($actual -eq $expected) (Get-LastLines $actual 6)

$checks += New-Check 'fetchUser keeps its IWSAM error constraint' ($text -match "fetchUser\s*<[^\r\n=]*\bUserError<'e>") ''
$checks += New-Check 'AppEnv and TestEnv stay separate types' ($text -match 'type\s+AppEnv\b' -and $text -match 'type\s+TestEnv\b') ''
$checks += New-Check 'greetUser leaves env unannotated' ($text -match '(?m)^let\s+greetUser\s+env\s+id\s*=') ''

Write-Checks (Join-Path $OutDir 'grading.json') $checks
