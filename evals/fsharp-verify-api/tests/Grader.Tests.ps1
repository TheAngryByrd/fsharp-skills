#Requires -Version 7.4
$ErrorActionPreference = 'Stop'

$root = Join-Path ([IO.Path]::GetTempPath()) "verify-api-grader-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
$failures = [System.Collections.Generic.List[string]]::new()

function Invoke-Case {
    param([string]$Grader, [string]$Inputs, [string]$Name, [hashtable]$Files = @{}, [scriptblock]$Edit)
    $ws = Join-Path $root "$Name/ws"
    $out = Join-Path $root "$Name/grade"
    New-Item -ItemType Directory -Force -Path $ws, $out | Out-Null
    Copy-Item (Join-Path $PSScriptRoot "../inputs/$Inputs") $ws -Recurse
    foreach ($target in $Files.Keys) { Copy-Item (Join-Path $PSScriptRoot $Files[$target]) (Join-Path $ws $target) }
    if ($Edit) { & $Edit $ws }
    & (Join-Path $PSScriptRoot "../graders/$Grader") -Workspace $ws -OutDir $out
    @(Get-Content -Raw (Join-Path $out 'grading.json') | ConvertFrom-Json)
}

function Assert-Checks {
    param([string]$Case, $Checks, [hashtable]$Expected, [switch]$Partial)
    $actual = @{}
    foreach ($c in $Checks) { $actual[$c.text] = $c.passed }
    $wrong = @($Expected.Keys | Where-Object { -not $actual.ContainsKey($_) -or $actual[$_] -ne $Expected[$_] })
    $extra = @($actual.Keys | Where-Object { -not $Partial -and -not $Expected.ContainsKey($_) })
    if ($wrong.Count -gt 0 -or $extra.Count -gt 0) {
        $detail = ($Checks | ForEach-Object { "  [$($_.passed)] $($_.text) $($_.evidence)" }) -join "`n"
        $failures.Add("${Case}: unexpected checks: $($wrong + $extra -join '; ')`n$detail")
    }
}

function New-Expected([string[]]$Names, [bool[]]$Values) {
    $h = @{}
    for ($i = 0; $i -lt $Names.Count; $i++) { $h[$Names[$i]] = $Values[$i] }
    $h
}

$cli = @(
    'Greeter.fsproj still references System.CommandLine 2.0.0'
    'The project builds'
    '`--name Bob --count 2` prints only two greetings and exits 0'
    '`--name Bob` prints only one greeting and exits 0'
    'A missing `--name` exits non-zero with an error and no greeting'
    '`--count 0` exits non-zero with an error and no greeting'
    '`--help` exits 0 and lists `--name` and `--count`'
    'An unknown option exits non-zero with a parse error'
)
$props = @(
    'OrderProps.fsx still references FsCheck 3.4.0'
    'OrderProps.fsx and the probe compile together'
    'sampleLines 300 returns 300 lines'
    'Every sampled line meets the constraints'
    'Samples use every SKU and vary quantity and price'
    'orderArb gives non-empty orders of valid lines'
    'checkTotal passes the correct total in exactly 250 valid orders'
    'checkTotal throws for a total that ignores quantity'
)
$downgrade = {
    param($ws)
    $proj = Join-Path $ws 'Greeter/Greeter.fsproj'
    (Get-Content -Raw $proj) -replace 'Version="2\.0\.0"', 'Version="2.0.0-beta4.22272.1"' | Set-Content $proj
}
$propsV2 = {
    param($ws)
    $file = Join-Path $ws 'OrderProps.fsx'
    (Get-Content -Raw $file) -replace 'FsCheck, 3\.4\.0', 'FsCheck, 2.16.6' | Set-Content $file
}

try {
    Assert-Checks 'cli good' (Invoke-Case cli-options.ps1 Greeter 'cli-good' @{ 'Greeter/Program.fs' = 'good/Program.fs' }) (New-Expected $cli (@($true) * 8))
    Assert-Checks 'cli stub' (Invoke-Case cli-options.ps1 Greeter 'cli-stub') (New-Expected $cli (@($true, $true) + @($false) * 6))
    Assert-Checks 'cli beta4' (Invoke-Case cli-options.ps1 Greeter 'cli-beta4' @{ 'Greeter/Program.fs' = 'beta4/Program.fs' }) (New-Expected $cli (@($true) + @($false) * 7))
    Assert-Checks 'cli downgrade' (Invoke-Case cli-options.ps1 Greeter 'cli-downgrade' @{ 'Greeter/Program.fs' = 'beta4/Program.fs' } $downgrade) @{ ($cli[0]) = $false; ($cli[1]) = $true } -Partial

    Assert-Checks 'cli extra output' (Invoke-Case cli-options.ps1 Greeter 'cli-extra' @{ 'Greeter/Program.fs' = 'extra-output/Program.fs' }) (New-Expected $cli (@($true, $true, $false, $false) + @($true) * 4))

    Assert-Checks 'props good' (Invoke-Case order-props.ps1 props/* 'props-good' @{ 'OrderProps.fsx' = 'props-good/OrderProps.fsx' }) (New-Expected $props (@($true) * 8))
    Assert-Checks 'props stub' (Invoke-Case order-props.ps1 props/* 'props-stub') (New-Expected $props (@($true) + @($false) * 7))
    Assert-Checks 'props v2 API' (Invoke-Case order-props.ps1 props/* 'props-v2' @{ 'OrderProps.fsx' = 'props-v2/OrderProps.fsx' }) (New-Expected $props (@($true) + @($false) * 7))
    Assert-Checks 'props downgrade' (Invoke-Case order-props.ps1 props/* 'props-downgrade' @{ 'OrderProps.fsx' = 'props-v2/OrderProps.fsx' } $propsV2) @{ ($props[0]) = $false } -Partial
    Assert-Checks 'props wrong' (Invoke-Case order-props.ps1 props/* 'props-wrong' @{ 'OrderProps.fsx' = 'props-wrong/OrderProps.fsx' }) (New-Expected $props @($true, $true, $true, $false, $false, $false, $false, $false))
    Assert-Checks 'props renamed lineGen' (Invoke-Case order-props.ps1 props/* 'props-renamed' @{ 'OrderProps.fsx' = 'props-renamed/OrderProps.fsx' }) (New-Expected $props (@($true) + @($false) * 7))
    Assert-Checks 'props bypass orderArb' (Invoke-Case order-props.ps1 props/* 'props-bypass' @{ 'OrderProps.fsx' = 'props-bypass/OrderProps.fsx' }) (New-Expected $props (@($true) * 6 + @($false, $true)))
    Assert-Checks 'props biased' (Invoke-Case order-props.ps1 props/* 'props-biased' @{ 'OrderProps.fsx' = 'props-biased/OrderProps.fsx' }) (New-Expected $props (@($true) * 8))

    $v2 = Join-Path $root 'props-downgrade/ws'
    Push-Location $v2
    try {
        $run = & dotnet fsi --nologo OrderProps.fsx 2>&1 | ForEach-Object { "$_" }
        if ($LASTEXITCODE -ne 0) { $failures.Add("props v2 control: the old API script does not load with FsCheck 2.16.6`n$($run -join "`n")") }
    } finally {
        Pop-Location
    }
} finally {
    Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Host "FAIL $_" }
    exit 1
}
Write-Host 'PASS all grader cases'
