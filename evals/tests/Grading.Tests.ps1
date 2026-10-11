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

if ($failures.Count) { throw "$($failures.Count) test(s) failed: $($failures -join ', ')" }
Write-Host 'All grading helper tests passed.'
