#Requires -Version 7.4
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$root = Join-Path ([IO.Path]::GetTempPath()) "signature-files-grader-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
$failures = [System.Collections.Generic.List[string]]::new()
$inputs = Join-Path $PSScriptRoot '../inputs'
$goodDir = Join-Path $PSScriptRoot 'good/Inventory'

$names = @(
    'Sku.fs, Stock.fs, and Pricing.fs each have their .fsi directly before them in the compile order'
    'Inventory builds'
    'No attribute or interface mismatch between .fsi and .fs (no FS3888 or FS0050)'
    'Shop builds and prints the same report'
    'The original Inventory.Tests build and pass'
    'The public surface equals the minimal API that Shop and the tests need'
    'The XML documentation keeps the doc comment of each public member'
    'A probe consumer that uses the public API builds and runs'
    'A probe consumer cannot build a Sku record directly'
    'A probe consumer cannot build a negative Quantity with the union case'
    'A probe consumer cannot use a StockLevel case without the type name'
    'A probe consumer cannot call the roundToCents helper'
)

function Invoke-Case {
    param([string]$Name, [switch]$Good, [scriptblock]$Edit)
    $ws = Join-Path $root "$Name/ws"
    $out = Join-Path $root "$Name/grade"
    New-Item -ItemType Directory -Force -Path $ws, $out | Out-Null
    Copy-Item (Join-Path $inputs '*') $ws -Recurse
    if ($Good) { Copy-Item (Join-Path $goodDir '*') (Join-Path $ws 'Inventory') -Force }
    if ($Edit) { & $Edit $ws }
    & (Join-Path $PSScriptRoot '../graders/minimal-surface.ps1') -Workspace $ws -OutDir $out
    @(Get-Content -Raw (Join-Path $out 'grading.json') | ConvertFrom-Json)
}

