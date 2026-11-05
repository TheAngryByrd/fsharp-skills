#Requires -Version 7.4
param(
    [Parameter(Mandatory)][string]$Workspace,
    [Parameter(Mandatory)][string]$OutDir,
    [switch]$SkipNative
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../../lib/Grading.psm1') -Force

$expected = Get-Content -Raw (Join-Path $PSScriptRoot 'classify-expected.json') | ConvertFrom-Json
$answer = Read-AnswerJson $Workspace
$changes = if ($answer -and $answer.PSObject.Properties['changes']) { $answer.changes } else { $null }
$checks = @()
$checks += New-Check 'answer.json has a changes object' ($null -ne $changes -and $changes -is [psobject]) $(if (-not $answer) { 'answer.json is missing or is not JSON' })

foreach ($change in $expected.PSObject.Properties) {
    $text = "$($change.Name): each graded result is correct"
    $given = if ($changes -is [psobject] -and $changes.PSObject.Properties[$change.Name]) { $changes.($change.Name) } else { $null }
    if ($null -eq $given) { $checks += New-Check $text $false 'no answer for this change'; continue }
    $wrong = @(foreach ($field in $change.Value.PSObject.Properties) {
            $value = if ($given -is [psobject] -and $given.PSObject.Properties[$field.Name]) { $given.($field.Name) } else { $null }
            if ($value -isnot [bool] -or $value -ne $field.Value) { "$($field.Name): expected $($field.Value.ToString().ToLowerInvariant()), got $(if ($null -eq $value) { 'nothing' } else { "$value".ToLowerInvariant() })" }
        })
    $checks += New-Check $text ($wrong.Count -eq 0) ($wrong -join '; ')
}

Write-Checks (Join-Path $OutDir 'grading.json') $checks
