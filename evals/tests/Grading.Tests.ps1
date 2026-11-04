#!/usr/bin/env pwsh
#Requires -Version 7.4
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../lib/Grading.psm1') -Force

$failures = [System.Collections.Generic.List[string]]::new()
function Assert-That([string]$Name, [bool]$Condition, [string]$Detail = '') {
    if ($Condition) { Write-Host "PASS $Name" } else { Write-Host "FAIL $Name $Detail"; $failures.Add($Name) }
}

$checks = @(ConvertFrom-ProbeOutput $null)
Assert-That 'null probe output gives no checks' ($checks.Count -eq 0) "$($checks.Count)"
$checks = @(ConvertFrom-ProbeOutput @())
Assert-That 'empty probe output gives no checks' ($checks.Count -eq 0) "$($checks.Count)"

$checks = @(ConvertFrom-ProbeOutput @('Loading script', '', 'PASS a [12 ms]', 'FAIL b', 'PASSED c', ' PASS d'))
Assert-That 'only PASS and FAIL lines give checks' ($checks.Count -eq 2) ($checks | ConvertTo-Json)
Assert-That 'a PASS line passes and drops the bracket detail' ($checks[0].text -eq 'a' -and $checks[0].passed -eq $true -and $checks[0].evidence -eq '') ($checks[0] | ConvertTo-Json)
Assert-That 'a FAIL line fails with the line as evidence' ($checks[1].text -eq 'b' -and $checks[1].passed -eq $false -and $checks[1].evidence -eq 'FAIL b') ($checks[1] | ConvertTo-Json)

$fixtures = Join-Path $PSScriptRoot 'fixtures'
$claude = @(Get-TranscriptCommands (Join-Path $fixtures 'claude.jsonl'))
Assert-That 'Claude transcript commands come from tool_use input' ($claude -contains 'ls' -and @($claude | Where-Object { $_ -like '*dotnet build*' }).Count -gt 0) ($claude -join ' | ')
$codex = @(Get-TranscriptCommands (Join-Path $fixtures 'codex.jsonl'))
Assert-That 'Codex transcript commands come from command items' (@($codex | Where-Object { $_ -like "*dotnet test*" }).Count -gt 0) ($codex -join ' | ')
$opencode = @(Get-TranscriptCommands (Join-Path $fixtures 'opencode.jsonl'))
Assert-That 'opencode transcript commands come from tool state input' (@($opencode | Where-Object { $_ -like 'dotnet fsi*' }).Count -gt 0) ($opencode -join ' | ')
Assert-That 'a missing transcript gives no commands' (@(Get-TranscriptCommands (Join-Path $fixtures 'missing.jsonl')).Count -eq 0)
Assert-That 'an empty transcript gives no commands' (@(Get-TranscriptCommands (Join-Path $fixtures 'empty.jsonl')).Count -eq 0)
foreach ($agent in 'claude', 'codex', 'opencode') {
    $results = @(Get-TranscriptCommandResults (Join-Path $fixtures "$agent.jsonl"))
    $build = $results | Where-Object { $_.Command -match 'dotnet build' } | Select-Object -First 1
    Assert-That "$agent command results mark the failed dotnet build" ($null -ne $build -and $build.Failed -eq $true) ($results | ConvertTo-Json -Depth 3)
    Assert-That "$agent command results keep a successful command" (@($results | Where-Object { -not $_.Failed }).Count -gt 0) ($results | ConvertTo-Json -Depth 3)
}
$codexResults = @(Get-TranscriptCommandResults (Join-Path $fixtures 'codex.jsonl'))
Assert-That 'codex command results keep the command output' (@($codexResults | Where-Object { $_.Output -match 'Build FAILED' }).Count -eq 2) ($codexResults | ConvertTo-Json -Depth 3)
Assert-That 'a missing transcript gives no command results' (@(Get-TranscriptCommandResults (Join-Path $fixtures 'missing.jsonl')).Count -eq 0)

