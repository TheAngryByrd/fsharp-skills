#!/usr/bin/env pwsh
#Requires -Version 7.4
<#
.SYNOPSIS
Writes the path-free result set of one eval result folder to evals/results/<skill>/<run-id>.json, ready to commit.

.EXAMPLE
pwsh ./evals/export-results.ps1 -ResultDir $env:TEMP/skill-evals/20261009-154304

.EXAMPLE
pwsh ./evals/export-results.ps1 -ResultDir $env:TEMP/skill-evals/20261009-154304 -ResolvedModel @{ 'claude:sonnet' = 'claude-sonnet-5-5' }
#>
param(
    [Parameter(Mandatory)][string]$ResultDir,
    [hashtable]$ResolvedModel = @{},
    [string]$ResultsRoot = (Join-Path $PSScriptRoot 'results'),
    [string]$UserName = [Environment]::UserName,
    [switch]$Force
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib/Agents.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'lib/Results.psm1') -Force

$dir = (Resolve-Path $ResultDir).Path
$runId = Split-Path $dir -Leaf
if (-not (Test-RunId $runId)) { throw "The result folder name '$runId' is not a run id. Use the name that run-evals.ps1 gave it (yyyyMMdd-HHmmss)." }
$runFiles = @(Get-ChildItem -Path $dir -Directory -Filter 'r*' | ForEach-Object { Join-Path $_.FullName 'run.json' } | Where-Object { Test-Path $_ } | Sort-Object)
if ($runFiles.Count -eq 0) { throw "No r*/run.json found in $dir." }

$skills = [System.Collections.Generic.HashSet[string]]::new()
$projected = foreach ($file in $runFiles) {
    $run = Get-Content -Raw $file | ConvertFrom-Json
    $skill = if ($run.PSObject.Properties['skill'] -and $run.skill) { "$($run.skill)" } else { "$((Find-EvalSpec -EvalsRoot $PSScriptRoot -TaskId $run.task)?.Spec.skill)" }
    if (-not $skill) { throw "Cannot find the skill of $file. No evals.json defines task '$($run.task)'." }
    $null = $skills.Add($skill)
    ConvertTo-ProjectedRun -Run $run -ResolvedModel $ResolvedModel -UserName $UserName
}
if ($skills.Count -ne 1) { throw "A result folder must hold one skill. Found: $($skills -join ', ')." }
$skill = $skills | Select-Object -First 1

$ordered = @($projected | Sort-Object { $_.target }, { $_.task }, { $_.mode }, { [int]$_.run })
$json = (ConvertTo-ResultSetJson -Skill $skill -RunId $runId -Runs $ordered) + "`n"

$out = Join-Path $ResultsRoot "$skill/$runId.json"
if ((Test-Path $out) -and -not $Force -and ([IO.File]::ReadAllText($out) -replace '\r\n', "`n") -ne $json) {
    throw "$out exists with different content. Use -Force to replace it."
}
Write-FileAtomic -Path $out -Content $json
$out
