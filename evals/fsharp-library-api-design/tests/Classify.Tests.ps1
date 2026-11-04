#Requires -Version 7.4
$ErrorActionPreference = 'Stop'

$root = Join-Path ([IO.Path]::GetTempPath()) "library-api-design-classify-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
$failures = [System.Collections.Generic.List[string]]::new()
$grader = Join-Path $PSScriptRoot '../graders/classify-changes.ps1'
$expected = Get-Content -Raw (Join-Path $PSScriptRoot '../graders/classify-expected.json') | ConvertFrom-Json

function Invoke-Case([string]$Name, [AllowNull()][string]$Answer) {
    $ws = Join-Path $root "$Name/ws"
    $out = Join-Path $root "$Name/grade"
    New-Item -ItemType Directory -Force -Path $ws, $out | Out-Null
    if ($null -ne $Answer) { Set-Content (Join-Path $ws 'answer.json') $Answer }
    & $grader -Workspace $ws -OutDir $out
    $checks = @(Get-Content -Raw (Join-Path $out 'grading.json') | ConvertFrom-Json)
    $result = @{}
    foreach ($c in $checks) { $result[$c.text] = $c.passed }
    $result
}

function Assert-Case([string]$Case, [hashtable]$Result, [bool]$Shape, [string[]]$Failing) {
    $wrong = @()
    if ($Result['answer.json has a changes object'] -ne $Shape) { $wrong += "shape expected $Shape" }
    foreach ($change in $expected.PSObject.Properties.Name) {
        $want = $Failing -notcontains $change
        if ($Result["${change}: each graded result is correct"] -ne $want) { $wrong += "$change expected $want" }
    }
    if ($wrong) { $failures.Add("${Case}: $($wrong -join '; ')") } else { Write-Host "ok $Case" }
}

function ConvertTo-Answer([scriptblock]$Edit) {
    $changes = [ordered]@{}
    foreach ($change in $expected.PSObject.Properties) {
        $entry = [ordered]@{ fsharpSource = $false; csharpSource = $false; binary = $false; packageValidation = $false }
        foreach ($field in $change.Value.PSObject.Properties) { $entry[$field.Name] = $field.Value }
        $changes[$change.Name] = $entry
    }
    if ($Edit) { & $Edit $changes }
    @{ changes = $changes } | ConvertTo-Json -Depth 5
}

try {
    $all = @($expected.PSObject.Properties.Name)
    Assert-Case 'correct answer' (Invoke-Case 'good' (ConvertTo-Answer)) $true @()
    Assert-Case 'extra field' (Invoke-Case 'extra' (ConvertTo-Answer { param($c) $c['add-bank-transfer'].reason = 'FS0025' })) $true @()
    Assert-Case 'common mistakes' (Invoke-Case 'mistakes' (ConvertTo-Answer {
                param($c)
                $c['tupled-calculate'].binary = $true
                $c['default-currency'].binary = $false
                $c['chargeall-seq'].fsharpSource = $true
            })) $true @('tupled-calculate', 'default-currency', 'chargeall-seq')
    Assert-Case 'string instead of boolean' (Invoke-Case 'strings' (ConvertTo-Answer { param($c) $c['key-overload'].binary = 'false' })) $true @('key-overload')
    Assert-Case 'missing change' (Invoke-Case 'missing' (ConvertTo-Answer { param($c) $c.Remove('gateway-refund') })) $true @('gateway-refund')
    Assert-Case 'no answer.json' (Invoke-Case 'none' $null) $false $all
} finally {
    Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Host "FAIL $_" }
    exit 1
}
Write-Host 'PASS all classification grader cases'
