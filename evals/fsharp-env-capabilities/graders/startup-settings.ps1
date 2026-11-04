#Requires -Version 7.4
param(
    [Parameter(Mandatory)][string]$Workspace,
    [Parameter(Mandatory)][string]$OutDir,
    [switch]$SkipNative
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../../lib/Grading.psm1') -Force

$validJson = @'
{ "Shipping": { "Carrier": "Contoso Freight", "MaxWeightKg": 30, "RatePerKg": 1.5, "FreeShippingOver": 100, "BlockedRegions": [ "AQ" ] } }
'@
$noBlockedJson = @'
{ "Shipping": { "Carrier": "Contoso Freight", "MaxWeightKg": 30, "RatePerKg": 1.5, "FreeShippingOver": 100 } }
'@
$zeroFreeJson = @'
{ "Shipping": { "Carrier": "Contoso Freight", "MaxWeightKg": 30, "RatePerKg": 1.5, "FreeShippingOver": 0, "BlockedRegions": [ "AQ" ] } }
'@
$badJson = @'
{ "Shipping": { "Carrier": "", "MaxWeightKg": -5, "BlockedRegions": [ "aq" ] } }
'@
$rangeJson = @'
{ "Shipping": { "Carrier": "Contoso Freight", "MaxWeightKg": 0, "RatePerKg": 0, "FreeShippingOver": -1 } }
'@
$noSectionJson = '{ "Logging": { "Level": "Information" } }'

$validExpected = @(
    'order 1: Contoso Freight 6.00'
    'order 2: Contoso Freight 0.00'
    'order 3: rejected (too heavy)'
    'order 4: rejected (blocked region AQ)'
) -join "`n"
$noBlockedExpected = $validExpected -replace 'order 4: rejected \(blocked region AQ\)', 'order 4: Contoso Freight 1.50'
$zeroFreeExpected = $validExpected -replace 'order 1: Contoso Freight 6\.00', 'order 1: Contoso Freight 0.00'
$testExpected = @(
    'order 1: Test Post 8.00'
    'order 2: rejected (blocked region CA)'
    'order 3: rejected (too heavy)'
    'order 4: Test Post 2.00'
) -join "`n"

function Get-Code([string]$Path) {
    if (-not (Test-Path $Path)) { return $null }
    $text = Get-Content -Raw $Path
    $text = [regex]::Replace($text, '(?s)\(\*.*?\*\)', '')
    [regex]::Replace($text, '(?m)//.*$', '')
}

function Invoke-Scenario([string]$Name, [string]$Script, $Json) {
    $dir = Join-Path $OutDir "run-$Name"
    if (Test-Path $dir) { Remove-Item -Recurse -Force $dir }
    Copy-Workspace -Workspace $Workspace -Destination $dir
    $settings = Join-Path $dir 'appsettings.json'
    if ($null -eq $Json) { Remove-Item -Force -ErrorAction SilentlyContinue $settings }
    else { Set-Content -Path $settings -Value $Json -Encoding utf8 }
    $run = Invoke-Capture dotnet @('fsi', '--nowarn:3535', $Script) -WorkingDirectory $dir
    $orders = @($run.Lines | Where-Object { $_ -match '^order \d+:' } | ForEach-Object { $_.TrimEnd() }) -join "`n"
    $ready = @($run.Lines | Where-Object { $_.Trim() -eq 'ready' }).Count -gt 0
    [pscustomobject]@{ ExitCode = $run.ExitCode; Text = $run.Text; Orders = $orders; Ready = $ready }
}

$checks = @()
$missing = @('Shipping.fsx', 'App.fsx', 'ShippingTests.fsx') | Where-Object { -not (Test-Path (Join-Path $Workspace $_)) }
if ($missing) {
    Write-Checks (Join-Path $OutDir 'grading.json') @(New-Check 'Shipping.fsx, App.fsx, and ShippingTests.fsx exist' $false ($missing -join ', '))
    return
}

$valid = Invoke-Scenario 'valid' 'App.fsx' $validJson
$checks += New-Check 'Valid settings: App.fsx prints ready and the expected quotes' ($valid.ExitCode -eq 0 -and $valid.Ready -and $valid.Orders -eq $validExpected) (Get-LastLines $valid.Text 6)

$noBlocked = Invoke-Scenario 'no-blocked' 'App.fsx' $noBlockedJson
$checks += New-Check 'Settings with no BlockedRegions key run and block no region' ($noBlocked.ExitCode -eq 0 -and $noBlocked.Orders -eq $noBlockedExpected) (Get-LastLines $noBlocked.Text 6)

$zeroFree = Invoke-Scenario 'zero-free' 'App.fsx' $zeroFreeJson
$checks += New-Check 'FreeShippingOver 0 is valid: App.fsx prints ready and quotes 0.00 for each accepted order' ($zeroFree.ExitCode -eq 0 -and $zeroFree.Ready -and $zeroFree.Orders -eq $zeroFreeExpected) (Get-LastLines $zeroFree.Text 6)

$bad = Invoke-Scenario 'bad' 'App.fsx' $badJson
$badStopped = $bad.ExitCode -ne 0 -and -not $bad.Ready -and -not $bad.Orders
$checks += New-Check 'Invalid settings stop App.fsx before it prints ready' $badStopped "exit $($bad.ExitCode), ready $($bad.Ready)`n$(Get-LastLines $bad.Text 6)"
$unnamed = @('Carrier', 'MaxWeightKg', 'RatePerKg', 'BlockedRegions') | Where-Object { $bad.Text -notmatch [regex]::Escape($_) }
$checks += New-Check 'The startup error names Carrier, MaxWeightKg, RatePerKg, and BlockedRegions' ($badStopped -and -not $unnamed) $(if ($unnamed) { "not named: $($unnamed -join ', ')" } else { '' })
$checks += New-Check 'The startup error reports the missing FreeShippingOver key' ($badStopped -and $bad.Text -match 'FreeShippingOver') (Get-LastLines $bad.Text 6)

$range = Invoke-Scenario 'range' 'App.fsx' $rangeJson
$rangeUnnamed = @('MaxWeightKg', 'RatePerKg', 'FreeShippingOver') | Where-Object { $range.Text -notmatch [regex]::Escape($_) }
$rangeStopped = $range.ExitCode -ne 0 -and -not $range.Ready -and -not $range.Orders
$checks += New-Check 'Out-of-range settings stop App.fsx before ready and name MaxWeightKg, RatePerKg, and FreeShippingOver' ($rangeStopped -and -not $rangeUnnamed) "exit $($range.ExitCode), ready $($range.Ready), not named: $($rangeUnnamed -join ', ')`n$(Get-LastLines $range.Text 6)"

$noSection = Invoke-Scenario 'no-section' 'App.fsx' $noSectionJson
$checks += New-Check 'A missing Shipping section stops App.fsx before ready with no NullReferenceException' ($noSection.ExitCode -ne 0 -and -not $noSection.Ready -and -not $noSection.Orders -and $noSection.Text -notmatch 'NullReferenceException') (Get-LastLines $noSection.Text 6)

$test = Invoke-Scenario 'tests' 'ShippingTests.fsx' $null
$checks += New-Check 'ShippingTests.fsx runs with no appsettings.json and prints the expected quotes' ($test.ExitCode -eq 0 -and $test.Orders -eq $testExpected) (Get-LastLines $test.Text 6)

$testCode = Get-Code (Join-Path $Workspace 'ShippingTests.fsx')
$configUse = [regex]::Matches($testCode, '\b(ConfigurationBuilder|ConfigurationManager|ConfigurationBinder|IConfiguration\w*|AddJsonFile|AddInMemoryCollection|GetSection|IOptions\w*|Options\.Create)\b') | ForEach-Object Value | Sort-Object -Unique
$checks += New-Check 'ShippingTests.fsx uses no configuration or Options types' ($configUse.Count -eq 0) ($configUse -join ', ')

$shippingCode = Get-Code (Join-Path $Workspace 'Shipping.fsx')
$optionsUse = [regex]::Matches($shippingCode, '\b(IOptions\w*|IConfiguration\w*)\b') | ForEach-Object Value | Sort-Object -Unique
$checks += New-Check 'No function in Shipping.fsx takes IOptions or IConfiguration' ($optionsUse.Count -eq 0) ($optionsUse -join ', ')

$checks += Invoke-Rubric -Workspace $Workspace -EvalDir (Split-Path $PSScriptRoot) -TaskId 'startup-settings'

Write-Checks (Join-Path $OutDir 'grading.json') $checks
