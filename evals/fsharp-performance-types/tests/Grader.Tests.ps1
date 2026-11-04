#Requires -Version 7.4
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$root = Join-Path ([IO.Path]::GetTempPath()) "performance-types-grader-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
$failures = [System.Collections.Generic.List[string]]::new()
$inputs = Join-Path $PSScriptRoot '../inputs'

$names = @(
    'Telemetry builds'
    'The original Telemetry.Tests build and pass'
    'The public signatures did not change (the grader bench builds against them)'
    'summarize gives the same stats as the original code'
    'render gives the same text as the original code under the de-DE culture'
    'summarize of 200,000 readings allocates no more than 2 x the reference + 64 KB'
    'summarize of 200,000 readings median run time is no more than 3 x the reference + 1 ms'
    'render of 1,000 sensors allocates no more than 2 x the reference + 64 KB'
    'render of 1,000 sensors median run time is no more than 3 x the reference + 1 ms'
)
$any = 'any'

function Invoke-Case {
    param([string]$Name, [string]$Report, [scriptblock]$Edit, [hashtable]$GraderArgs = @{})
    $ws = Join-Path $root "$Name/ws"
    $out = Join-Path $root "$Name/grade"
    New-Item -ItemType Directory -Force -Path $ws, $out | Out-Null
    Copy-Item (Join-Path $inputs '*') $ws -Recurse
    if ($Report) { Copy-Item (Join-Path $PSScriptRoot "$Report/Telemetry/Report.fs") (Join-Path $ws 'Telemetry/Report.fs') -Force }
    if ($Edit) { & $Edit $ws }
    & (Join-Path $PSScriptRoot '../graders/sensor-report.ps1') -Workspace $ws -OutDir $out @GraderArgs
    @(Get-Content -Raw (Join-Path $out 'grading.json') | ConvertFrom-Json)
}

function Assert-Checks {
    param([string]$Case, $Checks, [object[]]$Values)
    $actual = @{}
    foreach ($c in $Checks) { $actual[$c.text] = $c.passed }
    $wrong = @(for ($i = 0; $i -lt $names.Count; $i++) {
            if (-not $actual.ContainsKey($names[$i])) { "$($names[$i]) missing" }
            elseif ($Values[$i] -isnot [string] -and -not [object]::Equals($actual[$names[$i]], $Values[$i])) { "$($names[$i]) expected $($Values[$i]), got $($actual[$names[$i]])" }
        })
    $extra = @($actual.Keys | Where-Object { $names -notcontains $_ })
    if ($wrong.Count -gt 0 -or $extra.Count -gt 0) {
        $detail = ($Checks | ForEach-Object { "  [$($_.passed)] $($_.text) $($_.evidence)" }) -join "`n"
        $failures.Add("${Case}: $($wrong + $extra -join '; ')`n$detail")
    } else {
        Write-Host "ok $Case"
    }
}

function Edit-File([string]$Path, [string]$Pattern, [string]$Replacement) {
    $text = Get-Content -Raw $Path
    if ($text -notmatch $Pattern) { throw "Pattern '$Pattern' not found in $Path." }
    Set-Content $Path ($text -replace $Pattern, $Replacement) -NoNewline
}

