#!/usr/bin/env pwsh
#Requires -Version 7.4
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../lib/Grading.psm1') -Force

$failures = [System.Collections.Generic.List[string]]::new()
function Assert-That([string]$Name, [bool]$Condition, [string]$Detail = '') {
    if ($Condition) { Write-Host "PASS $Name" } else { Write-Host "FAIL $Name $Detail"; $failures.Add($Name) }
}

$root = Join-Path ([IO.Path]::GetTempPath()) ("rubric-tests-" + [guid]::NewGuid().ToString('n'))
$evalDir = Join-Path $root 'eval'
New-Item -ItemType Directory -Force -Path (Join-Path $evalDir 'inputs') | Out-Null
[IO.File]::WriteAllText((Join-Path $evalDir 'inputs/Orders.fsx'), "let total = 1`nlet unchanged = 2`n")
@{
    skill = 'demo'
    tasks = @(@{
            id = 'demo-task'; files = @('inputs/Orders.fsx'); grader = 'graders/demo.ps1'; prompt = 'secret prompt'
            rubric = @(
                @{ id = 'reuse'; question = 'Does the change reuse total?' },
                @{ id = 'small'; question = 'Is the change small?' }
            )
        })
} | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $evalDir 'evals.json') -Encoding utf8

function New-Workspace {
    $ws = Join-Path $root ("ws-" + [guid]::NewGuid().ToString('n'))
    New-Item -ItemType Directory -Force -Path (Join-Path $ws '.claude/skills/demo-eval') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $ws '.agents/skills/demo-eval') | Out-Null
    Set-Content (Join-Path $ws '.claude/skills/demo-eval/SKILL.md') 'name: demo-eval SKILLTEXT' -Encoding utf8
    Set-Content (Join-Path $ws '.agents/skills/demo-eval/SKILL.md') 'name: demo-eval SKILLTEXT' -Encoding utf8
    Set-Content (Join-Path $ws 'TASK.md') 'secret prompt' -Encoding utf8
    Set-Content (Join-Path $ws 'Orders.fsx') "let total = 42`nlet unchanged = 2" -Encoding utf8
    Set-Content (Join-Path $ws 'Added.fs') 'module Added' -Encoding utf8
    $ws
}

