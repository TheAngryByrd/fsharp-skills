Set-StrictMode -Version Latest

$DashboardSchemaVersion = 1

$Thresholds = [pscustomobject]@{
    PassRateDelta    = 0.10
    FailedBuildsDrop = 1.0
    TurnsDropRatio   = 0.25
    MinCountedRuns   = 3
}

function Format-Percent([double]$Ratio) { ([math]::Round($Ratio * 100)).ToString('0', [Globalization.CultureInfo]::InvariantCulture) + '%' }
function Format-Points([double]$Delta) { $p = [math]::Round($Delta * 100); ($(if ($p -gt 0) { '+' } else { '' })) + $p.ToString('0', [Globalization.CultureInfo]::InvariantCulture) }
function Format-One([double]$Value) { $Value.ToString('0.0', [Globalization.CultureInfo]::InvariantCulture) }

function Get-Mean([object[]]$Values) {
    $v = @($Values | Where-Object { $null -ne $_ })
    if ($v.Count -eq 0) { return $null }
    ($v | Measure-Object -Average).Average
}

function Get-CheckTally($Run) {
    $checks = @($Run.checks)
    [pscustomobject]@{
        Passed = @($checks | Where-Object { $_.passed -eq $true }).Count
        Failed = @($checks | Where-Object { $_.passed -eq $false }).Count
    }
}

function Get-ModeStats {
    param([object[]]$Runs, [Parameter(Mandatory)][ValidateSet('with', 'without')][string]$Mode)
    $all = @($Runs | Where-Object { $_.mode -eq $Mode })
    $counted = @($all | Where-Object { $Mode -eq 'without' -or $_.skillUsed -eq $true })
    $tallies = @($counted | ForEach-Object { Get-CheckTally $_ })
    $graded = @($tallies | Where-Object { ($_.Passed + $_.Failed) -gt 0 })
    $tokens = $counted | ForEach-Object { if ($null -ne $_.inputTokens) { $_.inputTokens + $_.outputTokens } }
    [pscustomobject]@{
        runs             = $all.Count
        counted          = $counted.Count
        notLoaded        = $all.Count - $counted.Count
        passRate         = Get-Mean ($graded | ForEach-Object { $_.Passed / ($_.Passed + $_.Failed) })
        allPassRuns      = @($graded | Where-Object { $_.Failed -eq 0 }).Count
        meanSeconds      = Get-Mean ($counted | ForEach-Object { $_.seconds })
        meanTokens       = Get-Mean $tokens
        meanTurns        = Get-Mean ($counted | ForEach-Object { $_.turns })
        meanFailedBuilds = Get-Mean ($counted | ForEach-Object { $_.failedBuilds })
        meanCostUsd      = Get-Mean ($counted | ForEach-Object { $_.costUsd })
    }
}

function Get-VerdictContext($With, $Without) {
    $delta = $null
    if ($null -ne $With.passRate -and $null -ne $Without.passRate) { $delta = [math]::Round($With.passRate - $Without.passRate, 4) }
    $buildsDrop = $null
    if ($null -ne $With.meanFailedBuilds -and $null -ne $Without.meanFailedBuilds) { $buildsDrop = [math]::Round($Without.meanFailedBuilds - $With.meanFailedBuilds, 4) }
    $turnsDrop = $null
    if ($null -ne $With.meanTurns -and $null -ne $Without.meanTurns -and $Without.meanTurns -gt 0) { $turnsDrop = [math]::Round(($Without.meanTurns - $With.meanTurns) / $Without.meanTurns, 4) }
    [pscustomobject]@{ With = $With; Without = $Without; Delta = $delta; FailedBuildsDrop = $buildsDrop; TurnsDropRatio = $turnsDrop }
}

function Get-EffortClauses($c) {
    $clauses = @()
    if ($null -ne $c.FailedBuildsDrop -and $c.FailedBuildsDrop -ge $Thresholds.FailedBuildsDrop) {
        $clauses += "failed builds fell from $(Format-One $c.Without.meanFailedBuilds) to $(Format-One $c.With.meanFailedBuilds)"
    }
    if ($null -ne $c.TurnsDropRatio -and $c.TurnsDropRatio -ge $Thresholds.TurnsDropRatio) {
        $clauses += "turns fell from $(Format-One $c.Without.meanTurns) to $(Format-One $c.With.meanTurns) (-$(Format-Percent $c.TurnsDropRatio))"
    }
    $clauses
}