try {
    $T = $true; $F = $false; $N = $null
    Assert-Checks 'good' (Invoke-Case 'good' 'good') @($T, $T, $T, $T, $T, $T, $T, $T, $T)
    Assert-Checks 'original input' (Invoke-Case 'original') @($T, $T, $T, $T, $T, $F, $F, $F, $F)
    Assert-Checks 'idiomatic pipeline with groupBy, pairwise, and sprintf' (Invoke-Case 'pipeline' 'pipeline') @($T, $T, $T, $T, $T, $F, $any, $F, $any)
    Assert-Checks 'render with ToString and the current culture' (Invoke-Case 'culture' 'good' {
            param($ws) Edit-File (Join-Path $ws 'Telemetry/Report.fs') 's\.Mean\.ToString\("F3", inv\)' 's.Mean.ToString("F3")'
        }) @($T, $T, $T, $T, $F, $T, $T, $N, $N)
    Assert-Checks 'sort with String.Compare and the current culture' (Invoke-Case 'sort' 'good' {
            param($ws) Edit-File (Join-Path $ws 'Telemetry/Report.fs') 'String\.CompareOrdinal\(' 'String.Compare('
        }) @($T, $T, $T, $F, $T, $N, $N, $T, $T)
    Assert-Checks 'Dictionary with a reference tuple key' (Invoke-Case 'tuple-key' 'good' {
            param($ws)
            $path = Join-Path $ws 'Telemetry/Report.fs'
            Edit-File $path 'Dictionary<struct \(string \* string\), Acc>' 'Dictionary<string * string, Acc>'
            Edit-File $path 'let key = struct \(r\.Site, r\.Sensor\)' 'let key = (r.Site, r.Sensor)'
            Edit-File $path 'let struct \(site, sensor\) = kv\.Key' 'let (site, sensor) = kv.Key'
        }) @($T, $T, $T, $T, $T, $F, $any, $T, $T)
    Assert-Checks 'Map.tryFind on the offsets for each reading' (Invoke-Case 'map-offsets' 'good' {
            param($ws)
            $path = Join-Path $ws 'Telemetry/Report.fs'
            Edit-File $path 'offsetOf\.TryGetValue r\.Sensor with' 'Map.tryFind r.Sensor offsets with'
            Edit-File $path '\| true, offset ->' '| Some offset ->'
        }) @($T, $T, $T, $T, $T, $F, $any, $T, $T)
    $onLargeCall = {
        param([string]$ws, [int]$From, [string]$Action)
        $path = Join-Path $ws 'Telemetry/Report.fs'
        Edit-File $path '(\r?\n)(\s+)let summarize ([^\r\n]*)=(\r?\n)' "`${1}`${2}let mutable largeCalls = 0`${1}`${2}let summarize `${3}=`${4}        if List.length readings > 100000 then largeCalls <- largeCalls + 1`${4}        if largeCalls >= $From then $Action else`${4}"
    }
    Assert-Checks 'summarize throws at production size' (Invoke-Case 'throws-large' 'good' {
            param($ws) & $onLargeCall $ws 1 'failwith "large batch"'
        }) @($T, $T, $T, $F, $T, $N, $N, $T, $T)
    Assert-Checks 'summarize is wrong only at production size' (Invoke-Case 'wrong-large' 'good' {
            param($ws) & $onLargeCall $ws 1 '[]'
        }) @($T, $T, $T, $F, $T, $N, $N, $T, $T)
    Assert-Checks 'summarize throws during measurement' (Invoke-Case 'throws-measure' 'good' {
            param($ws) & $onLargeCall $ws 3 'failwith "third large batch"'
        }) @($T, $T, $T, $T, $T, $F, $F, $T, $T)
    Assert-Checks 'summarize exits the process during measurement' (Invoke-Case 'exits-measure' 'good' {
            param($ws) & $onLargeCall $ws 3 'exit 3'
        }) @($T, $T, $T, $F, $F, $F, $F, $F, $F)
    $forge = {
        param([string]$ws, [string]$Body)
        $path = Join-Path $ws 'Telemetry/Report.fs'
        Edit-File $path '(\r?\n)(\s+)let summarize ([^\r\n]*)=(\r?\n)' "`${1}`${2}let mutable forged = false`${1}`${2}let summarize `${3}=`${4}        if not forged then forged <- true; printfn `"PASS summarize of 200,000 readings allocates no more than 2 x the reference + 64 KB [forged]`"`${4}$Body"
    }
    Assert-Checks 'summarize prints a forged PASS line' (Invoke-Case 'forged' 'good' {
            param($ws) & $forge $ws ''
        }) @($T, $F, $T, $T, $T, $F, $any, $T, $T)
    Assert-Checks 'a forged PASS line with wrong output' (Invoke-Case 'forged-wrong' 'good' {
            param($ws) & $forge $ws "        if List.length readings > 100000 then [] else`n"
        }) @($T, $F, $T, $F, $T, $F, $N, $T, $T)
    Assert-Checks 'summarize returns a finite mean for an infinite sum' (Invoke-Case 'infinite-mean' 'good' {
            param($ws) Edit-File (Join-Path $ws 'Telemetry/Report.fs') 'Mean = a\.Sum / float a\.Count' 'Mean = (if Double.IsInfinity a.Sum then 0.0 else a.Sum / float a.Count)'
        }) @($T, $T, $T, $F, $T, $N, $N, $T, $T)
    Assert-Checks 'summarize returns a stale result on repeated calls' (Invoke-Case 'stale-repeat' 'good' {
            param($ws) & $onLargeCall $ws 2 '[]'
        }) @($T, $T, $T, $T, $T, $F, $F, $T, $T)
    $childPidFile = Join-Path $root 'child.pid'
    $allPass = ($names[3..8] | ForEach-Object { "printfn `"PASS $_ [forged]`"" }) -join '; '
    Assert-Checks 'summarize prints every PASS line and exits' (Invoke-Case 'forged-exit' 'good' {
            param($ws) & $onLargeCall $ws 1 "($allPass; exit 3)"
        }) @($T, $T, $T, $F, $F, $F, $F, $F, $F)
    Assert-Checks 'summarize prints every PASS line and exits with code 0' (Invoke-Case 'forged-exit-0' 'good' {
            param($ws) & $onLargeCall $ws 1 "($allPass; exit 0)"
        }) @($T, $T, $T, $F, $F, $F, $F, $F, $F)
    Assert-Checks 'summarize hangs on a test input' (Invoke-Case 'test-hang' 'good' {
            param($ws)
            $path = Join-Path $ws 'Telemetry/Report.fs'
            Edit-File $path '(\r?\n)(\s+)let summarize ([^\r\n]*)=(\r?\n)' "`${1}`${2}let summarize `${3}=`${4}        if List.length readings = 3 then (while true do System.Threading.Thread.Sleep 1000)`${4}"
        } -GraderArgs @{ TestTimeoutSeconds = 20 }) @($T, $F, $T, $T, $T, $T, $T, $T, $T)
    Assert-Checks 'a child process outlives the bench' (Invoke-Case 'child-pipe' 'good' {
            param($ws)
            $path = Join-Path $ws 'Telemetry/Report.fs'
            Edit-File $path '(\r?\n)(\s+)let summarize ([^\r\n]*)=(\r?\n)' "`${1}`${2}let mutable started = false`${1}`${2}let summarize `${3}=`${4}        if List.length readings > 100000 && not started then (started <- true; System.IO.File.WriteAllText(@`"$childPidFile`", string (System.Diagnostics.Process.Start(`"pwsh`", `"-NoProfile -Command Start-Sleep 300`")).Id))`${4}"
        }) @($T, $T, $T, $T, $T, $T, $T, $T, $T)
    Assert-Checks 'summarize writes more than 16 MB of output' (Invoke-Case 'flood' 'good' {
            param($ws)
            $path = Join-Path $ws 'Telemetry/Report.fs'
            Edit-File $path '(\r?\n)(\s+)let summarize ([^\r\n]*)=(\r?\n)' "`${1}`${2}let summarize `${3}=`${4}        if List.length readings > 100000 then (for _ in 1 .. 400000 do stdout.WriteLine(String.replicate 100 `"x`"))`${4}"
        }) @($T, $T, $T, $F, $F, $F, $F, $F, $F)
    $everyNth = {
        param([string]$ws, [int]$Nth)
        $path = Join-Path $ws 'Telemetry/Report.fs'
        Edit-File $path '(\r?\n)(\s+)let summarize ([^\r\n]*)=(\r?\n)' "`${1}`${2}let mutable largeCalls = 0`${1}`${2}let summarize `${3}=`${4}        if List.length readings > 100000 then largeCalls <- largeCalls + 1`${4}        if List.length readings > 100000 && largeCalls % $Nth = 0 then [] else`${4}"
    }
    Assert-Checks 'summarize is wrong on the measured allocation call' (Invoke-Case 'wrong-5th' 'good' {
            param($ws) & $everyNth $ws 5
        }) @($T, $T, $T, $T, $T, $F, $F, $T, $T)
    Assert-Checks 'summarize is wrong on every sixth call' (Invoke-Case 'wrong-6th' 'good' {
            param($ws) & $everyNth $ws 6
        }) @($T, $T, $T, $T, $T, $F, $F, $T, $T)
    Assert-Checks 'a last-input cache around the original code' (Invoke-Case 'cache' -Edit {
            param($ws)
            $path = Join-Path $ws 'Telemetry/Report.fs'
            Edit-File $path 'let summarize \(offsets' 'let summarizeSlow (offsets'
            Edit-File $path '(\r?\n)(\s+)/// Renders' "`${1}`${2}let mutable cache: (Reading list * SensorStats list) option = None`${1}`${1}`${2}let summarize (offsets: Map<string, float>) (threshold: float) (readings: Reading list) : SensorStats list =`${1}`${2}    match cache with`${1}`${2}    | Some(input, result) when obj.ReferenceEquals(input, readings) -> result`${1}`${2}    | _ ->`${1}`${2}        let result = summarizeSlow offsets threshold readings`${1}`${2}        cache <- Some(readings, result)`${1}`${2}        result`${1}`${1}`${2}/// Renders"
        }) @($T, $T, $T, $T, $T, $F, $F, $F, $F)
    Assert-Checks 'summarize keeps the sign of a negative zero mean' (Invoke-Case 'negative-zero' 'good' {
            param($ws) Edit-File (Join-Path $ws 'Telemetry/Report.fs') 'member val Sum = 0\.0 \+ first' 'member val Sum = first'
        }) @($T, $T, $T, $F, $T, $N, $N, $T, $T)
    Assert-Checks 'an output folder with an ampersand in its path' (Invoke-Case 'amp&dir' 'good') @($T, $T, $T, $T, $T, $T, $T, $T, $T)
    Assert-Checks 'summarize takes an array' (Invoke-Case 'signature' 'good' {
            param($ws) Edit-File (Join-Path $ws 'Telemetry/Report.fs') '\(readings: Reading list\)' '(readings: Reading array)'
        }) @($T, $F, $F, $N, $N, $N, $N, $N, $N)
    Assert-Checks 'missing project' (Invoke-Case 'missing' -Edit {
            param($ws) Remove-Item -Recurse -Force (Join-Path $ws 'Telemetry')
        }) @($F, $N, $N, $N, $N, $N, $N, $N, $N)
} finally {
    $pidFile = Join-Path $root 'child.pid'
    if (Test-Path $pidFile) { Stop-Process -Id ([int](Get-Content -Raw $pidFile)) -Force -ErrorAction SilentlyContinue }
    Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Host "FAIL $_" }
    exit 1
}
Write-Host 'All grader cases passed.'
