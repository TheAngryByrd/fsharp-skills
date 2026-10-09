#Requires -Version 7.4
param(
    [Parameter(Mandatory)][string]$Workspace,
    [Parameter(Mandatory)][string]$OutDir,
    [switch]$SkipNative
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../../lib/Grading.psm1') -Force

# Verified by publishing inputs/Formatting.fs and comparing JIT output with native exe output.
$key = [ordered]@{
    L1 = 'works'; L2 = 'throws'; L3 = 'works'; L4 = 'works'; L5 = 'works'; L6 = 'loses data'
    L7 = 'loses data'; L8 = 'throws'; L9 = 'works'; L10 = 'works'; L11 = 'loses data'; L12 = 'throws'
    L13 = 'works'; L14 = 'works'; L15 = 'loses data'; L16 = 'loses data'; L17 = 'works'
}

function ConvertTo-Verdict([string]$Value) {
    $v = "$Value".Trim().ToLowerInvariant() -replace '[-_]', ' '
    if ($v -match '^lose') { 'loses data' } else { $v }
}

$checks = @()
$answer = Read-AnswerJson $Workspace
$rows = @{}
if ($answer -and $answer.PSObject.Properties['lines']) {
    foreach ($row in @($answer.lines)) { $rows["$($row.line)".Trim().ToUpperInvariant()] = $row }
}
$checks += New-Check 'answer.json lists all 17 lines' ($rows.Count -eq 17 -and @($key.Keys | Where-Object { -not $rows.ContainsKey($_) }).Count -eq 0) "found $($rows.Count) lines"

foreach ($group in 'throws', 'loses data', 'works') {
    $lines = @($key.Keys | Where-Object { $key[$_] -eq $group })
    $wrong = @($lines | Where-Object { -not $rows.ContainsKey($_) -or (ConvertTo-Verdict $rows[$_].verdict) -ne $group })
    $detail = ($wrong | ForEach-Object { "$_=$(if ($rows.ContainsKey($_)) { ConvertTo-Verdict $rows[$_].verdict } else { 'missing' })" }) -join ', '
    $checks += New-Check "Lines expected as '$group' ($($lines -join ', ')) are classified '$group'" ($wrong.Count -eq 0) $detail
}

$throwing = @($key.Keys | Where-Object { $key[$_] -eq 'throws' })
$bad = @($throwing | Where-Object {
    $c = if ($rows.ContainsKey($_)) { "$($rows[$_].change)" } else { '' }
    -not ($c -match '\$"' -and $c -notmatch '(sprintf|failwithf|printfn)\s+"')
})
$checks += New-Check 'Each throwing line changes to an interpolated string, not a classic format string' ($bad.Count -eq 0) ($bad -join ', ')

# Text rules for verified fixes. Status and Code need a ToString override, and Envelope needs its own override because %A ignores the union override.
$lossRules = [ordered]@{
    L6  = 'override\s+\w+\s*\.\s*ToString'
    L7  = 'fst|snd|let\s*\(?\s*\w+\s*,\s*\w+\s*\)?\s*=\s*pair|match\s+pair|\{\s*pair\s*\}|string\s+pair\b|pair\.ToString\(\)'
    L11 = '(?s-i)type\s+Envelope\b(?:(?!\btype\s).)*override\s+\w+\s*\.\s*ToString|(?s-i)override\s+\w+\s*\.\s*ToString.*\.Id\b'
    L15 = 'string\s+c\b|c\.ToString\(\)|\{\s*c\s*\}'
    L16 = 'override\s+\w+\s*\.\s*ToString'
}
$badLoss = @($lossRules.Keys | Where-Object {
    $c = if ($rows.ContainsKey($_)) { "$($rows[$_].change)" } else { '' }
    $c -match '%\+?A' -or $c -notmatch $lossRules[$_]
})
$checks += New-Check 'Each data-loss line has a fix that keeps the lost content' ($badLoss.Count -eq 0) ($badLoss -join ', ')

$works = @($key.Keys | Where-Object { $key[$_] -eq 'works' })
$touched = @($works | Where-Object { $rows.ContainsKey($_) -and "$($rows[$_].change)".Trim() -ne '' })
$checks += New-Check 'Lines that work are left unchanged' ($rows.Count -gt 0 -and $touched.Count -eq 0) ($touched -join ', ')

Write-Checks (Join-Path $OutDir 'grading.json') $checks
