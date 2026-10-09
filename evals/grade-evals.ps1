#!/usr/bin/env pwsh
#Requires -Version 7.4
<#
.SYNOPSIS
Grades the runs in an existing eval result folder again with the current graders and rebuilds the summary.

.EXAMPLE
pwsh ./evals/grade-evals.ps1 -ResultDir $env:TEMP/skill-evals/20261009-154304
#>
param(
    [Parameter(Mandatory)][string]$ResultDir,
    [string[]]$Task = @(),
    [switch]$SkipNative
)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$Task = @($Task | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
Import-Module (Join-Path $PSScriptRoot 'lib/Agents.psm1') -Force

$results = [System.Collections.Generic.List[object]]::new()
$skill = $null
foreach ($file in Get-ChildItem -Path $ResultDir -Filter 'run.json' -Recurse -Depth 1 | Sort-Object FullName) {
    $run = Get-Content -Raw $file.FullName | ConvertFrom-Json
    $spec = $null
    foreach ($evals in Get-ChildItem -Path $PSScriptRoot -Filter 'evals.json' -Recurse -Depth 1) {
        $candidate = Get-Content -Raw $evals.FullName | ConvertFrom-Json
        if ($candidate.tasks.id -contains $run.task) { $spec = $candidate; $evalDir = $evals.DirectoryName; break }
    }
    if (-not $spec) { throw "No evals.json defines task $($run.task)." }
    $skill = $spec.skill
    if ($Task.Count -eq 0 -or $run.task -in $Task) {
        $taskSpec = $spec.tasks | Where-Object id -eq $run.task
        $gradeDir = Join-Path $file.DirectoryName 'grade'
        Remove-Item -Recurse -Force $gradeDir -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Force -Path $gradeDir | Out-Null
        try {
            & (Join-Path $evalDir $taskSpec.grader) -Workspace $run.workspace -OutDir $gradeDir -SkipNative:$SkipNative | Out-Null
            $checks = @(Get-Content -Raw (Join-Path $gradeDir 'grading.json') | ConvertFrom-Json)
        } catch {
            $checks = @([pscustomobject]@{ text = 'Grader completed'; passed = $false; evidence = "$_" })
        }
        $run.checks = $checks
        $run.passed = @($checks | Where-Object { $_.passed -eq $true }).Count
        $run.failed = @($checks | Where-Object { $_.passed -eq $false }).Count
        $run.skipped = @($checks | Where-Object { $null -eq $_.passed }).Count
        $run | ConvertTo-Json -Depth 6 | Set-Content $file.FullName -Encoding utf8
        Write-Host ("{0} | {1} | {2}: {3}/{4} checks passed" -f $run.target, $run.task, $run.mode, $run.passed, ($run.passed + $run.failed))
    }
    $results.Add($run)
}

$results | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $ResultDir 'results.json') -Encoding utf8
$summary = Write-Summary -Results $results -Root $ResultDir -Skill $skill -Contamination @()
Write-Host ''
Write-Host $summary
