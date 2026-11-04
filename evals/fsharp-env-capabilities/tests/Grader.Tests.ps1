#Requires -Version 7.4
$ErrorActionPreference = 'Stop'

$root = Join-Path ([IO.Path]::GetTempPath()) "env-capabilities-grader-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
$failures = [System.Collections.Generic.List[string]]::new()
$judge = $env:SKILL_EVAL_JUDGE
$env:SKILL_EVAL_JUDGE = 'off'

$names = @(
    'Valid settings: App.fsx prints ready and the expected quotes'
    'Settings with no BlockedRegions key run and block no region'
    'FreeShippingOver 0 is valid: App.fsx prints ready and quotes 0.00 for each accepted order'
    'Invalid settings stop App.fsx before it prints ready'
    'The startup error names Carrier, MaxWeightKg, RatePerKg, and BlockedRegions'
    'The startup error reports the missing FreeShippingOver key'
    'Out-of-range settings stop App.fsx before ready and name MaxWeightKg, RatePerKg, and FreeShippingOver'
    'A missing Shipping section stops App.fsx before ready with no NullReferenceException'
    'ShippingTests.fsx runs with no appsettings.json and prints the expected quotes'
    'ShippingTests.fsx uses no configuration or Options types'
    'No function in Shipping.fsx takes IOptions or IConfiguration'
)

function Invoke-Case([string]$Name, [string[]]$Overlays, [scriptblock]$Edit) {
    $ws = Join-Path $root "$Name/ws"
    $out = Join-Path $root "$Name/grade"
    New-Item -ItemType Directory -Force -Path $ws, $out | Out-Null
    Copy-Item (Join-Path $PSScriptRoot '../inputs/shipping/*') $ws
    foreach ($overlay in $Overlays) { Copy-Item (Join-Path $PSScriptRoot "$overlay/*") $ws -Force }
    if ($Edit) { & $Edit $ws }
    & (Join-Path $PSScriptRoot '../graders/startup-settings.ps1') -Workspace $ws -OutDir $out
    @(Get-Content -Raw (Join-Path $out 'grading.json') | ConvertFrom-Json | Where-Object { $_.text -notlike 'Rubric *' })
}

function Assert-Checks([string]$Case, $Checks, [bool[]]$Expected) {
    $actual = @{}
    foreach ($c in $Checks) { $actual[$c.text] = $c.passed }
    $wrong = @(for ($i = 0; $i -lt $names.Count; $i++) { if ($actual[$names[$i]] -ne $Expected[$i]) { $names[$i] } })
    if ($wrong.Count -gt 0 -or $actual.Count -ne $names.Count -or $Expected.Count -ne $names.Count) {
        $detail = ($Checks | ForEach-Object { "  [$($_.passed)] $($_.text) $($_.evidence)" }) -join "`n"
        $failures.Add("${Case}: unexpected checks: $($wrong -join '; ')`n$detail")
    }
}

function Edit-File([string]$Path, [string]$Pattern, [string]$Replacement) {
    $text = Get-Content -Raw $Path
    $edited = [regex]::Replace($text, $Pattern, $Replacement)
    if ($edited -eq $text) { throw "Pattern not found in ${Path}: $Pattern" }
    Set-Content -Path $Path -Value $edited -NoNewline
}