$VerdictRules = @(
    [pscustomobject]@{
        Direction = 'not-comparable'
        Matches   = { param($c) $null -eq $c.Delta }
        Reason    = {
            param($c)
            if ($c.With.runs -eq 0) { 'No run with the skill is available to compare.' }
            elseif ($c.With.counted -eq 0) { "No with-skill run counts: the agent loaded the skill in $($c.With.counted) of $($c.With.runs) runs." }
            elseif ($c.Without.counted -eq 0) { 'No run without the skill is available to compare.' }
            else { 'No counted run has a graded check.' }
        }
    }
    [pscustomobject]@{
        Direction = 'better'
        Matches   = { param($c) $c.Delta -ge $Thresholds.PassRateDelta }
        Reason    = { param($c) "Pass rate rose from $(Format-Percent $c.Without.passRate) to $(Format-Percent $c.With.passRate) ($(Format-Points $c.Delta) points)." }
    }
    [pscustomobject]@{
        Direction = 'worse'
        Matches   = { param($c) $c.Delta -le -$Thresholds.PassRateDelta }
        Reason    = { param($c) "Pass rate fell from $(Format-Percent $c.Without.passRate) to $(Format-Percent $c.With.passRate) ($(Format-Points $c.Delta) points)." }
    }
    [pscustomobject]@{
        Direction = 'less-effort'
        Matches   = { param($c) @(Get-EffortClauses $c).Count -gt 0 }
        Reason    = { param($c) "Pass rate is about the same ($(Format-Percent $c.Without.passRate) to $(Format-Percent $c.With.passRate)), and $((@(Get-EffortClauses $c)) -join ' and ')." }
    }
    [pscustomobject]@{
        Direction = 'no-change'
        Matches   = { param($c) $true }
        Reason    = { param($c) "Pass rate is about the same ($(Format-Percent $c.Without.passRate) to $(Format-Percent $c.With.passRate)), and effort did not drop by the thresholds." }
    }
)

function Get-Verdict {
    param([Parameter(Mandatory)]$With, [Parameter(Mandatory)]$Without)
    $context = Get-VerdictContext $With $Without
    $rule = $VerdictRules | Where-Object { & $_.Matches $context } | Select-Object -First 1
    [pscustomobject]@{
        direction    = $rule.Direction
        underpowered = ([math]::Min($With.counted, $Without.counted) -lt $Thresholds.MinCountedRuns)
        reason       = & $rule.Reason $context
    }
}

function Get-CheckMatrix([object[]]$Runs) {
    $counted = @($Runs | Where-Object { $_.mode -eq 'without' -or $_.skillUsed -eq $true })
    $texts = @($counted | ForEach-Object { $_.checks } | ForEach-Object { $_.text } | Select-Object -Unique)
    foreach ($text in $texts) {
        $cells = foreach ($mode in 'with', 'without') {
            $hits = @($counted | Where-Object { $_.mode -eq $mode } | ForEach-Object { $_.checks } | Where-Object { $_.text -eq $text -and $null -ne $_.passed })
            [pscustomobject]@{ passed = @($hits | Where-Object { $_.passed -eq $true }).Count; total = $hits.Count }
        }
        [pscustomobject]@{ text = $text; with = $cells[0]; without = $cells[1] }
    }
}

function Get-ComparisonDate($StartedAt, [string]$RunId) {
    if ($StartedAt) { return "$StartedAt".Substring(0, 10) }
    if ($RunId -match '^(\d{4})(\d{2})(\d{2})-') { return "$($Matches[1])-$($Matches[2])-$($Matches[3])" }
    $null
}