try {
    $ws = New-Workspace
    $diff = Get-WorkspaceDiff -Workspace $ws -EvalDir $evalDir -TaskId 'demo-task'
    Assert-That 'diff shows the changed line' ($diff -match '(?m)^\+let total = 42') $diff
    Assert-That 'diff shows the removed line' ($diff -match '(?m)^-let total = 1') $diff
    Assert-That 'diff shows a new file' ($diff -match 'module Added') $diff
    Assert-That 'diff omits the installed skill' ($diff -notmatch 'SKILLTEXT|demo-eval') $diff
    Assert-That 'diff omits TASK.md' ($diff -notmatch 'TASK\.md|secret prompt') $diff
    Assert-That 'diff hides the run path' ($diff -notmatch [regex]::Escape((Split-Path $ws -Leaf))) $diff

    $crlf = New-Workspace
    [IO.File]::WriteAllText((Join-Path $crlf 'Orders.fsx'), "let total = 42`r`nlet unchanged = 2`r`n")
    $crlfDiff = Get-WorkspaceDiff -Workspace $crlf -EvalDir $evalDir -TaskId 'demo-task'
    Assert-That 'line endings alone do not show as changes' ($crlfDiff -notmatch '(?m)^[-+]let unchanged') $crlfDiff

    $fakeJudge = Join-Path $root 'fake-judge.ps1'
    Set-Content $fakeJudge @'
param([string]$ResponseFile, [string]$PromptFile, [int]$ExitCode = 0)
[Console]::In.ReadToEnd() | Set-Content -Path $PromptFile -Encoding utf8
Get-Content -Raw $ResponseFile
exit $ExitCode
'@ -Encoding utf8
    $promptFile = Join-Path $root 'prompt.txt'
    $responseFile = Join-Path $root 'response.json'
    function Invoke-FakeRubric([string]$Response, [int]$ExitCode = 0) {
        Set-Content $responseFile $Response -Encoding utf8
        $env:SKILL_EVAL_JUDGE = ConvertTo-Json -Compress @('pwsh', '-NoProfile', '-File', $fakeJudge, $responseFile, $promptFile, "$ExitCode")
        try { @(Invoke-Rubric -Workspace $ws -EvalDir $evalDir -TaskId 'demo-task') } finally { Remove-Item env:SKILL_EVAL_JUDGE }
    }

    $checks = Invoke-FakeRubric '{"items":[{"id":"reuse","answer":"yes","quote":"let total = 42"},{"id":"small","answer":"no","quote":"module   Added"}]}'
    Assert-That 'one check per rubric item' ($checks.Count -eq 2) "$($checks.Count)"
    Assert-That 'yes with a diff quote passes' ($checks[0].passed -eq $true -and $checks[0].text -match 'reuse total') ($checks[0] | ConvertTo-Json)
    Assert-That 'evidence holds the quote' ($checks[0].evidence -match 'let total = 42') $checks[0].evidence
    Assert-That 'no with a diff quote fails' ($checks[1].passed -eq $false) ($checks[1] | ConvertTo-Json)
    $prompt = Get-Content -Raw $promptFile
    Assert-That 'judge sees the diff and the questions' ($prompt -match 'let total = 42' -and $prompt -match 'Is the change small\?') $prompt
    Assert-That 'judge does not see the skill, mode, or task prompt' ($prompt -notmatch 'SKILLTEXT|demo-eval|secret prompt|with skill|without skill') $prompt

    $checks = Invoke-FakeRubric '{"items":[{"id":"reuse","answer":"yes","quote":"let invented = 7"},{"id":"small","answer":"yes","quote":""}]}'
    Assert-That 'a quote that is not in the diff skips the check' ($null -eq $checks[0].passed -and $checks[0].evidence -match 'not found') ($checks[0] | ConvertTo-Json)
    Assert-That 'an empty quote skips the check' ($null -eq $checks[1].passed) ($checks[1] | ConvertTo-Json)

    $checks = Invoke-FakeRubric '{"items":[{"id":"reuse","answer":"yes","quote":"let total = 42"}]}'
    Assert-That 'a missing answer skips the check' ($checks.Count -eq 2 -and $null -eq $checks[1].passed) ($checks | ConvertTo-Json)

    $checks = Invoke-FakeRubric '{"type":"result","result":"x","structured_output":{"items":[{"id":"reuse","answer":"yes","quote":"let total = 42"},{"id":"small","answer":"yes","quote":"module Added"}]}}'
    Assert-That 'claude structured output is read' ($checks[0].passed -eq $true -and $checks[1].passed -eq $true) ($checks | ConvertTo-Json)

    $checks = Invoke-FakeRubric 'Here is my answer: {"items":[{"id":"reuse","answer":"yes","quote":"let total = 42"}]} done'
    Assert-That 'JSON in free text is read' ($checks[0].passed -eq $true) ($checks | ConvertTo-Json)

    $checks = Invoke-FakeRubric 'boom' 3
    Assert-That 'a failed judge skips every item' ($checks.Count -eq 2 -and @($checks | Where-Object { $null -ne $_.passed }).Count -eq 0 -and $checks[0].evidence -match 'judge') ($checks | ConvertTo-Json)

    foreach ($shape in '{"items":[{"id":"reuse","answer":"yes"}]}', '{"items":[{"answer":"yes","quote":"let total = 42"}]}',
        '{"items":"none"}', '{"type":"result","result":"x","structured_output":{"verdicts":[]}}') {
        $checks = Invoke-FakeRubric $shape
        Assert-That "malformed judge output skips: $shape" ($checks.Count -eq 2 -and @($checks | Where-Object { $null -ne $_.passed }).Count -eq 0 -and $checks[0].evidence -match '^skipped:') ($checks | ConvertTo-Json)
    }

    foreach ($quote in 'diff --git', '@@ -1,2', 'let total = 42 let unchanged = 2', 'le') {
        $checks = Invoke-FakeRubric ('{"items":[{"id":"reuse","answer":"yes","quote":' + (ConvertTo-Json $quote) + '}]}')
        Assert-That "a header, multi-line, or tiny quote skips: $quote" ($null -eq $checks[0].passed) ($checks[0] | ConvertTo-Json)
    }

    $checks = Invoke-FakeRubric '{"items":[{"id":"reuse","answer":"no","quote":"+let total = 42"}]}'
    Assert-That 'a quote with its diff marker matches' ($checks[0].passed -eq $false) ($checks[0] | ConvertTo-Json)
    Assert-That 'check text starts with the item id' ($checks[0].text -like 'Rubric reuse: *') $checks[0].text

    Set-Content (Join-Path $ws 'Notes.md') 'I used the demo-eval skill.' -Encoding utf8
    $checks = Invoke-FakeRubric '{"items":[]}'
    Assert-That 'an empty items array gives a no-answer reason' ($null -eq $checks[0].passed -and $checks[0].evidence -match 'no answer') ($checks[0] | ConvertTo-Json)
    Assert-That 'the install name is removed from agent text' ((Get-Content -Raw $promptFile) -notmatch 'demo-eval') (Get-Content -Raw $promptFile)
    Remove-Item (Join-Path $ws 'Notes.md')

    Set-Content (Join-Path $ws 'Big.fs') (@(1..3000 | ForEach-Object { "let value$_ = $_ // padding padding" }) -join "`n") -Encoding utf8
    $checks = Invoke-FakeRubric '{"items":[{"id":"reuse","answer":"no","quote":"diff cut at 60000 characters"}]}'
    Assert-That 'the cut notice is not evidence' ($null -eq $checks[0].passed) ($checks[0] | ConvertTo-Json)
    Remove-Item (Join-Path $ws 'Big.fs')

    [IO.File]::WriteAllText((Join-Path $ws 'Orders.fsx'), "let total = 42 // price → €`nlet unchanged = 2`n")
    $checks = Invoke-FakeRubric '{"items":[{"id":"reuse","answer":"yes","quote":"let total = 42 // price → €"}]}'
    Assert-That 'non-ASCII quotes match' ($checks[0].passed -eq $true) ($checks[0] | ConvertTo-Json)

    foreach ($bad in 'claude -p', '[]', '"claude"') {
        $env:SKILL_EVAL_JUDGE = $bad
        try { $checks = @(Invoke-Rubric -Workspace $ws -EvalDir $evalDir -TaskId 'demo-task') } finally { Remove-Item env:SKILL_EVAL_JUDGE }
        Assert-That "an invalid judge setting skips: $bad" ($checks.Count -eq 2 -and $null -eq $checks[0].passed -and $checks[0].evidence -match 'SKILL_EVAL_JUDGE' -and $checks[0].evidence -notmatch 'is off') ($checks | ConvertTo-Json)
    }

    $badEval = Join-Path $root 'bad-eval'
    New-Item -ItemType Directory -Force -Path (Join-Path $badEval 'inputs') | Out-Null
    Copy-Item (Join-Path $evalDir 'inputs/Orders.fsx') (Join-Path $badEval 'inputs')
    @{ skill = 'demo'; tasks = @(@{ id = 'demo-task'; files = @('inputs/Orders.fsx'); rubric = @(@{ id = 'noquestion' }) }) } |
        ConvertTo-Json -Depth 6 | Set-Content (Join-Path $badEval 'evals.json') -Encoding utf8
    $env:SKILL_EVAL_JUDGE = ConvertTo-Json -Compress @('pwsh', '-NoProfile', '-File', $fakeJudge, $responseFile, $promptFile, '0')
    try { $checks = @(Invoke-Rubric -Workspace $ws -EvalDir $badEval -TaskId 'demo-task') }
    catch { $checks = @(); Assert-That 'a rubric item without a question does not throw' $false "$_" }
    finally { Remove-Item env:SKILL_EVAL_JUDGE }
    Assert-That 'a rubric item without a question is skipped' ($checks.Count -eq 1 -and $null -eq $checks[0].passed -and $checks[0].text -like 'Rubric noquestion*') ($checks | ConvertTo-Json)

    $env:GIT_EXTERNAL_DIFF = 'echo'
    try { $extDiff = Get-WorkspaceDiff -Workspace $ws -EvalDir $evalDir -TaskId 'demo-task' } finally { Remove-Item env:GIT_EXTERNAL_DIFF }
    Assert-That 'an external diff tool does not replace the unified diff' ($extDiff -match '(?m)^@@') $extDiff

    $env:SKILL_EVAL_JUDGE = 'off'
    try { $checks = @(Invoke-Rubric -Workspace $ws -EvalDir $evalDir -TaskId 'demo-task') } finally { Remove-Item env:SKILL_EVAL_JUDGE }
    Assert-That 'judge off skips every item' ($checks.Count -eq 2 -and $null -eq $checks[0].passed -and $checks[0].evidence -match 'skipped') ($checks | ConvertTo-Json)
}
finally {
    Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
}

if ($failures.Count) { throw "$($failures.Count) test(s) failed: $($failures -join ', ')" }
Write-Host 'All rubric tests passed.'