$validateLate = {
    param($ws)
    Edit-File (Join-Path $ws 'App.fsx') '(?s)try\s+provider\.GetRequiredService<IStartupValidator>\(\)\.Validate\(\).*?exit 1\s+' ''
}
$firstErrorOnly = {
    param($ws)
    Edit-File (Join-Path $ws 'App.fsx') 'for failure in e\.Failures do\s+eprintfn "  %s" failure' 'eprintfn "  %s" (Seq.head e.Failures)'
}
$decimalDefault = {
    param($ws)
    $shipping = Join-Path $ws 'Shipping.fsx'
    Edit-File $shipping 'FreeShippingOver: Nullable<decimal>' 'FreeShippingOver: decimal'
    Edit-File $shipping '(?s)if not dto\.FreeShippingOver\.HasValue then .*?else Ok dto\.FreeShippingOver\.Value' 'if dto.FreeShippingOver < 0m then Error "FreeShippingOver must be 0 or more" else Ok dto.FreeShippingOver'
}
$zeroRejected = {
    param($ws)
    Edit-File (Join-Path $ws 'Shipping.fsx') 'elif dto\.FreeShippingOver\.Value < 0m then' 'elif dto.FreeShippingOver.Value <= 0m then'
}
$rangeSkipped = {
    param($ws)
    $shipping = Join-Path $ws 'Shipping.fsx'
    Edit-File $shipping 'and! rate = positive "RatePerKg" dto\.RatePerKg' 'and! rate = (if dto.RatePerKg.HasValue then Ok dto.RatePerKg.Value else Error "RatePerKg is required")'
    Edit-File $shipping '\s+elif dto\.FreeShippingOver\.Value < 0m then Error "FreeShippingOver must be 0 or more"' ''
}
$maxWeightZeroAllowed = {
    param($ws)
    Edit-File (Join-Path $ws 'Shipping.fsx') 'and! maxWeight = positive "MaxWeightKg" dto\.MaxWeightKg' 'and! maxWeight = (if not dto.MaxWeightKg.HasValue then Error "MaxWeightKg is required" elif dto.MaxWeightKg.Value < 0m then Error "MaxWeightKg must be 0 or more" else Ok dto.MaxWeightKg.Value)'
}
$testReadsSettings = {
    param($ws)
    Edit-File (Join-Path $ws 'ShippingTests.fsx') '^#load "Shipping\.fsx"' "#load ""Shipping.fsx""`nif System.IO.File.Exists(System.IO.Path.Combine(__SOURCE_DIRECTORY__, ""appsettings.json"")) then failwith ""appsettings.json exists"""
}

try {
    Assert-Checks 'good' (Invoke-Case 'good' @('startup-settings-good')) (@($true) * 11)
    Assert-Checks 'input with Options.Create test' (Invoke-Case 'options' @('startup-settings-options')) @($true, $false, $true, $false, $false, $false, $false, $false, $true, $false, $false)
    Assert-Checks 'ValidateOnStart with no startup validator call' (Invoke-Case 'late' @('startup-settings-good') $validateLate) @($true, $true, $true, $false, $false, $false, $false, $false, $true, $true, $true)
    Assert-Checks 'only the first error printed' (Invoke-Case 'first-error' @('startup-settings-good') $firstErrorOnly) @($true, $true, $true, $true, $false, $false, $false, $true, $true, $true, $true)
    Assert-Checks 'FreeShippingOver bound as decimal' (Invoke-Case 'decimal' @('startup-settings-good') $decimalDefault) @($true, $true, $true, $true, $true, $false, $true, $true, $true, $true, $true)
    Assert-Checks 'test that fails when appsettings.json exists' (Invoke-Case 'test-reads-settings' @('startup-settings-good') $testReadsSettings) (@($true) * 11)
    Assert-Checks 'FreeShippingOver 0 rejected' (Invoke-Case 'zero-rejected' @('startup-settings-good') $zeroRejected) @($true, $true, $false, $true, $true, $true, $true, $true, $true, $true, $true)
    Assert-Checks 'MaxWeightKg 0 accepted' (Invoke-Case 'max-weight-zero' @('startup-settings-good') $maxWeightZeroAllowed) @($true, $true, $true, $true, $true, $true, $false, $true, $true, $true, $true)
    Assert-Checks 'RatePerKg and FreeShippingOver ranges skipped' (Invoke-Case 'range-skipped' @('startup-settings-good') $rangeSkipped) @($true, $true, $true, $true, $true, $true, $false, $true, $true, $true, $true)
} finally {
    $env:SKILL_EVAL_JUDGE = $judge
    Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Host $_ }
    exit 1
}
Write-Host 'All startup-settings grader cases passed.'
