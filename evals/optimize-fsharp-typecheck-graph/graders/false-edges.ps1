#Requires -Version 7.4
param(
    [Parameter(Mandatory)][string]$Workspace,
    [Parameter(Mandatory)][string]$OutDir,
    [switch]$SkipNative
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../../lib/Grading.psm1') -Force

function Get-Dependents([string]$GraphText, [string]$File) {
    $names = @{}
    foreach ($m in [regex]::Matches($GraphText, '(?m)^\s*(\d+)\["([^"]+)"\]')) { $names[$m.Groups[1].Value] = Split-Path $m.Groups[2].Value -Leaf }
    $target = @($names.Keys | Where-Object { $names[$_] -eq $File })
    @([regex]::Matches($GraphText, '(?m)^\s*(\d+)\s*-->\s*(\d+)') |
        Where-Object { $_.Groups[2].Value -in $target } |
        ForEach-Object { $names[$_.Groups[1].Value] } | Sort-Object -Unique)
}

$checks = @()
$shop = Join-Path $Workspace 'Shop'
$answer = Read-AnswerJson $Workspace

foreach ($name in 'graph-before.md', 'graph-after.md') {
    $path = Join-Path $Workspace $name
    $ok = (Test-Path $path) -and ((Get-Content -Raw $path) -match '-->') -and ((Get-Content -Raw $path) -match '\["Prelude\.fs"\]')
    $checks += New-Check "$name holds a compiler type-check graph" $ok ''
}
$before = Join-Path $Workspace 'graph-before.md'
if (Test-Path $before) {
    $deps = Get-Dependents (Get-Content -Raw $before) 'Prelude.fs'
    $checks += New-Check 'graph-before.md shows all six later files depending on Prelude.fs' ($deps.Count -eq 6) ($deps -join ', ')
}

$originalPricing = Get-FileHash (Join-Path $PSScriptRoot '../inputs/Shop/Pricing.fs')
$pricing = Join-Path $shop 'Pricing.fs'
$checks += New-Check 'Pricing.fs is unchanged' ((Test-Path $pricing) -and (Get-FileHash $pricing).Hash -eq $originalPricing.Hash) ''

$copy = Join-Path $OutDir 'Shop'
if (Test-Path $shop) { Copy-Workspace -Workspace $shop -Destination $copy }
$project = Join-Path $copy 'Shop.fsproj'
if (Test-Path $project) {
    $build = Invoke-Capture dotnet @('build', $project, '-c', 'Release', '-o', (Join-Path $OutDir 'bin'), '-p:OtherFlags=--test:GraphBasedChecking --test:DumpCheckingGraph') -WorkingDirectory $copy
    $checks += New-Check 'The changed project builds' ($build.ExitCode -eq 0) $(if ($build.ExitCode -ne 0) { Get-LastLines $build.Text 6 } else { '' })
    $graph = Get-ChildItem -Path $copy -Recurse -Filter '*.graph.md' | Select-Object -First 1
    if ($build.ExitCode -eq 0 -and $graph) {
        $deps = Get-Dependents (Get-Content -Raw $graph.FullName) 'Prelude.fs'
        $falseDeps = @($deps | Where-Object { $_ -in 'Customers.fs', 'Products.fs', 'Inventory.fs', 'Reports.fs' })
        $checks += New-Check 'Customers.fs, Products.fs, Inventory.fs, and Reports.fs no longer depend on Prelude.fs' ($falseDeps.Count -eq 0) ("dependents: " + ($deps -join ', '))
        $run = Invoke-Capture dotnet @((Join-Path $OutDir 'bin/Shop.dll')) -WorkingDirectory $copy
        $expected = (Get-Content (Join-Path $PSScriptRoot 'shop-expected.txt')) -join "`n"
        $actual = ($run.Lines | ForEach-Object { $_.TrimEnd() }) -join "`n"
        $checks += New-Check 'The program output is unchanged' ($actual.Trim() -eq $expected.Trim()) $actual
    } else {
        $checks += New-Check 'Customers.fs, Products.fs, Inventory.fs, and Reports.fs no longer depend on Prelude.fs' $false 'no graph produced'
        $checks += New-Check 'The program output is unchanged' $false 'build failed'
    }
} else {
    $checks += New-Check 'The changed project builds' $false 'Shop/Shop.fsproj missing'
}

$bottleneck = if ($answer -and $answer.PSObject.Properties['bottleneckFile']) { Split-Path "$($answer.bottleneckFile)" -Leaf } else { '' }
$cause = if ($answer -and $answer.PSObject.Properties['cause']) { "$($answer.cause)" } else { '' }
$checks += New-Check 'answer.json names Prelude.fs as the file that gates the others' ($bottleneck -eq 'Prelude.fs') $bottleneck
$checks += New-Check 'answer.json names AutoOpen or the global namespace as the cause' ($cause -match 'AutoOpen|global namespace|top-level module|no namespace') $cause

$speedup = if ($answer -and $answer.PSObject.Properties['buildFaster']) { "$($answer.buildFaster)".Trim().ToLowerInvariant() } else { '' }
$measured = $answer -and $answer.PSObject.Properties['measuredRuns'] -and [int]"0$($answer.measuredRuns)" -ge 3
$checks += New-Check 'answer.json claims a faster build only with three or more measured runs' ($speedup -in 'not shown', 'no' -or ($speedup -eq 'yes' -and $measured)) "buildFaster=$speedup"

Write-Checks (Join-Path $OutDir 'grading.json') $checks
