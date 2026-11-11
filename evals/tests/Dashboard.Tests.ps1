#!/usr/bin/env pwsh
#Requires -Version 7.4
param()
$ErrorActionPreference = 'Stop'
$evals = Split-Path $PSScriptRoot
Import-Module (Join-Path $evals 'lib/Results.psm1') -Force
Import-Module (Join-Path $evals 'dashboard/Dashboard.psm1') -Force
$fixtures = Join-Path $PSScriptRoot 'fixtures'
$failures = [System.Collections.Generic.List[string]]::new()

function Limit-Text($Value) { $text = "$Value"; if ($text.Length -gt 160) { $text.Substring(0, 160) + '...' } else { $text } }
function Assert-Equal($Expected, $Actual, [string]$Name) {
    if ($Expected -ne $Actual) { $failures.Add("${Name}: expected '$(Limit-Text $Expected)', got '$(Limit-Text $Actual)'") }
}
function Assert-True([bool]$Condition, [string]$Name, [string]$Detail = '') {
    if (-not $Condition) { $failures.Add("${Name} $Detail".Trim()) }
}
function Get-Error([scriptblock]$Action) {
    try { & $Action | Out-Null; $null } catch { "$_" }
}
function Test-Case([string]$Name, [scriptblock]$Body) {
    try { & $Body } catch { $failures.Add("${Name}: threw $($_.Exception.Message)") }
}
function Use-Culture([string]$Name, [scriptblock]$Body) {
    $saved = [cultureinfo]::CurrentCulture
    try { [cultureinfo]::CurrentCulture = [cultureinfo]::GetCultureInfo($Name); & $Body } finally { [cultureinfo]::CurrentCulture = $saved }
}

$localPath = 'C:\Users\someone\AppData\Local\Temp\skill-evals\20261101-100000\r001\ws'
function New-RunJson([string]$Mode, [int]$Number, [hashtable]$Override = @{}) {
    $json = [ordered]@{
        id = 1; target = 'claude:sonnet'; agent = 'claude'; model = 'sonnet'; task = 'invoice'; mode = $Mode; run = $Number; invocation = 'explicit'
        workspace = $localPath; isolated = $false; command = "claude -p --dir $localPath"; skill = 'fsharp-failure-paths'
        startedAt = '2026-11-01T10:00:00Z'; skillCommit = 'abc1234abc1234abc1234abc1234abc1234abc1234'; skillDirty = $false; resolvedModel = 'claude-sonnet-5-5'
        exitCode = 0; timedOut = $false; seconds = 12.5; inputTokens = 100; outputTokens = 20; costUsd = 0.1; turns = 5; failedBuilds = 1
        skillUsed = ($Mode -eq 'with'); globalSkillUsed = $false
        checks = @(
            [ordered]@{ text = 'Builds'; passed = $true; evidence = "built in $localPath" },
            [ordered]@{ text = 'Returns Error'; passed = $false; evidence = "FAIL in $localPath" },
            [ordered]@{ text = 'Native exe'; passed = $null; evidence = 'skipped' })
        passed = 1; failed = 1; skipped = 1
    }
    foreach ($key in $Override.Keys) { $json[$key] = $Override[$key] }
    $json
}
function New-ResultDir([string]$Root, [string]$RunId, [object[]]$Runs) {
    $dir = Join-Path $Root $RunId
    $n = 0
    foreach ($run in $Runs) {
        $n++
        $runDir = Join-Path $dir ('r{0:d3}' -f $n)
        New-Item -ItemType Directory -Force -Path $runDir | Out-Null
        $run | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $runDir 'run.json') -Encoding utf8
    }
    $dir
}

function New-ProjectedRun([string]$Mode, [int]$Passed, [int]$Failed, [bool]$SkillUsed = $true, $Turns = 10, $FailedBuilds = 2) {
    $checks = @(1..($Passed + $Failed) | ForEach-Object { [pscustomobject]@{ text = "check $_"; passed = ($_ -le $Passed) } })
    [pscustomobject]@{
        target = 'claude:sonnet'; agent = 'claude'; model = 'sonnet'; resolvedModel = 'claude-sonnet-5-5'; task = 'invoice'; mode = $Mode; run = 1; invocation = 'explicit'
        isolated = $false; startedAt = '2026-11-01T10:00:00Z'; skillCommit = 'abc1234'; skillDirty = $false; exitCode = 0; timedOut = $false; seconds = 10
        inputTokens = 100; outputTokens = 20; costUsd = 0.1; turns = $Turns; failedBuilds = $FailedBuilds; skillUsed = $SkillUsed; globalSkillUsed = $false; checks = $checks
    }
}
function Get-Direction([object[]]$Runs) { (New-Comparison -RunId 'r' -Runs $Runs).verdict }
function Copy-Run([int]$Count, [scriptblock]$Make) { 1..$Count | ForEach-Object { & $Make } }

