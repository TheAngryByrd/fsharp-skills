#Requires -Version 7.4
param(
    [Parameter(Mandatory)][string]$Workspace,
    [Parameter(Mandatory)][string]$OutDir,
    [switch]$SkipNative
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../../lib/Grading.psm1') -Force

$globalJson = Get-Content -Raw (Join-Path $PSScriptRoot 'global.json')
$surfaceScript = Join-Path $PSScriptRoot '../../../skills/fsharp-signature-files/scripts/public-surface.ps1'
$inputs = Join-Path $PSScriptRoot '../inputs'

$checks = @()
$copy = Join-Path $OutDir 'ws'
Copy-Workspace $Workspace $copy
if (-not (Test-Path (Join-Path $copy 'global.json'))) { Set-Content (Join-Path $copy 'global.json') $globalJson }
$project = Join-Path $copy 'Inventory/Inventory.fsproj'
if (-not (Test-Path $project)) {
    $checks += New-Check 'Inventory/Inventory.fsproj exists' $false 'missing'
    Write-Checks (Join-Path $OutDir 'grading.json') $checks
    return
}
$tests = Join-Path $copy 'Inventory.Tests'
foreach ($name in 'Inventory.Tests', 'Shop') {
    $target = Join-Path $copy $name
    if (Test-Path $target) { Remove-Item -Recurse -Force $target }
    Copy-Item (Join-Path $inputs $name) $target -Recurse
}

function ConvertTo-NormalizedSurface([string[]]$Lines) {
    $Lines |
        Where-Object { $_ -notmatch '\| (CompareTo|Equals|GetHashCode|ToString)\(' -and $_ -notmatch '\| implements System\.(Collections\.)?I(Comparable|Equatable|Structural)' } |
        ForEach-Object { [regex]::Replace($_, '\(([^)]*)\)', { param($m) '(' + ($m.Groups[1].Value -replace '\b\w+: ', '') + ')' }) } |
        Sort-Object -Unique -CaseSensitive
}

$items = Invoke-Capture dotnet @('msbuild', $project, '-getItem:Compile') -WorkingDirectory (Split-Path $project)
$compile = @()
if ($items.ExitCode -eq 0) { $compile = @(($items.Text | ConvertFrom-Json).Items.Compile | ForEach-Object { $_.Identity -replace '\\', '/' }) }
$unpaired = @(foreach ($source in 'Sku.fs', 'Stock.fs', 'Pricing.fs') {
        $i = [array]::IndexOf($compile, $source)
        if ($i -lt 1 -or $compile[$i - 1] -ne ($source -replace '\.fs$', '.fsi')) { $source }
    })
$checks += New-Check 'Sku.fs, Stock.fs, and Pricing.fs each have their .fsi directly before them in the compile order' ($compile.Count -gt 0 -and $unpaired.Count -eq 0) "Compile: $($compile -join ', ')"

$build = Invoke-Capture dotnet @('build', $project, '-c', 'Release', '--no-incremental') -WorkingDirectory (Split-Path $project)
$built = $build.ExitCode -eq 0
$checks += New-Check 'Inventory builds' $built $(if (-not $built) { Get-LastLines (($build.Lines | Where-Object { $_ -match ' error ' } | Sort-Object -Unique) -join "`n") })
$mismatch = @($build.Lines | Where-Object { $_ -match 'warning (FS3888|FS0050)' } | ForEach-Object { $_ -replace '\s*\[.*$', '' } | Sort-Object -Unique)
$checks += New-Check 'No attribute or interface mismatch between .fsi and .fs (no FS3888 or FS0050)' $(if ($built) { $mismatch.Count -eq 0 } else { $null }) ($mismatch -join "`n")

$shop = Invoke-Capture dotnet @('run', '-c', 'Release') -WorkingDirectory (Join-Path $copy 'Shop')
$expectedShop = @(Get-Content (Join-Path $PSScriptRoot 'shop-expected.txt') | Where-Object { $_ })
$shopLines = @($shop.Lines | Where-Object { $_ -notmatch ': (warning|error) ' -and $_.Trim() } | ForEach-Object { $_.TrimEnd() })
$checks += New-Check 'Shop builds and prints the same report' ($shop.ExitCode -eq 0 -and ($shopLines -join "`n") -ceq ($expectedShop -join "`n")) (Get-LastLines $shop.Text)

$test = Invoke-Capture dotnet @('run', '-c', 'Release') -WorkingDirectory $tests
$checks += New-Check 'The original Inventory.Tests build and pass' ($test.ExitCode -eq 0 -and @($test.Lines | Where-Object { $_ -match '^PASS ' }).Count -eq 9) (Get-LastLines $test.Text)

$dll = Join-Path $copy 'Inventory/bin/Release/net10.0/Inventory.dll'
if ($built -and (Test-Path $dll)) {
    $surface = @(& $surfaceScript -Assembly $dll)
    $actual = @(ConvertTo-NormalizedSurface $surface)
    $expected = @(Get-Content (Join-Path $PSScriptRoot 'minimal-surface-expected.txt') | Where-Object { $_ })
    $extra = @($actual | Where-Object { $expected -cnotcontains $_ })
    $missing = @($expected | Where-Object { $actual -cnotcontains $_ })
    $evidence = @($extra | ForEach-Object { "extra: $_" }) + @($missing | ForEach-Object { "missing: $_" })
    $checks += New-Check 'The public surface equals the minimal API that Shop and the tests need' ($LASTEXITCODE -eq 0 -and $evidence.Count -eq 0) ($evidence -join "`n")

    $xmlPath = Join-Path $copy 'Inventory/bin/Release/net10.0/Inventory.xml'
    $docs = @{}
    if (Test-Path $xmlPath) {
        foreach ($m in ([xml](Get-Content -Raw $xmlPath)).doc.members.member) { $docs[$m.name] = "$($m.summary)".Trim() }
    }
    $wanted = @(Get-Content (Join-Path $PSScriptRoot 'minimal-surface-docs.txt') | Where-Object { $_ })
    $undocumented = @($wanted | Where-Object { -not $docs[$_] })
    $checks += New-Check 'The XML documentation keeps the doc comment of each public member' ($undocumented.Count -eq 0) $(if ($undocumented) { "no summary: $($undocumented -join ', ')" })
} else {
    $checks += New-Check 'The public surface equals the minimal API that Shop and the tests need' $null 'skipped: Inventory did not build'
    $checks += New-Check 'The XML documentation keeps the doc comment of each public member' $null 'skipped: Inventory did not build'
}

function Invoke-Probe([string]$Name, [string]$Source) {
    $dir = Join-Path $OutDir "probes/$Name"
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Set-Content (Join-Path $dir 'global.json') $globalJson
    Set-Content (Join-Path $dir 'Probe.fs') $Source
    Set-Content (Join-Path $dir 'Probe.fsproj') @"
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net10.0</TargetFramework>
  </PropertyGroup>
  <ItemGroup>
    <Compile Include="Probe.fs" />
    <ProjectReference Include="$((Resolve-Path $project).Path)" />
  </ItemGroup>
</Project>
"@
    $r = Invoke-Capture dotnet @('build', 'Probe.fsproj', '-c', 'Release', '-o', 'out') -WorkingDirectory $dir
    $flat = $r.Text -replace '\s*\r?\n\s*', ' '
    $probeErrors = @([regex]::Matches($flat, 'Probe\.fs\(\d+,\d+\): error FS\d+:[^\[]*') | ForEach-Object { $_.Value.Trim() } | Sort-Object -Unique)
    $run = if ($r.ExitCode -eq 0) { Invoke-Capture dotnet @('out/Probe.dll') -WorkingDirectory $dir } else { $null }
    [pscustomobject]@{ Built = $r.ExitCode -eq 0; Errors = $probeErrors; Text = $r.Text; Run = $run }
}

$control = Invoke-Probe 'control' @'
open Inventory

match Sku.tryParse "abc-1234", Quantity.tryCreate 2 with
| Some sku, Some units ->
    let item: StockItem = { Sku = sku; OnHand = units }
    use ledger = new StockLedger()
    ledger.Receive(item.Sku, item.OnHand)
    let level = Stock.classify (ledger.OnHand sku)
    printfn "control %s %d %b %M" (Sku.value sku) (Quantity.value item.OnHand) (level = StockLevel.Low) (Pricing.lineTotal 1.5m units)
| _ -> printfn "control failed"
'@
$controlOk = $control.Built -and $control.Run -and ($control.Run.Lines -join "`n").Trim() -ceq 'control ABC-1234 2 true 3.0'
$checks += New-Check 'A probe consumer that uses the public API builds and runs' $controlOk $(if (-not $control.Built) { Get-LastLines (($control.Errors + @($control.Text)) -join "`n") } elseif ($control.Run) { $control.Run.Text })

$mustFail = [ordered]@{
    'A probe consumer cannot build a Sku record directly' = "open Inventory`nlet sku: Sku = { Code = `"not-a-sku`" }`nprintfn `"%A`" sku"
    'A probe consumer cannot build a negative Quantity with the union case' = "open Inventory`nlet units: Quantity = Quantity -1`nprintfn `"%A`" units"
    'A probe consumer cannot use a StockLevel case without the type name' = "open Inventory`nlet level = Low`nprintfn `"%A`" level"
    'A probe consumer cannot call the roundToCents helper' = "open Inventory`nprintfn `"%M`" (Pricing.roundToCents 2.125m)"
}
$i = 0
foreach ($text in $mustFail.Keys) {
    $i++
    if (-not $controlOk) { $checks += New-Check $text $null 'skipped: the control probe did not build and run'; continue }
    $p = Invoke-Probe "fail$i" $mustFail[$text]
    $checks += New-Check $text (-not $p.Built -and $p.Errors.Count -gt 0) $(if ($p.Built) { 'the probe compiled' } else { $p.Errors -join "`n" })
}

Write-Checks (Join-Path $OutDir 'grading.json') $checks
