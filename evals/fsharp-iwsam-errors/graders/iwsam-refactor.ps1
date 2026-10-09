#Requires -Version 7.4
param(
    [Parameter(Mandatory)][string]$Workspace,
    [Parameter(Mandatory)][string]$OutDir,
    [switch]$SkipNative
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../../lib/Grading.psm1') -Force

$checks = @()
$script = Join-Path $Workspace 'Orders.fsx'
$expected = (Get-Content (Join-Path $PSScriptRoot 'orders-expected.txt')) -join "`n"
if (-not (Test-Path $script)) {
    Write-Checks (Join-Path $OutDir 'grading.json') @(New-Check 'Orders.fsx runs under dotnet fsi' $false 'Orders.fsx missing')
    return
}
$text = Get-Content -Raw $script

# The plain command matters: an in-file #nowarn "3535" does not silence the main script under dotnet fsi.
$run = Invoke-Capture dotnet @('fsi', 'Orders.fsx') -WorkingDirectory $Workspace
$errors = @($run.Lines | Select-String -Pattern 'error FS\d+' | ForEach-Object { $_.Line.Trim() })
$checks += New-Check 'Orders.fsx runs under dotnet fsi without errors' ($run.ExitCode -eq 0 -and $errors.Count -eq 0) (($errors | Select-Object -First 3) -join "`n")

$actual = @($run.Lines | Where-Object { $_ -match ' x-?\d+: ' } | ForEach-Object { $_.TrimEnd() }) -join "`n"
$checks += New-Check 'The demo output is unchanged' ($actual -eq $expected) (Get-LastLines $actual 8)

$checks += New-Check 'No Result.mapError remains' ($text -notmatch 'mapError') ''
$interfaces = [regex]::Matches($text, "(?m)^(type|and)\s+\w+\s*<\s*'\w+.*>\s*=\s*\r?\n\s+static\s+abstract").Count
$checks += New-Check 'At least four error leaves are interfaces with static abstract members' ($interfaces -ge 4) "found $interfaces"
$leafSigs = [regex]::Matches($text, "let\s+\w+\s*<\s*'(\w+)\s+when\s+('\1\s*:>\s*)?\w+\s*<\s*'\1\s*>").Count
$checks += New-Check 'At least four leaf functions declare an explicit error constraint' ($leafSigs -ge 4) "found $leafSigs"

Write-Checks (Join-Path $OutDir 'grading.json') $checks