$root = Join-Path ([IO.Path]::GetTempPath()) "dashboard-tests-$PID"
New-Item -ItemType Directory -Force -Path $root | Out-Null
try {
    $export = Join-Path $evals 'export-results.ps1'
    $results = Join-Path $root 'results'
    $dir = New-ResultDir (Join-Path $root 'in') '20261101-100000' @((New-RunJson 'without' 1), (New-RunJson 'with' 1))

    $out = & $export -ResultDir $dir -ResultsRoot $results
    Assert-Equal (Join-Path $results 'fsharp-failure-paths/20261101-100000.json') $out 'export path'
    $text = [IO.File]::ReadAllText($out)
    Assert-True ($text -notmatch 'someone|workspace|command|evidence|AppData') 'export drops workspace, command, and evidence'
    $set = Read-ResultSet $out
    Assert-Equal 'fsharp-failure-paths' $set.skill 'export skill'
    Assert-Equal '20261101-100000' $set.runId 'export run id'
    Assert-Equal 2 $set.runs.Count 'export run count'
    Assert-Equal '2026-11-01T10:00:00Z' $set.runs[0].startedAt 'export start time as ISO 8601 UTC'
    Assert-Equal 'claude-sonnet-5-5' $set.runs[0].resolvedModel 'export resolved model'
    Assert-Equal 'with,without' (($set.runs | ForEach-Object mode) -join ',') 'export orders runs by mode'
    Assert-Equal 'Builds,Returns Error,Native exe' (($set.runs[0].checks | ForEach-Object text) -join ',') 'export check texts'
    Assert-Equal 'text,passed' (($set.runs[0].checks[0].PSObject.Properties.Name) -join ',') 'export checks keep only text and passed'
    Assert-True ($null -eq $set.runs[0].checks[2].passed) 'export keeps a skipped check as null'

    $again = & $export -ResultDir $dir -ResultsRoot $results
    Assert-Equal $text ([IO.File]::ReadAllText($again)) 'export is idempotent'

    $changed = New-ResultDir (Join-Path $root 'in2') '20261101-100000' @((New-RunJson 'with' 1 @{ turns = 9 }), (New-RunJson 'without' 1))
    $message = Get-Error { & $export -ResultDir $changed -ResultsRoot $results }
    Assert-True ($message -like '*different content*-Force*') 'export refuses to replace a different file without -Force' "$message"
    $null = & $export -ResultDir $changed -ResultsRoot $results -Force
    Assert-Equal 9 (Read-ResultSet $out).runs[0].turns 'export -Force replaces the file'

    $noModel = New-ResultDir (Join-Path $root 'in3') '20261102-100000' @((New-RunJson 'with' 1 @{ resolvedModel = $null }))
    $message = Get-Error { & $export -ResultDir $noModel -ResultsRoot $results }
    Assert-True ($message -like '*no resolvedModel*-ResolvedModel*claude:sonnet*') 'export fails without a resolved model' "$message"
    Assert-True (-not (Test-Path (Join-Path $results 'fsharp-failure-paths/20261102-100000.json'))) 'a failed export writes no file'
    $null = & $export -ResultDir $noModel -ResultsRoot $results -ResolvedModel @{ 'claude:sonnet' = 'claude-sonnet-5-5' }
    $filled = Read-ResultSet (Join-Path $results 'fsharp-failure-paths/20261102-100000.json')
    Assert-Equal 'claude-sonnet-5-5' $filled.runs[0].resolvedModel 'export uses -ResolvedModel for a run without one'

    $oldRun = New-RunJson 'with' 1
    foreach ($key in 'skill', 'startedAt', 'skillCommit', 'skillDirty') { $oldRun.Remove($key) }
    $old = New-ResultDir (Join-Path $root 'in4') '20261103-100000' @($oldRun)
    $null = & $export -ResultDir $old -ResultsRoot $results
    $oldSet = Read-ResultSet (Join-Path $results 'fsharp-failure-paths/20261103-100000.json')
    Assert-Equal 'fsharp-failure-paths' $oldSet.skill 'export finds the skill from evals.json when run.json has none'
    Assert-True ($null -eq $oldSet.runs[0].startedAt -and $null -eq $oldSet.runs[0].skillCommit) 'export keeps missing start time and commit as null'

    $stats = Get-ModeStats -Mode with -Runs @(
        (New-ProjectedRun with 2 0), (New-ProjectedRun with 1 1), (New-ProjectedRun with 0 2 $false), (New-ProjectedRun without 1 1))
    Assert-Equal 3 $stats.runs 'with-skill runs'
    Assert-Equal 2 $stats.counted 'a with-skill run without skill use is not counted'
    Assert-Equal 1 $stats.notLoaded 'a with-skill run without skill use is listed as not loaded'
    Assert-Equal 0.75 $stats.passRate 'pass rate averages counted runs only'
    Assert-Equal 1 $stats.allPassRuns 'all-checks-passed runs among counted runs'
    Assert-Equal 120 $stats.meanTokens 'mean tokens add input and output'
    $empty = Get-ModeStats -Mode with -Runs @((New-ProjectedRun with 2 0 $false))
    Assert-True ($empty.counted -eq 0 -and $null -eq $empty.passRate -and $null -eq $empty.meanTurns) 'a mode without counted runs has null stats'

    $better = Get-Direction @((Copy-Run 3 { New-ProjectedRun with 4 1 }) + (Copy-Run 3 { New-ProjectedRun without 2 3 }))
    Assert-Equal 'better' $better.direction 'verdict better'
    Assert-Equal 'Pass rate rose from 40% to 80% (+40 points).' $better.reason 'verdict better reason'
    Assert-Equal $false $better.underpowered 'three counted runs in each mode are not underpowered'
    Assert-Equal 'better' (Get-Direction @((Copy-Run 3 { New-ProjectedRun with 9 1 }) + (Copy-Run 3 { New-ProjectedRun without 8 2 }))).direction 'a delta of exactly 10 points is better'
    $worse = Get-Direction @((Copy-Run 3 { New-ProjectedRun with 1 4 }) + (Copy-Run 3 { New-ProjectedRun without 4 1 }))
    Assert-Equal 'worse' $worse.direction 'verdict worse'
    Assert-Equal 'Pass rate fell from 80% to 20% (-60 points).' $worse.reason 'verdict worse reason'
    $fewerBuilds = Get-Direction @((Copy-Run 3 { New-ProjectedRun with 2 2 $true 10 1 }) + (Copy-Run 3 { New-ProjectedRun without 2 2 $true 10 2 }))
    Assert-Equal 'less-effort' $fewerBuilds.direction 'verdict less-effort from failed builds'
    Assert-Equal 'Pass rate is about the same (50% to 50%), and failed builds fell from 2.0 to 1.0.' $fewerBuilds.reason 'verdict less-effort reason'
    Assert-Equal 'less-effort' (Get-Direction @((Copy-Run 3 { New-ProjectedRun with 2 2 $true 9 0 }) + (Copy-Run 3 { New-ProjectedRun without 2 2 $true 12 0 }))).direction 'verdict less-effort from turns'
    Assert-Equal 'no-change' (Get-Direction @((Copy-Run 3 { New-ProjectedRun with 2 2 $true 10 1.5 }) + (Copy-Run 3 { New-ProjectedRun without 2 2 $true 12 2 }))).direction 'verdict no-change when effort drops below the thresholds'
    Assert-Equal 'better' (Get-Direction @((Copy-Run 3 { New-ProjectedRun with 4 1 $true 10 0 }) + (Copy-Run 3 { New-ProjectedRun without 2 3 $true 20 5 }))).direction 'a pass rate gain wins over an effort gain'

    $noLoad = Get-Direction @((Copy-Run 3 { New-ProjectedRun with 4 1 $false }) + (Copy-Run 3 { New-ProjectedRun without 2 3 }))
    Assert-Equal 'not-comparable' $noLoad.direction 'verdict not-comparable when the skill never loaded'
    Assert-Equal 'No with-skill run counts: the agent loaded the skill in 0 of 3 runs.' $noLoad.reason 'not-comparable reason'
    Assert-Equal 'not-comparable' (Get-Direction @((Copy-Run 3 { New-ProjectedRun with 4 1 }))).direction 'verdict not-comparable without baseline runs'
    Assert-Equal 'No run without the skill is available to compare.' (Get-Direction @((Copy-Run 3 { New-ProjectedRun with 4 1 }))).reason 'not-comparable reason without baseline runs'
    Assert-Equal 'No run with the skill is available to compare.' (Get-Direction @((Copy-Run 3 { New-ProjectedRun without 4 1 }))).reason 'not-comparable reason without with-skill runs'
    $ungradedRuns = Copy-Run 3 { $run = New-ProjectedRun with 1 0; $run.checks = @(); $run }
    Assert-Equal 'No counted run has a graded check.' (Get-Direction @($ungradedRuns + (Copy-Run 3 { New-ProjectedRun without 2 3 }))).reason 'not-comparable reason without a graded check'

    $small = Get-Direction @((Copy-Run 2 { New-ProjectedRun with 4 1 }) + (Copy-Run 3 { New-ProjectedRun without 2 3 }))
    Assert-Equal $true $small.underpowered 'two counted runs are underpowered'
    Assert-Equal 'better' $small.direction 'an underpowered comparison still has a direction'

    $matrix = (New-Comparison -RunId 'r' -Runs @((New-ProjectedRun with 2 0), (New-ProjectedRun with 1 1), (New-ProjectedRun with 0 2 $false), (New-ProjectedRun without 1 1))).checks
    Assert-Equal '2/2' "$($matrix[0].with.passed)/$($matrix[0].with.total)" 'check matrix counts counted with-skill runs'
    Assert-Equal '1/2' "$($matrix[1].with.passed)/$($matrix[1].with.total)" 'check matrix second check with skill'
    Assert-Equal '1/1' "$($matrix[0].without.passed)/$($matrix[0].without.total)" 'check matrix without skill'

    Test-Case 'a run without the skill counts even when skillUsed is false' {
        $stats = Get-ModeStats -Mode without -Runs @((New-ProjectedRun without 2 0 $false), (New-ProjectedRun without 1 1 $true))
        Assert-Equal 2 $stats.counted 'a without-skill run with skillUsed false counts'
        Assert-Equal 0 $stats.notLoaded 'a without-skill run is never listed as not loaded'
        Assert-Equal 0.75 $stats.passRate 'the pass rate includes a without-skill run with skillUsed false'
        $matrix = (New-Comparison -RunId 'r' -Runs @((New-ProjectedRun with 2 0), (New-ProjectedRun without 2 0 $false))).checks
        Assert-Equal '1/1' "$($matrix[0].without.passed)/$($matrix[0].without.total)" 'the check matrix counts a without-skill run with skillUsed false'
        $serial = $null
        foreach ($set in Get-ChildItem (Join-Path $fixtures 'results/fsharp-serialization') -Filter '*.json') {
            $serial = (New-Comparison -RunId 'r' -Runs (Read-ResultSet $set.FullName).runs)
        }
        Assert-Equal 4 $serial.without.counted 'the serialization fixture counts its without-skill run with skillUsed false'
        Assert-Equal 4 $serial.without.runs 'the serialization fixture has four without-skill runs'
    }

    Test-Case 'verdict thresholds at the boundary' {
        $loss = Get-Direction @((Copy-Run 3 { New-ProjectedRun with 8 2 }) + (Copy-Run 3 { New-ProjectedRun without 9 1 }))
        Assert-Equal 'worse' $loss.direction 'a loss of exactly 10 points is worse'
        $nearLoss = Get-Direction @((Copy-Run 3 { New-ProjectedRun with 85 15 }) + (Copy-Run 3 { New-ProjectedRun without 9 1 }))
        Assert-Equal 'no-change' $nearLoss.direction 'a loss of 5 points is no change'
        Assert-Equal 'no-change' (Get-Direction @((Copy-Run 3 { New-ProjectedRun with 2 2 $true 8 1 }) + (Copy-Run 3 { New-ProjectedRun without 2 2 $true 10 1 }))).direction 'a turns drop of 20 percent is no change'
        Assert-Equal 'less-effort' (Get-Direction @((Copy-Run 3 { New-ProjectedRun with 2 2 $true 6 1 }) + (Copy-Run 3 { New-ProjectedRun without 2 2 $true 8 1 }))).direction 'a turns drop of exactly 25 percent is less effort'
        Assert-Equal 'no-change' (Get-Direction @((Copy-Run 3 { New-ProjectedRun with 2 2 $true 10 1.5 }) + (Copy-Run 3 { New-ProjectedRun without 2 2 $true 10 2.4 }))).direction 'a failed builds drop below 1 is no change'
        Assert-Equal 'less-effort' (Get-Direction @((Copy-Run 3 { New-ProjectedRun with 2 2 $true 10 1.5 }) + (Copy-Run 3 { New-ProjectedRun without 2 2 $true 10 2.5 }))).direction 'a failed builds drop of exactly 1 is less effort'
    }

    Test-Case 'comparison statistics keep their edge cases' {
        $ungraded = New-ProjectedRun with 1 0
        $ungraded.checks = @()
        $graded = Get-ModeStats -Mode with -Runs @((New-ProjectedRun with 2 0), $ungraded)
        Assert-Equal 2 $graded.counted 'a run without checks is counted'
        Assert-Equal 1 $graded.allPassRuns 'a run without graded checks is not an all-pass run'
        Assert-Equal 1 $graded.passRate 'a run without graded checks does not change the pass rate'

        $skipped = New-ProjectedRun with 1 1
        $skipped.checks = @($skipped.checks) + [pscustomobject]@{ text = 'Native exe'; passed = $null }
        $comparison = New-Comparison -RunId 'r' -Runs @($skipped, (New-ProjectedRun without 1 1))
        $native = $comparison.checks | Where-Object { $_.text -eq 'Native exe' }
        Assert-Equal 0 $native.with.total 'a skipped check is not in the matrix total'
        Assert-Equal 0.5 $comparison.with.passRate 'a skipped check does not change the pass rate'

        $late = New-ProjectedRun with 1 1; $late.startedAt = '2026-11-01T10:05:00Z'
        $early = New-ProjectedRun with 1 1; $early.startedAt = '2026-11-01T10:00:00Z'
        $latest = New-ProjectedRun with 1 1; $latest.startedAt = '2026-11-01T10:10:00Z'
        Assert-Equal '2026-11-01T10:00:00Z' (New-Comparison -RunId 'r' -Runs @($late, $early, $latest)).startedAt 'the comparison starts at the earliest run'

        $dirty = New-ProjectedRun with 1 1; $dirty.skillDirty = $true
        Assert-Equal $true (New-Comparison -RunId 'r' -Runs @((New-ProjectedRun with 1 1), $dirty, (New-ProjectedRun with 1 1))).skillDirty 'one dirty run marks the comparison dirty'
        Assert-Equal $false (New-Comparison -RunId 'r' -Runs @((New-ProjectedRun with 1 1), (New-ProjectedRun with 1 1))).skillDirty 'clean runs give a clean comparison'
    }

    Test-Case 'a comparison date comes from the start time or the run id' {
        $started = New-ProjectedRun with 1 1; $started.startedAt = '2026-11-02T23:30:00Z'
        Assert-Equal '2026-11-02' (New-Comparison -RunId '20261101-100000' -Runs @($started)).date 'the date follows the start time'
        $legacy = New-ProjectedRun with 1 1; $legacy.startedAt = $null
        $comparison = New-Comparison -RunId '20261101-100000' -Runs @($legacy)
        Assert-True ($null -eq $comparison.startedAt) 'a legacy comparison has no start time'
        Assert-Equal '2026-11-01' $comparison.date 'the date of a run without a start time follows the run id'
    }

    Test-Case 'targets split by model' {
        $catalog = @([pscustomobject]@{ skill = 'demo'; description = ''; tasks = @('invoice') })
        function New-ModelRuns([string]$Model, [string]$Mode, [int]$Passed, [int]$Failed) {
            Copy-Run 3 { $run = New-ProjectedRun $Mode $Passed $Failed; $run.resolvedModel = $Model; $run }
        }
        $mixed = [pscustomobject]@{ skill = 'demo'; runId = '20261101-100000'; runs = @((New-ModelRuns 'model-a' with 4 1) + (New-ModelRuns 'model-b' without 2 3)) }
        $data = New-DashboardData -Catalog $catalog -ResultSets @($mixed) -GeneratedAt '2026-11-03T00:00:00Z'
        $targets = @($data.skills[0].tasks[0].targets)
        Assert-Equal 2 $targets.Count 'runs of one target with two models make two rows'
        Assert-Equal 'model-a,model-b' (($targets | ForEach-Object resolvedModel) -join ',') 'each row names its own model'
        Assert-True (@($targets | Where-Object { $_.latest.verdict.direction -ne 'not-comparable' }).Count -eq 0) 'a model change between modes gives no skill verdict' (($targets | ForEach-Object { $_.latest.verdict.direction }) -join ',')

        $both = [pscustomobject]@{ skill = 'demo'; runId = '20261101-100000'; runs = @((New-ModelRuns 'model-a' with 4 1) + (New-ModelRuns 'model-a' without 2 3) + (New-ModelRuns 'model-b' with 1 4) + (New-ModelRuns 'model-b' without 4 1)) }
        $later = [pscustomobject]@{ skill = 'demo'; runId = '20261102-100000'; runs = @((New-ModelRuns 'model-a' with 4 1) + (New-ModelRuns 'model-a' without 2 3)) }
        $data = New-DashboardData -Catalog $catalog -ResultSets @($both, $later) -GeneratedAt '2026-11-03T00:00:00Z'
        $a = $data.skills[0].tasks[0].targets | Where-Object { $_.resolvedModel -eq 'model-a' }
        $b = $data.skills[0].tasks[0].targets | Where-Object { $_.resolvedModel -eq 'model-b' }
        Assert-Equal 'better' $a.latest.verdict.direction 'the first model has its own verdict'
        Assert-Equal 'worse' $b.latest.verdict.direction 'the second model has its own verdict'
        Assert-Equal 2 $a.history.Count 'the first model has two history points'
        Assert-Equal 1 $b.history.Count 'the second model has one history point'
        Assert-Equal 'model-a' $a.latest.resolvedModel 'a comparison names one model'
        Assert-Equal $false $a.superseded 'the model of the newest result set is current'
        Assert-Equal $true $b.superseded 'a model that only an older result set used is superseded'
        $together = New-DashboardData -Catalog $catalog -ResultSets @($both) -GeneratedAt '2026-11-03T00:00:00Z'
        Assert-Equal 0 @($together.skills[0].tasks[0].targets | Where-Object { $_.superseded }).Count 'two models in the newest result set are both current'
        $reversed = New-DashboardData -Catalog $catalog -ResultSets @($later, $both) -GeneratedAt '2026-11-03T00:00:00Z'
        Assert-Equal 1 @($reversed.skills[0].tasks[0].targets | Where-Object { $_.superseded }).Count 'result set order does not change which model is superseded'
        $other = [pscustomobject]@{ skill = 'demo'; runId = '20261103-100000'; runs = @(Copy-Run 3 { $run = New-ProjectedRun with 4 1; $run.target = 'codex'; $run.resolvedModel = 'model-c'; $run }) }
        $apart = New-DashboardData -Catalog $catalog -ResultSets @($both, $other) -GeneratedAt '2026-11-03T00:00:00Z'
        Assert-Equal 0 @($apart.skills[0].tasks[0].targets | Where-Object { $_.target -eq 'codex' -and $_.superseded }).Count 'a target with one model is never superseded'
        Assert-Equal 0 @($apart.skills[0].tasks[0].targets | Where-Object { $_.target -ne 'codex' -and $_.superseded }).Count 'a newer result set of another target supersedes nothing'
    }

    $catalog = @(Get-SkillCatalog -EvalsRoot $evals -SkillsRoot (Join-Path (Split-Path $evals) 'skills'))
    $sets = @(Get-ChildItem (Join-Path $fixtures 'results') -Filter '*.json' -Recurse | ForEach-Object { Read-ResultSet $_.FullName })
    $data = New-DashboardData -Catalog $catalog -ResultSets $sets -Commit 'abc' -GeneratedAt '2026-11-03T00:00:00Z'
    $names = @($data.skills | ForEach-Object skill)
    $missing = @($catalog | Where-Object { $_.skill -notin $names } | ForEach-Object skill)
    Assert-True ($catalog.Count -gt 2 -and $missing.Count -eq 0) 'every skill with evals appears' ($missing -join ',')
    $bare = $data.skills | Where-Object { $_.skill -eq 'fsharp-idiom-review' }
    Assert-True ($bare -and $bare.tasks.Count -gt 0 -and @($bare.tasks | ForEach-Object { $_.targets } | Where-Object { $_ }).Count -eq 0) 'a skill without results lists its tasks with no targets'
    $paths = $data.skills | Where-Object { $_.skill -eq 'fsharp-failure-paths' }
    Assert-True ($paths.description -like 'Make failures*') 'skill description comes from SKILL.md frontmatter' $paths.description
    $sonnet = $paths.tasks[0].targets | Where-Object { $_.target -eq 'claude:sonnet' }
    Assert-Equal '20261102-100000' $sonnet.latest.runId 'latest is the newest result set'
    Assert-Equal '20261101-100000,20261102-100000' (($sonnet.history | ForEach-Object runId) -join ',') 'history runs oldest to newest'
    Assert-Equal 'claude-sonnet-5-5' $sonnet.resolvedModel 'target names the exact model'
    Assert-Equal 3 $sonnet.latest.with.counted 'fixture latest counted with-skill runs'
    Assert-Equal 1 $sonnet.latest.with.notLoaded 'fixture latest not-loaded run'
    $directions = @($paths.tasks[0].targets | ForEach-Object { $_.latest.verdict.direction } | Sort-Object -Unique) -join ','
    Assert-Equal 'better,less-effort,no-change,not-comparable,worse' $directions 'fixture latest result set covers every verdict direction'
    $codex = $paths.tasks[0].targets | Where-Object { $_.target -eq 'codex' }
    Assert-Equal 'gpt-6.1-sol (reasoning effort high)' $codex.resolvedModel 'codex target names model and effort'
    $haikuRows = @($paths.tasks[0].targets | Where-Object { $_.target -eq 'claude:haiku' })
    Assert-Equal 2 $haikuRows.Count 'a target whose alias moved to a new model has one row for each model'
    $haiku = $haikuRows | Where-Object { $_.resolvedModel -eq 'claude-haiku-4-5' }
    $olderHaiku = $haikuRows | Where-Object { $_.resolvedModel -eq 'claude-haiku-4-0' }
    Assert-True ($haiku.history.Count -eq 1 -and $haiku.latest.verdict.underpowered) 'a target in one result set has one history point'
    Assert-Equal $false $haiku.superseded 'the row with the newest result set is current'
    Assert-Equal $true $olderHaiku.superseded 'the row of an older model is superseded'
    Assert-Equal '20261101-100000' $olderHaiku.latest.runId 'the superseded row keeps its own latest result set'
    Assert-Equal 1 @($paths.tasks[0].targets | Where-Object { $_.superseded }).Count 'only the older haiku row is superseded in the fixtures'
    Assert-True (($data | ConvertTo-Json -Depth 12) -notmatch 'someone|workspace') 'dashboard data holds no local paths'

    $site = Join-Path $root 'site'
    $build = Join-Path $evals 'dashboard/build-dashboard.ps1'
    & $build -OutDir $site -ResultsRoot (Join-Path $fixtures 'results') | Out-Null
    foreach ($file in 'index.html', 'dashboard.js', 'dashboard.css', 'data.js') { Assert-True (Test-Path (Join-Path $site $file)) "build writes $file" }
    $dataJs = [IO.File]::ReadAllText((Join-Path $site 'data.js'))
    Assert-True ($dataJs.StartsWith('window.EVAL_DASHBOARD = ') -and $dataJs.TrimEnd().EndsWith(';')) 'data.js assigns window.EVAL_DASHBOARD'
    $parsed = ($dataJs -replace '^window\.EVAL_DASHBOARD = ', '').TrimEnd().TrimEnd(';') | ConvertFrom-Json
    Assert-Equal 1 $parsed.schemaVersion 'data.js holds the dashboard data'
    $emptySite = Join-Path $root 'empty-site'
    & $build -OutDir $emptySite -ResultsRoot (Join-Path $root 'no-results') | Out-Null
    $emptyData = ([IO.File]::ReadAllText((Join-Path $emptySite 'data.js')) -replace '^window\.EVAL_DASHBOARD = ', '').TrimEnd().TrimEnd(';') | ConvertFrom-Json
    Assert-True ($emptyData.skills.Count -gt 2 -and ($emptyData.skills.tasks | ForEach-Object { $_.targets.Count } | Measure-Object -Sum).Sum -eq 0) 'a build without result sets still lists every skill'

    $cultureDir = New-ResultDir (Join-Path $root 'in-culture') '20261105-100000' @((New-RunJson 'with' 1), (New-RunJson 'without' 1))
    $baseline = [IO.File]::ReadAllText((& $export -ResultDir $cultureDir -ResultsRoot (Join-Path $root 'culture-baseline')))
    $runner = Join-Path $evals 'run-evals.ps1'
    foreach ($culture in 'fi-FI', 'th-TH') {
        Use-Culture $culture {
            Test-Case "dates under $culture" {
                $instant = [datetime]::new(2026, 11, 1, 10, 0, 0, [DateTimeKind]::Utc)
                Assert-Equal '2026-11-01T10:00:00Z' (ConvertTo-IsoUtc $instant) "$culture ConvertTo-IsoUtc of a DateTime"
                Assert-Equal '2026-11-01T10:00:00Z' (ConvertTo-IsoUtc '2026-11-01T10:00:00Z') "$culture ConvertTo-IsoUtc of text"
                Assert-Equal '2026-11-01T10:00:00Z' (ConvertTo-IsoUtc (ConvertTo-IsoUtc $instant)) "$culture ConvertTo-IsoUtc round trip"
                Assert-Equal '2026-11-01T10:00:00Z' (Format-IsoUtc $instant) "$culture Format-IsoUtc"
            }
            Test-Case "export under $culture" {
                $exported = & $export -ResultDir $cultureDir -ResultsRoot (Join-Path $root "culture-$culture") -Force
                $exportedText = [IO.File]::ReadAllText($exported)
                $startedLine = ($exportedText -split "`n" | Where-Object { $_ -match 'startedAt' } | Select-Object -First 1)
                Assert-True ($exportedText -ceq $baseline) "$culture export writes the same bytes" "$startedLine".Trim()
                Assert-Equal '2026-11-01T10:00:00Z' (Read-ResultSet $exported).runs[0].startedAt "$culture result set start time"
            }
            Test-Case "build under $culture" {
                $site = Join-Path $root "culture-site-$culture"
                & $build -OutDir $site -ResultsRoot (Join-Path $fixtures 'results') | Out-Null
                $null = [IO.File]::ReadAllText((Join-Path $site 'data.js')) -match '"generatedAt":\s*"(?<value>[^"]*)"'
                $generated = "$($Matches.value)"
                Assert-True ($generated -match '^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$') "$culture generatedAt is ISO 8601" $generated
                Assert-Equal ([DateTime]::UtcNow.Year) ([int]$generated.Substring(0, 4)) "$culture generatedAt year"
            }
            Test-Case "run id under $culture" {
                $outputRoot = Join-Path $root "runs-$culture"
                & $runner -Skill fsharp-failure-paths -Target claude -Task invoice -DryRun -OutputRoot $outputRoot *> $null
                $names = @(Get-ChildItem $outputRoot -Directory | ForEach-Object Name)
                Assert-True ($names.Count -eq 1 -and $names[0] -match '^\d{8}-\d{6}$') "$culture run id has the form yyyyMMdd-HHmmss" ($names -join ',')
                Assert-Equal ([DateTime]::Now.Year) ([int]$names[0].Substring(0, 4)) "$culture run id year"
            }
        }
    }

    function New-CheckRun([string[]]$Texts, [hashtable]$Override = @{}) {
        $run = New-RunJson 'with' 1 @{ checks = @($Texts | ForEach-Object { [ordered]@{ text = $_; passed = $true; evidence = '' } }) }
        foreach ($key in $Override.Keys) { $run[$key] = $Override[$key] }
        [pscustomobject]$run
    }

    Test-Case 'text that looks like a local path is refused' {
        Import-Module (Join-Path $evals 'lib/Grading.psm1') -Force
        $userName = [Environment]::UserName
        $texts = @(
            'Builds in "~/Client Alice"'
            'Builds in "D:\work\Client Alice\ws"'
            'D:\work\x y failed'
            'wrote /opt/private/project/result.json'
            'wrote /workspaces/repo/x.fs'
            'uses C:/x'
            '\\server\share\x'
            'opened (/tmp/a)'
            'wrote //server/private/ClientAlice/result.json'
            'wrote ///opt/private/ClientAlice/result.json'
        )
        if ($userName.Length -ge 3) { $texts += "greets $userName" }
        $checks = @(ConvertFrom-ProbeOutput -Lines @($texts | ForEach-Object { "PASS $_" }))
        Assert-Equal $texts.Count $checks.Count 'every probe line gives a check'
        for ($i = 0; $i -lt $checks.Count; $i++) {
            $message = "$(Get-Error { ConvertTo-ProjectedRun -Run (New-CheckRun @('Returns Error', $checks[$i].text)) })"
            foreach ($part in 'run 1 (claude:sonnet)', 'checks[1].text', 'must not hold local paths or the user name') {
                Assert-True ($message.Contains($part)) "the projection refuses '$($texts[$i])' with '$part'" "message: $message"
            }
            Assert-True (-not $message.Contains($texts[$i]) -and $message -notmatch 'Alice') "the refusal of '$($texts[$i])' does not repeat the text" "message: $message"

            $dir = New-ResultDir (Join-Path $root "in-refused-$i") ('202612{0:d2}-100000' -f $i) @((New-RunJson 'with' 1 @{ checks = @([ordered]@{ text = $checks[$i].text; passed = $true; evidence = '' }) }))
            $resultsRoot = Join-Path $root "results-refused-$i"
            $message = "$(Get-Error { & $export -ResultDir $dir -ResultsRoot $resultsRoot })"
            Assert-True ($message.Contains('must not hold local paths or the user name')) "the export refuses '$($texts[$i])'" "message: $message"
            Assert-True (-not (Test-Path $resultsRoot)) "a refused export of '$($texts[$i])' writes no file"
        }

        foreach ($field in 'target', 'agent', 'model', 'resolvedModel', 'task', 'invocation', 'skillCommit') {
            foreach ($value in '/opt/private/x', 'C:\Users\x\m', '~/m', '\\server\share\task') {
                $message = "$(Get-Error { ConvertTo-ProjectedRun -Run (New-CheckRun @('Builds') @{ $field = $value }) })"
                foreach ($part in "'$field'", 'must not hold local paths or the user name') {
                    Assert-True ($message.Contains($part)) "a path in $field ($value) is refused with '$part'" "message: $message"
                }
                Assert-True (-not $message.Contains($value)) "the refusal for $field does not repeat $value" "message: $message"
            }
        }
        $privateTarget = 'codex:C:/ClientAlice/model'
        $message = "$(Get-Error { ConvertTo-ProjectedRun -Run (New-CheckRun @('Builds') @{ target = $privateTarget; resolvedModel = '' }) })"
        Assert-True ($message.Contains("'<target>' = '<exact model>'")) 'the unknown-model error names a private target as <target>' "message: $message"
        Assert-True (-not $message.Contains('ClientAlice')) 'the unknown-model error does not repeat a private target' "message: $message"

        $agentRun = New-CheckRun @('Builds') @{ target = 'codex'; agent = 'claude' }
        $message = "$(Get-Error { ConvertTo-ProjectedRun -Run $agentRun -UserName 'claude' })"
        Assert-True ($message.Contains("'agent'")) 'a user name that is also an agent name is refused by default' "message: $message"
        Assert-Equal 'claude' (ConvertTo-ProjectedRun -Run $agentRun -UserName '').agent 'an empty -UserName turns off the user-name check'
        $dir = New-ResultDir (Join-Path $root 'in-username-off') '20261230-100000' @((New-RunJson 'with' 1 @{ agent = 'claude' }))
        $out = & $export -ResultDir $dir -ResultsRoot (Join-Path $root 'results-username-off') -UserName ''
        Assert-True (Test-Path $out) 'export -UserName passes the name to the projection'

        $legacy = ConvertTo-ProjectedRun -Run (New-CheckRun @('Builds') @{ skillCommit = $null })
        Assert-True ($null -eq $legacy.skillCommit) 'a null skillCommit stays null'
        Assert-Equal 0 @((ConvertTo-ProjectedRun -Run (New-CheckRun @())).checks).Count 'a run without checks projects no check'
    }

    Test-Case 'text without path syntax is exported unchanged' {
        Import-Module (Join-Path $evals 'lib/Grading.psm1') -Force
        $texts = @(
            'Returns Error with the cause', 'Opens https://example.com/a/b', 'Reads a/b', 'Accepts and/or', 'Parses 12:30/24', 'Returns Error<string>'
            'Runs on opencode:github-copilot/gpt-5.5', 'Runs on opencode/deepseek-v4.1-flash-free', 'Uses ratio 1/2'
        )
        $checks = @(ConvertFrom-ProbeOutput -Lines @($texts | ForEach-Object { "PASS $_" }))
        $projected = ConvertTo-ProjectedRun -Run (New-CheckRun @($checks | ForEach-Object text))
        Assert-Equal ($texts -join '|') (($projected.checks | ForEach-Object text) -join '|') 'check text is unchanged'
        $labels = ConvertTo-ProjectedRun -Run (New-CheckRun @('Builds') @{ target = 'opencode:github-copilot/gpt-5.5'; resolvedModel = 'gpt-6.1-sol (reasoning effort high)'; model = 'opencode/deepseek-v4.1-flash-free' })
        Assert-Equal 'opencode:github-copilot/gpt-5.5|gpt-6.1-sol (reasoning effort high)|opencode/deepseek-v4.1-flash-free' "$($labels.target)|$($labels.resolvedModel)|$($labels.model)" 'target labels are unchanged'
    }

    Test-Case 'fixture result sets are accepted unchanged' {
        $files = @(Get-ChildItem (Join-Path $fixtures 'results') -Filter '*.json' -Recurse)
        Assert-True ($files.Count -ge 3) 'the fixture result sets exist' "found $($files.Count)"
        $strings = 0
        foreach ($file in $files) {
            foreach ($run in (Read-ResultSet $file.FullName).runs) {
                $values = @('target', 'agent', 'model', 'resolvedModel', 'task', 'invocation', 'skillCommit' | ForEach-Object { $run.$_ }) + @($run.checks | ForEach-Object { $_.text })
                foreach ($value in $values | Where-Object { $_ -is [string] }) {
                    $strings++
                    Assert-True (-not (Test-LocalPath $value -UserName '')) "$($file.Name) text has no path syntax: $value"
                }
                $projected = ConvertTo-ProjectedRun -Run $run
                Assert-Equal (@($run.checks | ForEach-Object { $_.text }) -join '|') (@($projected.checks | ForEach-Object text) -join '|') "$($file.Name) check text is unchanged"
            }
        }
        Assert-True ($strings -gt 100) 'the fixture check covers many strings' "covered $strings"
    }

    Test-Case 'Test-LocalPath rule parts' {
        $found = [ordered]@{
            'a backslash' = 'a\b'
            'a home-relative path' = 'x ~/y'
            'a drive path with a slash' = 'in d:/x'
            'a drive path after a bracket' = 'in (d:/x)'
            'a drive path at the start' = 'D:/x'
            'a word that starts with a slash at the start' = '/x'
            'a word that starts with a slash after a space' = 'at /x'
            'a word that starts with a slash after a tab' = "at`t/x"
            'a word that starts with a slash after a double quote' = 'a "/x'
            'a word that starts with a slash after a single quote' = "a '/x"
            'a word that starts with a slash after a backtick' = 'a `/x'
            'a word that starts with a slash after a parenthesis' = 'a (/x'
            'a word that starts with a slash after a bracket' = 'a [/x'
            'a word that starts with a slash after an equals sign' = 'a =/x'
            'a word that starts with a slash after a comma' = 'a,/x'
        }
        foreach ($name in $found.Keys) { Assert-True (Test-LocalPath $found[$name] -UserName '') "Test-LocalPath finds $name in: $($found[$name])" }
        foreach ($text in 'Returns Error', 'a/b', 'and/or', 'ratio 1/2', 'see https://example.com/a/b', 'Parses 12:30/24', 'Ratio 3:/4', 'in ad:/x', 'in 3d:/x', 'x//y', 'a / b', 'a /', 'Returns Error<string>', 'opencode:github-copilot/gpt-5.5', 'opencode/deepseek-v4.1-flash-free', '', $null) {
            Assert-True (-not (Test-LocalPath $text -UserName '')) "Test-LocalPath finds no path in: $text"
        }
        Assert-True (Test-LocalPath 'greets jimmy' -UserName 'jimmy') 'Test-LocalPath finds the user name'
        Assert-True (Test-LocalPath 'Greets (JIMMY).' -UserName 'jimmy') 'Test-LocalPath finds the user name without case and next to punctuation'
        Assert-True (-not (Test-LocalPath 'greets jimmys' -UserName 'jimmy')) 'a longer word that starts with the user name is kept'
        Assert-True (-not (Test-LocalPath 'greets xjimmy' -UserName 'jimmy')) 'a longer word that ends with the user name is kept'
        Assert-True (-not (Test-LocalPath 'al wrote' -UserName 'al')) 'a user name shorter than 3 characters is ignored'
        Assert-True (-not (Test-LocalPath 'axb wrote' -UserName 'a.b')) 'the user name is not a pattern'
        Assert-True (Test-LocalPath 'greets a.b' -UserName 'a.b') 'a user name with a dot matches literally'
    }

    Test-Case 'every real grader text is accepted' {
        $texts = [System.Collections.Generic.List[string]]::new()
        foreach ($specFile in Get-ChildItem $evals -Filter 'evals.json' -Recurse -Depth 1) {
            foreach ($task in (Get-Content -Raw $specFile.FullName | ConvertFrom-Json).tasks) {
                foreach ($item in @(if ($task.PSObject.Properties['rubric']) { $task.rubric })) { $texts.Add("Rubric $($item.id): $($item.question)") }
            }
        }
        $rubric = $texts.Count
        $graders = @(Get-ChildItem -Path (Join-Path $evals '*/graders/*') -File | Where-Object { $_.Extension -in '.ps1', '.fsx' })
        foreach ($file in $graders) {
            $source = [IO.File]::ReadAllText($file.FullName)
            if ($file.Extension -eq '.ps1') {
                foreach ($m in [regex]::Matches($source, "New-Check\s+(?:'((?:[^']|'')*)'|""((?:[^""``]|``.)*)"")")) {
                    $texts.Add($(if ($m.Groups[1].Success) { $m.Groups[1].Value -replace "''", "'" } else { $m.Groups[2].Value }))
                }
                foreach ($block in [regex]::Matches($source, '(?ms)\$names\s*=\s*(?:\[ordered\])?@\{?
(.*?)^\}')) {
                    foreach ($m in [regex]::Matches($block.Groups[1].Value, "(?m)^\s+\w+\s+=\s+(?:'((?:[^']|'')*)'|""([^""]*)"")\s*$")) {
                        $texts.Add($(if ($m.Groups[1].Success) { $m.Groups[1].Value -replace "''", "'" } else { $m.Groups[2].Value }))
                    }
                }
            } else {
                foreach ($m in [regex]::Matches($source, '(?m)^\s*(?:report|check)\s+\$?"((?:[^"\\]|\\.)*)"')) { $texts.Add($m.Groups[1].Value) }
            }
        }
        Assert-True ($rubric -ge 5) 'the evals.json files hold rubric questions' "found $rubric"
        Assert-True ($texts.Count - $rubric -ge 100) 'the grader scan finds many check names' "found $($texts.Count - $rubric)"
        foreach ($text in $texts) { Assert-True (-not (Test-LocalPath $text -UserName '')) "a grader text is accepted: $text" }
    }

    Test-Case 'generated path text is refused and generated safe text is kept' {
        $pathWords = 'zephyr', 'quartz', 'mango', 'falcon', 'orchid', 'tundra', 'cobalt', 'velvet', 'harbor', 'pickle', 'walnut', 'sparrow', 'lantern', 'meadow', 'glacier', 'nimbus'
        $proseWords = 'builds', 'returns', 'failed', 'wrote', 'opened', 'reads', 'checks', 'passed', 'output', 'handles', 'the', 'cause'
        $rng = [System.Random]::new(20261110)
        function Get-Word([string[]]$List) { $List[$rng.Next($List.Count)] }
        function Get-Words([int]$Count, [string[]]$List) { @(for ($k = 0; $k -lt $Count; $k++) { Get-Word $List }) }
        function Remove-At([string[]]$Items, [int]$Index) { @(for ($k = 0; $k -lt $Items.Count; $k++) { if ($k -ne $Index) { $Items[$k] } }) }
        function Get-Refusal([string]$Text) { "$(Get-Error { ConvertTo-ProjectedRun -Run (New-CheckRun @($Text)) })" }
        function Find-Smallest($Case, [scriptblock]$Shrinks, [scriptblock]$Fails) {
            do {
                $smaller = & $Shrinks $Case | Where-Object { & $Fails $_ } | Select-Object -First 1
                if ($smaller) { $Case = $smaller }
            } while ($smaller)
            $Case
        }

        function Format-PathCase($Case) {
            $path = switch ($Case.Kind) {
                'windows' { 'C:\' + ($Case.Segments -join '\') }
                'slash' { 'd:/' + ($Case.Segments -join '/') }
                'unc' { '\\' + ($Case.Segments -join '\') }
                'home' { '~/' + ($Case.Segments -join '/') }
                'posix' { '/' + ($Case.Segments -join '/') }
            }
            (@($Case.Before) + "$($Case.Quote)$path$($Case.Quote)" + @($Case.After)) -join ' '
        }
        function Test-PathCaseFails($Case) { -not (Get-Refusal (Format-PathCase $Case)).Contains('must not hold local paths') }
        function Get-PathCaseShrinks($Case) {
            foreach ($field in 'Before', 'After') {
                for ($k = 0; $k -lt $Case[$field].Count; $k++) { $copy = $Case.Clone(); $copy[$field] = @(Remove-At $Case[$field] $k); $copy }
            }
            for ($k = 0; $Case.Segments.Count -gt 1 -and $k -lt $Case.Segments.Count; $k++) { $copy = $Case.Clone(); $copy.Segments = @(Remove-At $Case.Segments $k); $copy }
            for ($k = 0; $k -lt $Case.Segments.Count; $k++) {
                $words = @($Case.Segments[$k] -split ' ')
                for ($w = 0; $words.Count -gt 1 -and $w -lt $words.Count; $w++) {
                    $copy = $Case.Clone(); $copy.Segments = @($Case.Segments); $copy.Segments[$k] = (Remove-At $words $w) -join ' '; $copy
                }
            }
            if ($Case.Quote -ne '') { $copy = $Case.Clone(); $copy.Quote = ''; $copy }
        }
        $firstPath = $null
        for ($n = 0; $n -lt 400 -and -not $firstPath; $n++) {
            $segmentCount = 1 + $rng.Next(3)
            $segments = @(for ($k = 0; $k -lt $segmentCount; $k++) { (Get-Words (1 + $rng.Next(2)) $pathWords) -join ' ' })
            $case = @{
                Kind = Get-Word 'windows', 'slash', 'unc', 'home', 'posix'; Quote = Get-Word '', '"', "'", '`'; Segments = $segments
                Before = @(Get-Words ($rng.Next(4)) $proseWords); After = @(Get-Words ($rng.Next(3)) $proseWords)
            }
            if (Test-PathCaseFails $case) { $firstPath = $case }
        }
        if ($firstPath) {
            $small = Find-Smallest $firstPath ${function:Get-PathCaseShrinks} ${function:Test-PathCaseFails}
            $failures.Add("a path is not refused. Smallest failing input: $(Format-PathCase $small)")
        }

        function New-SafeToken {
            $word = if ($rng.Next(3) -eq 0) { -join (Get-Words (1 + $rng.Next(6)) 'a', 'b', 'c', 'x', 'y', 'z', '0', '1', '7', '9') } else { Get-Word $proseWords }
            switch ($rng.Next(11)) {
                0 { "${word}," } 1 { "${word}." } 2 { "${word}:" } 3 { "(${word})" } 4 { "<${word}>" } 5 { "'${word}'" } 6 { "`"${word}`"" } 7 { "$word-$(Get-Word $proseWords)" }
                8 { "$word/$(Get-Word $proseWords)" } 9 { "https://example.com/$word/$(Get-Word $pathWords)" } default { $word }
            }
        }
        function Test-SafeCaseFails($Tokens) { (Get-Refusal ($Tokens -join ' ')) -ne '' }
        function Get-SafeCaseShrinks($Tokens) { for ($k = 0; $Tokens.Count -gt 1 -and $k -lt $Tokens.Count; $k++) { , (Remove-At $Tokens $k) } }
        $firstSafe = $null
        for ($n = 0; $n -lt 400 -and -not $firstSafe; $n++) {
            $tokenCount = 1 + $rng.Next(8)
            $tokens = @(for ($k = 0; $k -lt $tokenCount; $k++) { New-SafeToken })
            if (Test-SafeCaseFails $tokens) { $firstSafe = $tokens }
        }
        if ($firstSafe) {
            $small = Find-Smallest $firstSafe ${function:Get-SafeCaseShrinks} ${function:Test-SafeCaseFails}
            $failures.Add("safe text is refused. Smallest failing input: $($small -join ' ')")
        }
    }

    function Read-Mutated([string]$Name, [scriptblock]$Mutate) {
        $set = Get-Content -Raw (Join-Path $fixtures 'results/fsharp-failure-paths/20261101-100000.json') | ConvertFrom-Json -AsHashtable
        & $Mutate $set
        $path = Join-Path $root "mutated-$Name.json"
        $set | ConvertTo-Json -Depth 8 | Set-Content $path -Encoding utf8
        Read-ResultSet $path
    }
    function Assert-Rejects([string]$Name, [string]$Pattern, [scriptblock]$Mutate) {
        $message = Get-Error { Read-Mutated $Name $Mutate }
        Assert-True ($message -like $Pattern) "Read-ResultSet rejects $Name" "message: $message"
    }

    Test-Case 'Read-ResultSet rejections' {
        Assert-Rejects 'a wrong schemaVersion' '*schemaVersion*' { param($s) $s.schemaVersion = 2 }
        Assert-Rejects 'a missing skill' "*no 'skill'*" { param($s) $s.Remove('skill') }
        Assert-Rejects 'a missing runId' "*no 'runId'*" { param($s) $s.Remove('runId') }
        Assert-Rejects 'a runId that is not a run id' '*yyyyMMdd-HHmmss*' { param($s) $s.runId = 'today' }
        Assert-Rejects 'a missing runs list' "*no 'runs'*" { param($s) $s.Remove('runs') }
        foreach ($key in 'target', 'agent', 'task', 'mode', 'run', 'skillUsed', 'resolvedModel', 'checks') {
            Assert-Rejects "a run without '$key'" "*a run has no '$key'*" { param($s) $s.runs[0].Remove($key) }
        }
        Assert-Rejects 'a mode that is not with or without' "*mode 'both'*" { param($s) $s.runs[0].mode = 'both' }
        Assert-Rejects 'an empty resolvedModel' '*no resolvedModel*' { param($s) $s.runs[0].resolvedModel = '' }
        Assert-Rejects 'a null resolvedModel' '*no resolvedModel*' { param($s) $s.runs[0].resolvedModel = $null }
        Assert-Rejects 'a check without text' "*a check has no 'text'*" { param($s) $s.runs[0].checks[0].Remove('text') }
        Assert-Rejects 'a check without passed' "*a check has no 'passed'*" { param($s) $s.runs[0].checks[0].Remove('passed') }
        $bad = Join-Path $root 'malformed.json'
        Set-Content $bad '{ "schemaVersion": ' -Encoding utf8
        Assert-True ($null -ne (Get-Error { Read-ResultSet $bad })) 'Read-ResultSet rejects malformed JSON'
        Assert-True ($null -ne (Get-Error { Read-ResultSet (Join-Path $root 'none.json') })) 'Read-ResultSet rejects a missing file'
    }

    Test-Case 'Read-ResultSet schema evolution' {
        $optional = @('model', 'invocation', 'isolated', 'startedAt', 'skillCommit', 'skillDirty', 'exitCode', 'timedOut', 'seconds', 'inputTokens', 'outputTokens', 'costUsd', 'turns', 'failedBuilds', 'globalSkillUsed')
        foreach ($key in $optional) {
            $read = Read-Mutated "without-$key" { param($s) foreach ($r in $s.runs) { $r.Remove($key) } }
            Assert-True ($read.runs.Count -gt 0 -and @($read.runs | Where-Object { $null -ne $_.$key }).Count -eq 0) "a result set without '$key' reads with null values"
        }
        $sets = @(New-DashboardData -Catalog @([pscustomobject]@{ skill = 'fsharp-failure-paths'; description = ''; tasks = @('invoice') }) -ResultSets @(Read-Mutated 'without-cost' { param($s) foreach ($r in $s.runs) { $r.Remove('costUsd') } }) -GeneratedAt '2026-11-03T00:00:00Z')
        Assert-True ($null -eq $sets[0].skills[0].tasks[0].targets[0].latest.with.meanCostUsd) 'a result set without costUsd gives a null mean cost'
    }

    Test-Case 'ConvertTo-ProjectedRun rejections' {
        foreach ($name in 'target', 'agent', 'task', 'mode', 'run', 'skillUsed') {
            $run = New-RunJson 'with' 1
            $run.Remove($name)
            $message = Get-Error { ConvertTo-ProjectedRun -Run ([pscustomobject]$run) }
            Assert-True ($message -like "*run.json has no '$name'*") "ConvertTo-ProjectedRun rejects a run without '$name'" "message: $message"
        }
        $message = Get-Error { ConvertTo-ProjectedRun -Run ([pscustomobject](New-RunJson 'with' 1 @{ mode = 'both' })) }
        Assert-True ($message -like "*mode 'both' is not 'with' or 'without'*") 'ConvertTo-ProjectedRun rejects a bad mode' "message: $message"
        Assert-True ($null -eq (Get-Error { ConvertTo-ProjectedRun -Run ([pscustomobject](New-RunJson 'without' 1)) })) 'ConvertTo-ProjectedRun accepts skillUsed false'
        $filled = ConvertTo-ProjectedRun -Run ([pscustomobject](New-RunJson 'with' 1 @{ resolvedModel = '' })) -ResolvedModel @{ 'claude:sonnet' = 'claude-sonnet-5-5' }
        Assert-Equal 'claude-sonnet-5-5' $filled.resolvedModel 'an empty resolvedModel takes the -ResolvedModel entry'
    }

    Test-Case 'export rejections' {
        $empty = Join-Path $root 'in-empty/20261107-100000'
        New-Item -ItemType Directory -Force -Path (Join-Path $empty 'r001') | Out-Null
        $message = Get-Error { & $export -ResultDir $empty -ResultsRoot (Join-Path $root 'results-rejected') }
        Assert-True ($message -like '*No r*/run.json found*') 'export rejects a folder without run.json files' "message: $message"
        $two = New-ResultDir (Join-Path $root 'in-two') '20261107-110000' @((New-RunJson 'with' 1), (New-RunJson 'with' 2 @{ skill = 'fsharp-serialization' }))
        $message = Get-Error { & $export -ResultDir $two -ResultsRoot (Join-Path $root 'results-rejected') }
        Assert-True ($message -like '*one skill*fsharp-failure-paths*fsharp-serialization*') 'export rejects a folder with two skills' "message: $message"
        $named = New-ResultDir (Join-Path $root 'in-named') 'my-folder' @((New-RunJson 'with' 1))
        $message = Get-Error { & $export -ResultDir $named -ResultsRoot (Join-Path $root 'results-rejected') }
        Assert-True ($message -like '*not a run id*') 'export rejects a folder name that is not a run id' "message: $message"
        Assert-True (-not (Test-Path (Join-Path $root 'results-rejected'))) 'a rejected export writes nothing'
    }

    Test-Case 'provenance is read for each run' {
        Import-Module (Join-Path $evals 'lib/Agents.psm1') -Force
        $repo = Join-Path $root 'prov-repo'
        foreach ($dir in 'skills/demo', 'evals/demo', 'evals/lib', 'evals/other') { New-Item -ItemType Directory -Force -Path (Join-Path $repo $dir) | Out-Null }
        foreach ($file in 'skills/demo/SKILL.md', 'evals/demo/evals.json', 'evals/lib/x.psm1', 'evals/other/x.txt') { Set-Content (Join-Path $repo $file) 'v1' }
        function Invoke-Git { git -C $repo -c user.name=tester -c user.email=tester@example.com -c commit.gpgsign=false @args 2>&1 | Out-Null }
        Invoke-Git init -q
        Invoke-Git add -A
        Invoke-Git commit -q -m one
        $first = "$(git -C $repo rev-parse HEAD)".Trim()
        $clean = Get-SkillProvenance -Repo $repo -Skill demo
        Assert-Equal $first $clean.SkillCommit 'provenance names the head commit'
        Assert-Equal $false $clean.SkillDirty 'a clean tree is not dirty'
        foreach ($file in 'skills/demo/SKILL.md', 'evals/demo/evals.json', 'evals/lib/x.psm1') {
            Set-Content (Join-Path $repo $file) 'v2'
            Assert-Equal $true (Get-SkillProvenance -Repo $repo -Skill demo).SkillDirty "a change to $file makes the run dirty"
            Invoke-Git checkout -- $file
        }
        Set-Content (Join-Path $repo 'evals/lib/new.psm1') 'new'
        Assert-Equal $true (Get-SkillProvenance -Repo $repo -Skill demo).SkillDirty 'a new file under evals/lib makes the run dirty'
        Remove-Item (Join-Path $repo 'evals/lib/new.psm1')
        Set-Content (Join-Path $repo 'evals/other/x.txt') 'v2'
        Assert-Equal $false (Get-SkillProvenance -Repo $repo -Skill demo).SkillDirty 'a change outside the skill, its eval, and evals/lib does not make the run dirty'
        Invoke-Git commit -q -a -m two
        Assert-True ((Get-SkillProvenance -Repo $repo -Skill demo).SkillCommit -ne $first) 'a later call sees a later commit'
    }

    Test-Case 'the runner reads provenance inside the run loop' {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $evals 'run-evals.ps1'), [ref]$null, [ref]$null)
        $named = { param($name) @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq $name }, $true)) }
        $reads = & $named 'Get-SkillProvenance'
        Assert-Equal 1 $reads.Count 'the runner calls Get-SkillProvenance once'
        if ($reads.Count -eq 1) {
            $node = $reads[0].Parent
            while ($node -and $node -isnot [System.Management.Automation.Language.ForStatementAst]) { $node = $node.Parent }
            Assert-True ($null -ne $node) 'the provenance call sits inside the loop over runs'
            $start = (& $named 'Invoke-Agent')[0]
            Assert-True ($reads[0].Extent.StartOffset -lt $start.Extent.StartOffset) 'the provenance call comes before the agent starts'
        }
    }

    Test-Case 'the runner resolves the model of Codex and opencode before the agent starts' {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $evals 'run-evals.ps1'), [ref]$null, [ref]$null)
        $named = { param($name) @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq $name }, $true)) }
        $start = (& $named 'Invoke-Agent')[0]
        $reads = & $named 'Get-ResolvedModel'
        $guard = { param($call) $node = $call.Parent; while ($node -and $node -isnot [System.Management.Automation.Language.IfStatementAst]) { $node = $node.Parent }; if ($node) { $node.Clauses[0].Item1.Extent.Text } else { "" } }
        $fromTranscript = @($reads | Where-Object { @($_.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.CommandParameterAst] -and $_.ParameterName -eq 'TranscriptPath' }).Count -gt 0 })
        $beforeLaunch = @($reads | Where-Object { $_ -notin $fromTranscript })
        Assert-Equal 1 $fromTranscript.Count 'the runner reads the Claude model from the transcript once'
        Assert-Equal 1 $beforeLaunch.Count 'the runner reads the model of the other agents once, without a transcript'
        if ($fromTranscript.Count -eq 1) { Assert-True ((& $guard $fromTranscript[0]) -match "-eq 'claude'") 'only Claude reads the model from the transcript' }
        if ($beforeLaunch.Count -eq 1) { Assert-True ((& $guard $beforeLaunch[0]) -match "-ne 'claude'") 'the model read before the launch is for the other agents' }
        if ($fromTranscript.Count -eq 1) { Assert-True ($fromTranscript[0].Extent.StartOffset -gt $start.Extent.StartOffset) 'the Claude model is read after the run' }
        if ($beforeLaunch.Count -eq 1) { Assert-True ($beforeLaunch[0].Extent.StartOffset -lt $start.Extent.StartOffset) 'the Codex and opencode model is read before the agent starts' }
    }

    Test-Case 'a failed write keeps the previous file' {
        $folder = Join-Path $root 'atomic'
        $path = Join-Path $folder 'set.json'
        Write-FileAtomic -Path $path -Content "old`n"
        Assert-Equal "old`n" ([IO.File]::ReadAllText($path)) 'Write-FileAtomic writes the file'
        Assert-True ([IO.File]::ReadAllBytes($path)[0] -ne 0xEF) 'Write-FileAtomic writes no byte order mark'
        $message = Get-Error { Write-FileAtomic -Path $path -Content ("new " + [char]0xD800) }
        Assert-True ($null -ne $message) 'Write-FileAtomic fails on content that cannot be encoded'
        Assert-Equal "old`n" ([IO.File]::ReadAllText($path)) 'a failed write keeps the previous content'
        Write-FileAtomic -Path $path -Content "new`n"
        Assert-Equal "new`n" ([IO.File]::ReadAllText($path)) 'Write-FileAtomic replaces the file'
        Assert-Equal 'set.json' (@(Get-ChildItem $folder -Force | ForEach-Object Name) -join ',') 'Write-FileAtomic leaves no temporary file'
        $exported = & $export -ResultDir $dir -ResultsRoot (Join-Path $root 'results-atomic')
        Assert-Equal '20261101-100000.json' (@(Get-ChildItem (Split-Path $exported) -Force | ForEach-Object Name) -join ',') 'the export leaves no temporary file'
    }

    Test-Case 'build writes the repository link' {
        function Get-BuiltData([string]$Name) {
            $site = Join-Path $root "repo-$Name"
            & $build -OutDir $site -ResultsRoot (Join-Path $fixtures 'results') | Out-Null
            ([IO.File]::ReadAllText((Join-Path $site 'data.js')) -replace '^window\.EVAL_DASHBOARD = ', '').TrimEnd().TrimEnd(';') | ConvertFrom-Json
        }
        $saved = @{ Server = $env:GITHUB_SERVER_URL; Repository = $env:GITHUB_REPOSITORY }
        try {
            $env:GITHUB_SERVER_URL = $null; $env:GITHUB_REPOSITORY = $null
            Assert-Equal 'https://github.com/TheAngryByrd/fsharp-skills' (Get-BuiltData 'default').repoUrl 'the repository link defaults to the upstream repository'
            $env:GITHUB_SERVER_URL = 'https://github.example/'; $env:GITHUB_REPOSITORY = 'someone/fork'
            Assert-Equal 'https://github.example/someone/fork' (Get-BuiltData 'fork').repoUrl 'the repository link follows GITHUB_SERVER_URL and GITHUB_REPOSITORY'
        } finally { $env:GITHUB_SERVER_URL = $saved.Server; $env:GITHUB_REPOSITORY = $saved.Repository }
    }

    Test-Case 'documented workflow triggers match the workflow' {
        $repo = Split-Path $evals
        $workflow = Get-Content (Join-Path $repo '.github/workflows/eval-dashboard.yml')
        $paths = @($workflow | Where-Object { $_ -match "^\s+- '(?<path>[^']+)'$" } | ForEach-Object { $Matches.path })
        Assert-True ($paths.Count -ge 9) 'the workflow lists its trigger paths' "found $($paths.Count)"
        $docs = @{ 'evals/README.md' = [IO.File]::ReadAllText((Join-Path $evals 'README.md')); 'lode/eval-dashboard.md' = [IO.File]::ReadAllText((Join-Path $repo 'lode/eval-dashboard.md')) }
        foreach ($doc in $docs.Keys) {
            foreach ($path in $paths) { Assert-True ($docs[$doc].Contains("``$path``")) "$doc names the trigger path $path" }
        }
        foreach ($test in 'Dashboard.Tests.ps1', 'Metrics.Tests.ps1') {
            Assert-True (($workflow -join "`n").Contains("./evals/tests/$test")) "the workflow runs $test"
        }
    }

    Test-Case 'the README has no lazy list continuation line' {
        $lazy = @([IO.File]::ReadAllLines((Join-Path $evals 'README.md')) | Where-Object { $_ -match '^ [^ ]' })
        Assert-Equal 0 $lazy.Count 'no README line starts with a single space'
    }

    Test-Case 'the page explains every not-comparable case' {
        $js = [IO.File]::ReadAllText((Join-Path $evals 'dashboard/dashboard.js'))
        Assert-True ($js -match "'Not comparable', '[^']*no counted run[^']*graded check") 'the not-comparable rule names the no-counted-run and no-graded-check cases'
    }
} finally { Remove-Item -Recurse -Force $root }

if ($failures.Count) { $failures | ForEach-Object { Write-Error $_ -ErrorAction Continue }; exit 1 }
