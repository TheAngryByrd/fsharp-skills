#Requires -Version 7.4
param(
    [Parameter(Mandatory)][string]$Workspace,
    [Parameter(Mandatory)][string]$OutDir,
    [switch]$SkipNative
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../../lib/Grading.psm1') -Force

$checks = @()
$script = Join-Path $Workspace 'Checkout.fsx'
$expected = (Get-Content (Join-Path $PSScriptRoot 'checkout-expected.txt')) -join "`n"
if (-not (Test-Path $script)) {
    Write-Checks (Join-Path $OutDir 'grading.json') @(New-Check 'Checkout.fsx runs under dotnet fsi' $false 'Checkout.fsx missing')
    return
}
$text = Get-Content -Raw $script

$run = Invoke-Capture dotnet @('fsi', '--nowarn:3535', 'Checkout.fsx') -WorkingDirectory $Workspace
$errors = @($run.Lines | Select-String -Pattern 'error FS\d+' | ForEach-Object { $_.Line.Trim() })
$checks += New-Check 'Checkout.fsx runs under dotnet fsi without errors' ($run.ExitCode -eq 0 -and $errors.Count -eq 0) (($errors | Select-Object -First 3) -join "`n")

$actual = @($run.Lines | Where-Object { $_ -match ' x\d+: |^smoke test:' } | ForEach-Object { $_.TrimEnd() }) -join "`n"
$checks += New-Check 'The demo prints the expected outcome for every case' ($actual -eq $expected) (Get-LastLines $actual 8)

$checks += New-Check 'No Result.mapError is added' ($text -notmatch 'mapError') ''
$checks += New-Check 'ApiError still implements the error interfaces' ($text -match 'interface\s+SkuError<ApiError>' -and $text -match 'interface\s+StockError<ApiError>' -and $text -match 'interface\s+PaymentError<ApiError>') ''
$checks += New-Check 'The CardExpired case stays in PaymentError' ($text -match 'static\s+abstract\s+CardExpired') ''
$checks += New-Check 'reserveStock declares its error constraint explicitly' ($text -match "reserveStock\s*<\s*'e\s+when\s+StockError<'e>") ''

Write-Checks (Join-Path $OutDir 'grading.json') $checks
