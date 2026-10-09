#!/usr/bin/env pwsh
#Requires -Version 7.4
<#
.SYNOPSIS
Runs skill eval tasks with Claude Code, Codex, or opencode, with and without the skill, and grades the results.

.EXAMPLE
pwsh ./evals/run-evals.ps1 -Skill fsharp-native-aot -Target claude:sonnet,codex,opencode:github-copilot/gpt-5.5

.EXAMPLE
pwsh ./evals/run-evals.ps1 -Skill fsharp-native-aot -Task diagnose-symptoms -Target claude -Runs 3 -SkipNative
#>
param(
    [Parameter(Mandatory)][string]$Skill,
    [string[]]$Target = @('claude'),
    [string[]]$Task = @(),
    [ValidateSet('both', 'with', 'without')][string]$Mode = 'both',
    [ValidateSet('explicit', 'implicit')][string]$Invocation = 'explicit',
    [ValidateRange(1, 20)][int]$Runs = 1,
    [ValidateRange(1, 240)][int]$TimeoutMinutes = 30,
    [string]$OutputRoot = (Join-Path ([IO.Path]::GetTempPath()) 'skill-evals'),
    [switch]$Isolate,
    [switch]$SkipNative,
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
Import-Module (Join-Path $PSScriptRoot 'lib/Agents.psm1') -Force

$repo = Split-Path $PSScriptRoot
$skillDir = Join-Path $repo "skills/$Skill"
$evalDir = Join-Path $PSScriptRoot $Skill
$evalFile = Join-Path $evalDir 'evals.json'
if (-not (Test-Path (Join-Path $skillDir 'SKILL.md'))) { throw "Skill not found: $skillDir" }
if (-not (Test-Path $evalFile)) { throw "Eval definition not found: $evalFile" }

$spec = Get-Content -Raw $evalFile | ConvertFrom-Json
$tasks = @($spec.tasks | Where-Object { $Task.Count -eq 0 -or $_.id -in $Task })
if ($tasks.Count -eq 0) { throw "No task matches: $($Task -join ', '). Known: $($spec.tasks.id -join ', ')" }
$targets = @($Target | ForEach-Object { $_ -split ',' } | Where-Object { $_ } | ForEach-Object { ConvertTo-AgentTarget $_ })
$modes = if ($Mode -eq 'both') { @('with', 'without') } else { @($Mode) }

foreach ($t in $targets) {
    if (-not $DryRun) { $null = Resolve-AgentCommand $t.Agent }
}

$runId = Get-Date -Format 'yyyyMMdd-HHmmss'
$root = Join-Path $OutputRoot $runId
New-Item -ItemType Directory -Force -Path $root | Out-Null

[object[]]$contamination = @()
if (-not $Isolate) { $contamination = @(Find-ConflictingSkills -Skill $Skill -Keywords @($spec.contaminationKeywords)) }
if ($contamination.Count -gt 0) {
    Write-Warning ("Runs without the skill can load these global skills: " + (($contamination | ForEach-Object { "$($_.Name) ($($_.Path))" }) -join ', '))
    Write-Warning 'Claude baseline runs disable all skills. Use -Isolate to hide global skills from Codex and opencode.'
}

$results = [System.Collections.Generic.List[object]]::new()
$n = 0
foreach ($t in $targets) {
    foreach ($taskSpec in $tasks) {
        foreach ($m in $modes) {
            for ($i = 1; $i -le $Runs; $i++) {
                $n++
                $runDir = Join-Path $root ('r{0:d3}' -f $n)
                $ws = Join-Path $runDir 'ws'
                New-Item -ItemType Directory -Force -Path $ws | Out-Null
                foreach ($f in @($taskSpec.files)) { Copy-Item (Join-Path $evalDir $f) $ws }
                Set-Content -Path (Join-Path $ws 'TASK.md') -Value $taskSpec.prompt -Encoding utf8
                if ($m -eq 'with') { Install-Skill -SkillDir $skillDir -Workspace $ws }
                Initialize-WorkspaceRepo $ws

                $label = "$($t.Label) | $($taskSpec.id) | $m skill | run $i"
                Write-Host "[$n] $label"
                $info = [ordered]@{
                    id = $n; target = $t.Label; agent = $t.Agent; model = $t.Model; task = $taskSpec.id
                    mode = $m; run = $i; invocation = $Invocation; workspace = $ws; isolated = [bool]$Isolate
                }

                $message = Get-AgentMessage -Skill $Skill -WithSkill:($m -eq 'with') -Invocation $Invocation
                $agentRun = Invoke-Agent -Target $t -Workspace $ws -RunDir $runDir -Message $message -WithSkill:($m -eq 'with') `
                    -Isolate:$Isolate -TimeoutMinutes $TimeoutMinutes -DryRun:$DryRun
                $info.command = $agentRun.Command
                if ($DryRun) { $results.Add([pscustomobject]$info); continue }

                $metrics = Get-AgentMetrics -Agent $t.Agent -TranscriptPath $agentRun.Stdout -Skill $Skill
                $info.exitCode = $agentRun.ExitCode
                $info.timedOut = $agentRun.TimedOut
                $info.seconds = [math]::Round($agentRun.Seconds, 1)
                $info.inputTokens = $metrics.InputTokens
                $info.outputTokens = $metrics.OutputTokens
                $info.costUsd = $metrics.CostUsd
                $info.skillUsed = $metrics.SkillUsed

                $gradeDir = Join-Path $runDir 'grade'
                New-Item -ItemType Directory -Force -Path $gradeDir | Out-Null
                $grader = Join-Path $evalDir $taskSpec.grader
                try {
                    & $grader -Workspace $ws -OutDir $gradeDir -SkipNative:$SkipNative | Out-Null
                    $checks = @(Get-Content -Raw (Join-Path $gradeDir 'grading.json') | ConvertFrom-Json)
                } catch {
                    $checks = @([pscustomobject]@{ text = 'Grader completed'; passed = $false; evidence = "$_" })
                }
                $info.checks = $checks
                $info.passed = @($checks | Where-Object { $_.passed -eq $true }).Count
                $info.failed = @($checks | Where-Object { $_.passed -eq $false }).Count
                $info.skipped = @($checks | Where-Object { $null -eq $_.passed }).Count
                $info | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $runDir 'run.json') -Encoding utf8
                if ($m -eq 'with' -and -not $info.skillUsed) { Write-Warning "    The agent did not load $Skill in this run." }
                Write-Host ("    {0}/{1} checks passed, {2} skipped, {3}s, skill used: {4}" -f $info.passed, ($info.passed + $info.failed), $info.skipped, $info.seconds, $info.skillUsed)
                $results.Add([pscustomobject]$info)
            }
        }
    }
}

if ($DryRun) {
    $results | ForEach-Object { "[$($_.id)] $($_.target) | $($_.task) | $($_.mode)`n    $($_.command)" }
    return
}

$summary = Write-Summary -Results $results -Root $root -Skill $Skill -Contamination $contamination
$results | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $root 'results.json') -Encoding utf8
Write-Host ''
Write-Host $summary
Write-Host ''
Write-Host "Results: $root"