function New-Comparison {
    param([Parameter(Mandatory)][string]$RunId, [Parameter(Mandatory)][object[]]$Runs)
    $with = Get-ModeStats -Runs $Runs -Mode with
    $without = Get-ModeStats -Runs $Runs -Mode without
    $starts = @($Runs | ForEach-Object { $_.startedAt } | Where-Object { $_ } | Sort-Object)
    $started = if ($starts.Count) { $starts[0] } else { $null }
    $commits = @($Runs | ForEach-Object { $_.skillCommit } | Where-Object { $_ } | Select-Object -Unique)
    $models = @($Runs | ForEach-Object { $_.resolvedModel } | Where-Object { $_ } | Select-Object -Unique | Sort-Object)
    [pscustomobject]@{
        runId         = $RunId
        startedAt     = $started
        date          = Get-ComparisonDate $started $RunId
        skillCommit   = $(if ($commits.Count) { $commits[0] } else { $null })
        skillDirty    = @($Runs | Where-Object { $_.skillDirty -eq $true }).Count -gt 0
        resolvedModel = $models -join ', '
        with          = $with
        without       = $without
        verdict       = Get-Verdict -With $with -Without $without
        checks        = @(Get-CheckMatrix $Runs)
    }
}

function New-TargetEntry([string]$Task, [string]$Target, [string]$Model, [object[]]$Sets) {
    $inEntry = { $_.task -eq $Task -and $_.target -eq $Target -and "$($_.resolvedModel)" -eq $Model }
    $history = foreach ($set in $Sets | Sort-Object { $_.runId }) {
        $runs = @($set.runs | Where-Object $inEntry)
        if ($runs.Count) { New-Comparison -RunId $set.runId -Runs $runs }
    }
    $history = @($history)
    if ($history.Count -eq 0) { return }
    $agent = @($Sets | ForEach-Object { $_.runs } | Where-Object $inEntry | ForEach-Object { $_.agent })[0]
    [pscustomobject]@{ target = $Target; agent = $agent; resolvedModel = $Model; superseded = $false; latest = $history[-1]; history = $history }
}

function New-DashboardData {
    param(
        [Parameter(Mandatory)][object[]]$Catalog,
        [object[]]$ResultSets = @(),
        [string]$Commit = '',
        [string]$RepoUrl = '',
        [Parameter(Mandatory)][string]$GeneratedAt
    )
    $names = @($Catalog | ForEach-Object { $_.skill }) + @($ResultSets | ForEach-Object { $_.skill }) | Select-Object -Unique | Sort-Object
    $skills = foreach ($name in $names) {
        $entry = $Catalog | Where-Object { $_.skill -eq $name } | Select-Object -First 1
        $sets = @($ResultSets | Where-Object { $_.skill -eq $name })
        $taskIds = @(if ($entry) { $entry.tasks }) + @($sets | ForEach-Object { $_.runs } | ForEach-Object { $_.task }) | Select-Object -Unique
        $pairs = @($sets | ForEach-Object { $_.runs } | ForEach-Object { [pscustomobject]@{ target = $_.target; model = "$($_.resolvedModel)" } } | Sort-Object target, model -Unique)
        $tasks = foreach ($task in $taskIds) {
            $entries = @($pairs | ForEach-Object { New-TargetEntry $task $_.target $_.model $sets })
            foreach ($group in $entries | Group-Object target) {
                $newest = @($group.Group | ForEach-Object { $_.latest.runId } | Sort-Object)[-1]
                foreach ($row in $group.Group) { $row.superseded = $row.latest.runId -ne $newest }
            }
            [pscustomobject]@{ task = $task; targets = $entries }
        }
        [pscustomobject]@{ skill = $name; description = $(if ($entry) { $entry.description } else { '' }); tasks = @($tasks) }
    }
    [pscustomobject]@{
        schemaVersion = $DashboardSchemaVersion
        generatedAt   = $GeneratedAt
        commit        = $(if ($Commit) { $Commit } else { $null })
        repoUrl       = $(if ($RepoUrl) { $RepoUrl } else { $null })
        thresholds    = $Thresholds
        skills        = @($skills)
    }
}

Export-ModuleMember -Function Get-ModeStats, Get-Verdict, New-Comparison, New-DashboardData