$root = Join-Path ([IO.Path]::GetTempPath()) ("grading-tests-" + [guid]::NewGuid().ToString('n'))
New-Item -ItemType Directory -Force -Path $root | Out-Null
try {
    $probe = Join-Path $root 'Probe.fsx'
    $nested = Join-Path $root 'Nested.fsx'
    $flat = Join-Path $root 'Flat.fsx'
    [IO.File]::WriteAllText($nested, "module Reports =`n    let x = 1`n")
    [IO.File]::WriteAllText($flat, "module Reports`nlet x = 1`n")

    foreach ($eol in "`n", "`r`n") {
        $label = if ($eol -eq "`n") { 'LF' } else { 'CRLF' }
        [IO.File]::WriteAllText($probe, "#load `"Reports.fsx`"$eol" + "open Reports$eol" + "open Reports.Extra$eol")
        $text = Get-ProbeScript -ProbePath $probe -SourcePath $nested -Module 'Reports'
        Assert-That "a nested module adds open Reports.Reports ($label)" ($text -match '(?m)^open Reports\r?\nopen Reports\.Reports\r?$') $text
        Assert-That "a nested module leaves other open lines ($label)" (@([regex]::Matches($text, '(?m)^open Reports\.Reports\r?$')).Count -eq 1 -and $text -match 'open Reports\.Extra') $text
        $text = Get-ProbeScript -ProbePath $probe -SourcePath $flat -Module 'Reports'
        Assert-That "a top-level module leaves the probe unchanged ($label)" ($text -eq [IO.File]::ReadAllText($probe)) $text
    }
}
finally {
    Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
}

$done = Invoke-Capture pwsh @('-NoProfile', '-Command', 'Write-Output a; [Console]::Error.WriteLine("b"); exit 3') -TimeoutSeconds 60
Assert-That 'a time limit keeps the exit code, stdout, and stderr of a command that ends' ($done.ExitCode -eq 3 -and -not $done.TimedOut -and $done.Lines -contains 'a' -and $done.Lines -contains 'b') ($done | ConvertTo-Json)
$pidFile = Join-Path ([IO.Path]::GetTempPath()) ("invoke-capture-" + [guid]::NewGuid().ToString('n') + '.txt')
$watch = [Diagnostics.Stopwatch]::StartNew()
$hung = Invoke-Capture pwsh @('-NoProfile', '-Command', "Write-Output started; `$c = Start-Process pwsh -ArgumentList '-NoProfile','-Command','Start-Sleep 600' -NoNewWindow -PassThru; Set-Content '$pidFile' `$c.Id; Start-Sleep 600") -TimeoutSeconds 10
$watch.Stop()
$child = Get-Content $pidFile -ErrorAction SilentlyContinue
Assert-That 'a command over the time limit stops with TimedOut and its output' ($hung.TimedOut -and $hung.ExitCode -eq -1 -and $hung.Lines -contains 'started' -and $hung.Text -match 'timed out after 10 seconds' -and $watch.Elapsed.TotalSeconds -lt 120) ($hung | ConvertTo-Json)
Assert-That 'a command over the time limit stops its child processes' ($child -and -not (Get-Process -Id $child -ErrorAction SilentlyContinue)) "child $child"
Remove-Item $pidFile -ErrorAction SilentlyContinue
$watch = [Diagnostics.Stopwatch]::StartNew()
$orphaned = Invoke-Capture pwsh @('-NoProfile', '-Command', "Write-Output started; `$c = Start-Process pwsh -ArgumentList '-NoProfile','-Command','Start-Sleep 600' -NoNewWindow -PassThru; Set-Content '$pidFile' `$c.Id; exit 0") -TimeoutSeconds 10
$watch.Stop()
$child = Get-Content $pidFile -ErrorAction SilentlyContinue
Assert-That 'a child that keeps the output open after its parent exits stops at the time limit' ($orphaned.TimedOut -and $orphaned.Lines -contains 'started' -and $watch.Elapsed.TotalSeconds -lt 120) "$($watch.Elapsed.TotalSeconds) s $($orphaned | ConvertTo-Json)"
Assert-That 'a child that outlives its parent is stopped' ($child -and -not (Get-Process -Id $child -ErrorAction SilentlyContinue)) "child $child"
Remove-Item $pidFile -ErrorAction SilentlyContinue

if ($failures.Count) { throw "$($failures.Count) test(s) failed: $($failures -join ', ')" }
Write-Host 'All grading helper tests passed.'
