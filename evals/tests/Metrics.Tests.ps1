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

$resolved = @(
    @{ Name = 'claude transcript model'; Agent = 'claude'; Model = 'sonnet'; File = 'claude.jsonl'; Expected = 'claude-test-model' }
    @{ Name = 'claude without model in transcript is unknown, not the alias'; Agent = 'claude'; Model = 'sonnet'; File = 'claude-no-result.jsonl'; Expected = '' }
    @{ Name = 'claude missing transcript is unknown, not the alias'; Agent = 'claude'; Model = 'sonnet'; File = 'none.jsonl'; Expected = '' }
    @{ Name = 'opencode target model'; Agent = 'opencode'; Model = 'provider/model-x'; File = 'opencode.jsonl'; Expected = 'provider/model-x' }
    @{ Name = 'codex config model and effort'; Agent = 'codex'; Model = ''; File = 'codex.jsonl'; Config = 'codex-config.toml'; Expected = 'gpt-test-1 (reasoning effort high)' }
    @{ Name = 'codex target model with config effort'; Agent = 'codex'; Model = 'gpt-explicit'; File = 'codex.jsonl'; Config = 'codex-config.toml'; Expected = 'gpt-explicit (reasoning effort high)' }
    @{ Name = 'codex config without top-level model'; Agent = 'codex'; Model = ''; File = 'codex.jsonl'; Config = 'codex-config-no-model.toml'; Expected = '' }
    @{ Name = 'codex config with a profile and no explicit model is unknown'; Agent = 'codex'; Model = ''; File = 'codex.jsonl'; Config = 'codex-config-profile.toml'; Expected = '' }
    @{ Name = 'codex config with a profile and an explicit model'; Agent = 'codex'; Model = 'gpt-explicit'; File = 'codex.jsonl'; Config = 'codex-config-profile.toml'; Expected = 'gpt-explicit (reasoning effort high)' }
    @{ Name = 'codex config with a single-quoted profile and no explicit model is unknown'; Agent = 'codex'; Model = ''; File = 'codex.jsonl'; Config = 'codex-config-profile-literal.toml'; Expected = '' }
    @{ Name = 'codex config with an unquoted profile and no explicit model is unknown'; Agent = 'codex'; Model = ''; File = 'codex.jsonl'; Config = 'codex-config-profile-bare.toml'; Expected = '' }
    @{ Name = 'codex config with a single-quoted profile and an explicit model'; Agent = 'codex'; Model = 'gpt-explicit'; File = 'codex.jsonl'; Config = 'codex-config-profile-literal.toml'; Expected = 'gpt-explicit (reasoning effort high)' }
    @{ Name = 'codex config with single-quoted model and effort'; Agent = 'codex'; Model = ''; File = 'codex.jsonl'; Config = 'codex-config-literal.toml'; Expected = 'gpt-literal-1 (reasoning effort low)' }
    @{ Name = 'codex missing config'; Agent = 'codex'; Model = ''; File = 'codex.jsonl'; Config = 'none.toml'; Expected = '' }
    @{ Name = 'codex isolated run ignores config'; Agent = 'codex'; Model = ''; File = 'codex.jsonl'; Config = 'codex-config.toml'; Isolated = $true; Expected = '' }
)
foreach ($case in $resolved) {
    $config = if ($case.Config) { Join-Path $fixtures $case.Config } else { '' }
    $actual = Get-ResolvedModel -Agent $case.Agent -Model $case.Model -TranscriptPath (Join-Path $fixtures $case.File) -CodexConfigPath $config -Isolated:([bool]$case.Isolated)
    Assert-Equal $case.Expected $actual "resolved model: $($case.Name)"
}
$initOnly = Join-Path ([IO.Path]::GetTempPath()) "metrics-init-$PID.jsonl"
try {
    Set-Content $initOnly '{"type":"system","subtype":"init","model":"claude-init-only"}' -Encoding utf8
    Assert-Equal 'claude-init-only' (Get-ResolvedModel -Agent claude -Model 'sonnet' -TranscriptPath $initOnly) 'resolved model: claude init event'
} finally { Remove-Item -Force $initOnly }

function New-Run([string]$Mode, $Turns, $FailedBuilds) {
    $run = [ordered]@{ target = 'claude'; resolvedModel = 'claude-test-model'; task = 'fix'; mode = $Mode; skillUsed = $true; passed = 1; failed = 0; skipped = 0; seconds = 10
        inputTokens = 1; outputTokens = 1; checks = @() }
    if ($null -ne $Turns) { $run.turns = $Turns; $run.failedBuilds = $FailedBuilds }
    [pscustomobject]$run
}
$root = Join-Path ([IO.Path]::GetTempPath()) "metrics-tests-$PID"
New-Item -ItemType Directory -Force -Path $root | Out-Null
try {
    $summary = Write-Summary -Root $root -Skill 'demo' -Results @(
        New-Run 'with' 4 0; New-Run 'with' 7 3; New-Run 'without' 12 5; New-Run 'without' $null $null)
    $rows = @($summary -split "`n" | Where-Object { $_ -match '^\| claude \(' })
    Assert-Equal '| claude (claude-test-model) | fix | with | 2 | 100% | 0 | 10 | 2 | 5.5 | 1.5 | 0 |' $rows[0] 'summary with-skill row names the exact model'
    Assert-Equal '| claude (claude-test-model) | fix | without | 2 | 100% | 0 | 10 | 2 | 12.0 | 5.0 | 0 |' $rows[1] 'summary without-skill row names the exact model'
    Assert-Equal $true ($summary -match '(?m)^### claude \(claude-test-model\) \| fix$') 'summary check heading names the exact model'
    $mixed = New-Run 'with' 4 0; $mixed.resolvedModel = 'claude-other-model'
    $unknown = New-Run 'with' 4 0; $unknown.PSObject.Properties.Remove('resolvedModel'); $unknown.target = 'codex'
    $mixedSummary = Write-Summary -Root $root -Skill 'demo' -Results @((New-Run 'with' 4 0), $mixed, $unknown)
    Assert-Equal $true ($mixedSummary -match '(?m)^\| claude \(claude-other-model, claude-test-model\) \| fix \| with \|') 'summary joins the distinct models of one row'
    Assert-Equal $true ($mixedSummary -match '(?m)^\| codex \(model unknown\) \| fix \| with \|') 'summary marks a run without an exact model'
} finally { Remove-Item -Recurse -Force $root }

if ($failures.Count) { $failures | ForEach-Object { Write-Error $_ -ErrorAction Continue }; exit 1 }
