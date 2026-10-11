#!/usr/bin/env pwsh
#Requires -Version 7.4
param()
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../lib/Agents.psm1') -Force
$fixtures = Join-Path $PSScriptRoot 'fixtures'
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Equal($Expected, $Actual, [string]$Name) {
    if ($Expected -ne $Actual) { $failures.Add("${Name}: expected '$Expected', got '$Actual'") }
}

$cases = @(
    @{ Agent = 'claude'; Turns = 6; FailedBuilds = 3 }
    @{ Agent = 'codex'; Turns = 12; FailedBuilds = 4 }
    @{ Agent = 'opencode'; Turns = 3; FailedBuilds = 3 }
    @{ Agent = 'claude'; File = 'claude-no-result'; Turns = 7; FailedBuilds = 3 }
    @{ Agent = 'claude'; File = 'empty'; Turns = $null; FailedBuilds = $null }
    @{ Agent = 'codex'; File = 'empty'; Turns = $null; FailedBuilds = $null }
    @{ Agent = 'opencode'; File = 'empty'; Turns = $null; FailedBuilds = $null }
)
foreach ($case in $cases) {
    $file = if ($case.File) { $case.File } else { $case.Agent }
    $m = Get-AgentMetrics -Agent $case.Agent -TranscriptPath (Join-Path $fixtures "$file.jsonl") -Skill 'demo'
    Assert-Equal $case.Turns $m.Turns "$($case.Agent) $file turns"
    Assert-Equal $case.FailedBuilds $m.FailedBuilds "$($case.Agent) $file failed builds"
}

$missing = Get-AgentMetrics -Agent 'claude' -TranscriptPath (Join-Path $fixtures 'none.jsonl') -Skill 'demo'
Assert-Equal $null $missing.Turns 'missing transcript turns'
Assert-Equal $null $missing.FailedBuilds 'missing transcript failed builds'

function New-Run([string]$Mode, $Turns, $FailedBuilds) {
    $run = [ordered]@{ target = 'claude'; task = 'fix'; mode = $Mode; skillUsed = $true; passed = 1; failed = 0; skipped = 0; seconds = 10
        inputTokens = 1; outputTokens = 1; checks = @() }
    if ($null -ne $Turns) { $run.turns = $Turns; $run.failedBuilds = $FailedBuilds }
    [pscustomobject]$run
}
$root = Join-Path ([IO.Path]::GetTempPath()) "metrics-tests-$PID"
New-Item -ItemType Directory -Force -Path $root | Out-Null
try {
    $summary = Write-Summary -Root $root -Skill 'demo' -Results @(
        New-Run 'with' 4 0; New-Run 'with' 7 3; New-Run 'without' 12 5; New-Run 'without' $null $null)
    $rows = @($summary -split "`n" | Where-Object { $_ -match '^\| claude \| fix \|' })
    Assert-Equal '| claude | fix | with | 2 | 100% | 0 | 10 | 2 | 5.5 | 1.5 | 0 |' $rows[0] 'summary with-skill row'
    Assert-Equal '| claude | fix | without | 2 | 100% | 0 | 10 | 2 | 12.0 | 5.0 | 0 |' $rows[1] 'summary without-skill row'
} finally { Remove-Item -Recurse -Force $root }

if ($failures.Count) { $failures | ForEach-Object { Write-Error $_ -ErrorAction Continue }; exit 1 }