function Assert-Checks {
    param([string]$Case, $Checks, [object[]]$Values)
    $actual = @{}
    foreach ($c in $Checks) { $actual[$c.text] = $c.passed }
    $wrong = @(for ($i = 0; $i -lt $names.Count; $i++) {
            if (-not $actual.ContainsKey($names[$i]) -or $actual[$names[$i]] -ne $Values[$i]) { "$($names[$i]) expected $($Values[$i])" }
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

$allsigs = {
    param($ws)
    $lib = Join-Path $ws 'Inventory'
    Set-Content (Join-Path $ws 'global.json') (Get-Content -Raw (Join-Path $PSScriptRoot '../graders/global.json'))
    Push-Location $lib
    try { dotnet build '-p:OtherFlags=--allsigs' 2>&1 | Out-Null } finally { Pop-Location }
    Remove-Item -Recurse -Force (Join-Path $lib 'bin'), (Join-Path $lib 'obj')
    Edit-File (Join-Path $lib 'Inventory.fsproj') '<Compile Include="(\w+)\.fs" />' '<Compile Include="$1.fsi" /><Compile Include="$1.fs" />'
    Edit-File (Join-Path $lib 'Inventory.fsproj') '<ItemGroup>' "<ItemGroup><InternalsVisibleTo Include=`"Inventory.Tests`" /></ItemGroup><ItemGroup>"
}

try {
    $T = $true; $F = $false; $N = $null
    Assert-Checks 'good' (Invoke-Case 'good' -Good) @($T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T)
    Assert-Checks 'original input' (Invoke-Case 'stub') @($F, $T, $T, $T, $T, $F, $T, $T, $F, $F, $T, $F)
    Assert-Checks 'raw --allsigs output' (Invoke-Case 'allsigs' -Edit $allsigs) @($T, $T, $T, $T, $T, $F, $T, $T, $F, $F, $T, $F)
    Assert-Checks 'test-only helper public' (Invoke-Case 'public-helper' -Good -Edit {
            param($ws) Edit-File (Join-Path $ws 'Inventory/Pricing.fsi') 'val internal roundToCents' 'val roundToCents'
        }) @($T, $T, $T, $T, $T, $F, $T, $T, $T, $T, $T, $F)
    Assert-Checks '.fsi after .fs' (Invoke-Case 'order' -Good -Edit {
            param($ws) Edit-File (Join-Path $ws 'Inventory/Inventory.fsproj') '(<Compile Include="Pricing.fsi" />)(\s*)(<Compile Include="Pricing.fs" />)' '$3$2$1'
        }) @($F, $F, $N, $F, $F, $N, $N, $F, $N, $N, $N, $N)
    Assert-Checks 'docs only in .fs' (Invoke-Case 'docs' -Good -Edit {
            param($ws) foreach ($f in Get-ChildItem (Join-Path $ws 'Inventory') -Filter *.fsi) { Edit-File $f.FullName '(?m)^\s*///.*\r?\n' '' }
        }) @($T, $T, $T, $T, $T, $T, $F, $T, $T, $T, $T, $T)
    Assert-Checks 'RequireQualifiedAccess missing in .fsi' (Invoke-Case 'rqa' -Good -Edit {
            param($ws) Edit-File (Join-Path $ws 'Inventory/Stock.fsi') '\[<RequireQualifiedAccess>\]\r?\n' ''
        }) @($T, $T, $F, $T, $T, $T, $T, $T, $T, $T, $F, $T)
    Assert-Checks 'Sku representation public' (Invoke-Case 'public-sku' -Good -Edit {
            param($ws) Edit-File (Join-Path $ws 'Inventory/Sku.fsi') '(?m)^type Sku\s*$' 'type Sku = { Code: string }'
        }) @($T, $T, $T, $T, $T, $F, $T, $T, $F, $T, $T, $T)
    Assert-Checks 'interface not listed in .fsi' (Invoke-Case 'iface' -Good -Edit {
            param($ws) Edit-File (Join-Path $ws 'Inventory/Stock.fsi') '(?m)^\s*interface System\.IDisposable\s*\r?\n' ''
        }) @($T, $T, $F, $F, $T, $T, $T, $F, $N, $N, $N, $N)
    Assert-Checks 'private representation with an extra AssemblyInfo.fs' (Invoke-Case 'private-repr' -Good -Edit {
            param($ws)
            $lib = Join-Path $ws 'Inventory'
            Edit-File (Join-Path $lib 'Sku.fsi') '(?m)^type Sku\s*$' 'type Sku = private { Code: string }'
            Edit-File (Join-Path $lib 'Sku.fs') 'type Sku = \{ Code: string \}' 'type Sku = private { Code: string }'
            Edit-File (Join-Path $lib 'Sku.fsi') '(?m)^type Quantity\s*$' 'type Quantity = private Quantity of int'
            Edit-File (Join-Path $lib 'Sku.fs') 'type Quantity = Quantity of int' 'type Quantity = private Quantity of int'
            Set-Content (Join-Path $lib 'AssemblyInfo.fs') "module internal AssemblyInfo`n`n[<assembly: System.Runtime.CompilerServices.InternalsVisibleTo(`"Inventory.Tests`")>]`ndo ()"
            Edit-File (Join-Path $lib 'Inventory.fsproj') '<InternalsVisibleTo Include="Inventory.Tests" />' ''
            Edit-File (Join-Path $lib 'Inventory.fsproj') '<Compile Include="Pricing.fs" />' '<Compile Include="Pricing.fs" /><Compile Include="AssemblyInfo.fs" />'
        }) @($T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T)
    Assert-Checks 'StockItem constructor hidden' (Invoke-Case 'stockitem' -Good -Edit {
            param($ws)
            Edit-File (Join-Path $ws 'Inventory/Stock.fsi') 'type StockItem = \{ Sku: Sku; OnHand: Quantity \}' "[<Sealed>]`ntype StockItem =`n    member Sku: Sku`n    member OnHand: Quantity"
            Edit-File (Join-Path $ws 'Inventory/Stock.fs') 'type StockItem = \{ Sku: Sku; OnHand: Quantity \}' "[<Sealed>]`ntype StockItem internal (sku: Sku, onHand: Quantity) =`n    member _.Sku = sku`n    member _.OnHand = onHand"
            Edit-File (Join-Path $ws 'Inventory/Stock.fs') 'Ok \{ Sku = sku; OnHand = onHand \}' 'Ok(StockItem(sku, onHand))'
        }) @($T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T)
    Assert-Checks 'Shop replaced with fixed output' (Invoke-Case 'shop-edit' -Edit {
            param($ws)
            $lines = Get-Content (Join-Path $PSScriptRoot '../graders/shop-expected.txt') | Where-Object { $_ } | ForEach-Object { "    printfn `"%s`" `"$($_.Replace('"', '\"'))`"" }
            Set-Content (Join-Path $ws 'Shop/Program.fs') (@('[<EntryPoint>]', 'let main _ =') + $lines + '    0')
            Edit-File (Join-Path $ws 'Inventory/Stock.fs') 'let lowThreshold = 5' 'let lowThreshold = 2'
        }) @($F, $T, $T, $F, $F, $F, $T, $T, $F, $F, $T, $F)
} finally {
    Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Host "FAIL $_" }
    exit 1
}
Write-Host 'PASS all grader cases'
