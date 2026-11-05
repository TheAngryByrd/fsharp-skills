#Requires -Version 7.4
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$root = Join-Path ([IO.Path]::GetTempPath()) "library-api-design-grader-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
$failures = [System.Collections.Generic.List[string]]::new()
$inputs = Join-Path $PSScriptRoot '../inputs'
$goodSource = Join-Path $PSScriptRoot 'good/Payments/Payments.fs'

$names = @(
    'Payments builds'
    'The Payments version is 1.1.0'
    'RELEASE_NOTES.md has a 1.1.0 entry'
    'The 1.0.0 source of Checkout builds against the new Payments and prints the same output'
    'The 1.0.0 source of CheckoutCs builds against the new Payments and prints the same output'
    'Checkout compiled against 1.0.0 runs with the new Payments.dll and prints the same output'
    'CheckoutCs compiled against 1.0.0 runs with the new Payments.dll and prints the same output'
    'No public member of 1.0.0 is removed or changed'
    'New public members take no F#-only parameter types (option, list, function, Async, Map, Set) and return no option, function, or Async'
    'A C# probe that calls client.Charge(request, "order-42") and client.Charge(request) builds against the new Payments'
    'A second charge with the same key and a different request returns the first receipt and does not call the gateway'
    'A charge with a new key calls the gateway'
    'A charge with the first key after a different key returns the first receipt and does not call the gateway'
    'Charges without a key call the gateway each time'
    'A C# probe that passes an array, a List<ChargeRequest>, and an iterator to ChargeAll builds against the new Payments'
    'ChargeAll charges each request of a C# array once, in order, when it is called'
    'ChargeAll charges each request of a List<ChargeRequest> once, in order, when it is called'
    'ChargeAll charges each request of an IEnumerable<ChargeRequest> iterator once, in order, when it is called'
)

function Edit-File([string]$Path, [string]$Pattern, [string]$Replacement) {
    $text = Get-Content -Raw $Path
    if ($text -notmatch $Pattern) { throw "Pattern '$Pattern' not found in $Path." }
    Set-Content $Path ($text -replace $Pattern, $Replacement) -NoNewline
}

function Invoke-Case {
    param([string]$Name, [switch]$Good, [scriptblock]$Edit, [hashtable]$GraderArgs = @{})
    $ws = Join-Path $root "$Name/ws"
    $out = Join-Path $root "$Name/grade"
    New-Item -ItemType Directory -Force -Path $ws, $out | Out-Null
    Copy-Item (Join-Path $inputs '*') $ws -Recurse
    if ($Good) {
        $lib = Join-Path $ws 'Payments'
        Copy-Item $goodSource $lib -Force
        Edit-File (Join-Path $lib 'Payments.fsproj') '<Version>1\.0\.0</Version>' '<Version>1.1.0</Version>'
        Add-Content (Join-Path $lib 'RELEASE_NOTES.md') "`n## 1.1.0`n`n- Add ``PaymentClient.Charge(request, idempotencyKey)`` and ``PaymentClient.ChargeAll(seq)``."
    }
    if ($Edit) { & $Edit $ws }
    & (Join-Path $PSScriptRoot '../graders/minor-release.ps1') -Workspace $ws -OutDir $out @GraderArgs
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

function Test-Dependencies {
    $dir = Join-Path $root 'dependencies'
    $deps = {
        param([string]$Folder, [string]$Version)
        New-Item -ItemType Directory -Force -Path $Folder | Out-Null
        Set-Content (Join-Path $Folder 'FSharp.Core.dll') 'not an assembly'
        $id = "FSharp.Core/$Version"
        @{ targets = @{ '.NETCoreApp,Version=v10.0' = @{ $id = @{ runtime = @{ 'lib/netstandard2.1/FSharp.Core.dll' = @{ assemblyVersion = '10.0.0.0' } } } } }
            libraries = @{ $id = @{ type = 'package' } } } | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $Folder 'app.deps.json')
        Get-PackageVersions (Join-Path $Folder 'app.deps.json')
    }
    Import-Module (Join-Path $PSScriptRoot '../../lib/Grading.psm1') -Force
    Import-Module (Join-Path $PSScriptRoot '../graders/Dependencies.psm1') -Force
    $cases = @(
        @{ Name = 'a package upgrade with the same assembly version replaces the old DLL'; Old = '10.0.113'; New = '10.0.114'; Copy = $true }
        @{ Name = 'a package downgrade with the same assembly version keeps the old DLL'; Old = '10.0.114'; New = '10.0.113'; Copy = $false }
        @{ Name = 'a prerelease of a newer version replaces the old DLL'; Old = '10.1.403'; New = '11.0.101-rc3.26522.148'; Copy = $true }
        @{ Name = 'a prerelease of the same version keeps the old release DLL'; Old = '11.0.101'; New = '11.0.101-rc3.26522.148'; Copy = $false }
    )
    for ($i = 0; $i -lt $cases.Count; $i++) {
        $case = $cases[$i]
        $old = & $deps (Join-Path $dir "$i/old") $case.Old
        $new = & $deps (Join-Path $dir "$i/new") $case.New
        $copy = Test-NewerDependency -NewDll (Join-Path $dir "$i/new/FSharp.Core.dll") -OldDll (Join-Path $dir "$i/old/FSharp.Core.dll") -NewPackages $new -OldPackages $old
        if ($copy -ne $case.Copy) { $failures.Add("dependencies: $($case.Name): expected copy $($case.Copy), got $copy") } else { Write-Host "ok $($case.Name)" }
    }

    $project = Join-Path $dir 'Versioned'
    New-Item -ItemType Directory -Force -Path $project | Out-Null
    Set-Content (Join-Path $project 'global.json') (Get-Content -Raw (Join-Path $PSScriptRoot '../graders/global.json'))
    Set-Content (Join-Path $project 'Versioned.csproj') '<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><TargetFramework>net10.0</TargetFramework></PropertyGroup></Project>'
    $builds = @{ old = @('1.0.0.0', '1.0.0.1'); fileUpgrade = @('1.0.0.0', '1.0.0.2'); assemblyUpgrade = @('2.0.0.0', '1.0.0.0') }
    foreach ($key in $builds.Keys) {
        $r = Invoke-Capture dotnet @('build', '-c', 'Release', '-o', (Join-Path $dir "versioned-$key"), "-p:AssemblyVersion=$($builds[$key][0])", "-p:FileVersion=$($builds[$key][1])") -WorkingDirectory $project
        if ($r.ExitCode -ne 0) { throw "The versioned test library did not build.`n$($r.Text)" }
    }
    $dll = { param([string]$Key) Join-Path $dir "versioned-$Key/Versioned.dll" }
    $fallback = @(
        @{ Name = 'with no package entry, a higher file version with the same assembly version replaces the old DLL'; New = 'fileUpgrade'; Old = 'old'; Copy = $true }
        @{ Name = 'with no package entry, a lower file version with the same assembly version keeps the old DLL'; New = 'old'; Old = 'fileUpgrade'; Copy = $false }
        @{ Name = 'with no package entry, a higher assembly version replaces the old DLL'; New = 'assemblyUpgrade'; Old = 'fileUpgrade'; Copy = $true }
        @{ Name = 'with no package entry, a lower assembly version keeps the old DLL'; New = 'fileUpgrade'; Old = 'assemblyUpgrade'; Copy = $false }
    )
    foreach ($case in $fallback) {
        $copy = Test-NewerDependency -NewDll (& $dll $case.New) -OldDll (& $dll $case.Old)
        if ($copy -ne $case.Copy) { $failures.Add("dependencies: $($case.Name): expected copy $($case.Copy), got $copy") } else { Write-Host "ok $($case.Name)" }
    }
}

$chargeMembers = '(?s)    /// Charges the request and returns its receipt\..*?(?=    /// Charges each request in order)'

try {
    $T = $true; $F = $false; $N = $null
    Test-Dependencies
    Assert-Checks 'good' (Invoke-Case 'good' -Good) @($T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T)
    Assert-Checks 'original input' (Invoke-Case 'stub') @($T, $F, $F, $T, $T, $T, $T, $T, $T, $F, $N, $N, $N, $N, $F, $N, $N, $N)
    Assert-Checks 'optional attribute on the existing Charge' (Invoke-Case 'optional-attribute' -Good -Edit {
            param($ws)
            Edit-File (Join-Path $ws 'Payments/Payments.fs') $chargeMembers @'
    /// Charges the request. A repeated idempotency key returns the first receipt.
    member _.Charge(request: ChargeRequest, [<System.Runtime.InteropServices.Optional; System.Runtime.InteropServices.DefaultParameterValue(null: string)>] idempotencyKey: string) : Receipt =
        chargeOnce request idempotencyKey


'@
        }) @($T, $T, $T, $T, $T, $F, $F, $F, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T)
    Assert-Checks 'F# optional parameter on the existing Charge' (Invoke-Case 'fsharp-optional' -Good -Edit {
            param($ws)
            Edit-File (Join-Path $ws 'Payments/Payments.fs') $chargeMembers @'
    /// Charges the request. A repeated idempotency key returns the first receipt.
    member _.Charge(request: ChargeRequest, ?idempotencyKey: string) : Receipt =
        chargeOnce request (defaultArg idempotencyKey null)


'@
        }) @($T, $T, $T, $T, $F, $F, $F, $F, $F, $F, $N, $N, $N, $N, $T, $T, $T, $T)
    Assert-Checks 'seq parameter on the existing ChargeAll' (Invoke-Case 'seq-parameter' -Good -Edit {
            param($ws)
            Edit-File (Join-Path $ws 'Payments/Payments.fs') '(?s)    /// Charges each request in order.*$' @'
    /// Charges each request in order and returns the receipts.
    member _.ChargeAll(requests: seq<ChargeRequest>) : Receipt list = requests |> Seq.map charge |> List.ofSeq
'@
        }) @($T, $T, $T, $T, $T, $F, $F, $F, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T)
    Assert-Checks 'new record field' (Invoke-Case 'record-field' -Good -Edit {
            param($ws)
            $source = Join-Path $ws 'Payments/Payments.fs'
            Edit-File $source '      Method: PaymentMethod \}' "      Method: PaymentMethod`n      IdempotencyKey: string option }"
            Edit-File $source $chargeMembers @'
    /// Charges the request. A repeated idempotency key returns the first receipt.
    member _.Charge(request: ChargeRequest) : Receipt =
        match request.IdempotencyKey with
        | Some key -> chargeOnce request key
        | None -> charge request


'@
        }) @($T, $T, $T, $F, $F, $F, $F, $F, $F, $F, $N, $N, $N, $N, $F, $N, $N, $N)
    Assert-Checks 'new interface member' (Invoke-Case 'interface-member' -Good -Edit {
            param($ws)
            Edit-File (Join-Path $ws 'Payments/Payments.fs') '(    abstract Submit: request: ChargeRequest \* total: decimal -> string)' "`$1`n    abstract Forget: idempotencyKey: string -> unit"
        }) @($T, $T, $T, $F, $F, $F, $F, $T, $T, $F, $N, $N, $N, $N, $F, $N, $N, $N)
    Assert-Checks 'new dependency project' (Invoke-Case 'new-dependency' -Good -Edit {
            param($ws)
            $dep = Join-Path $ws 'PaymentsKeys'
            New-Item -ItemType Directory -Force -Path $dep | Out-Null
            Set-Content (Join-Path $dep 'PaymentsKeys.fsproj') '<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><TargetFramework>net10.0</TargetFramework></PropertyGroup><ItemGroup><Compile Include="Keys.fs" /></ItemGroup></Project>'
            Set-Content (Join-Path $dep 'Keys.fs') "module PaymentsKeys.Keys`n`nlet normalize (key: string) = key.Trim()"
            Edit-File (Join-Path $ws 'Payments/Payments.fsproj') '<Compile Include="Payments.fs" />' '<Compile Include="Payments.fs" /><ProjectReference Include="../PaymentsKeys/PaymentsKeys.fsproj" />'
            Edit-File (Join-Path $ws 'Payments/Payments.fs') 'match receipts.TryGetValue idempotencyKey with' 'match receipts.TryGetValue(PaymentsKeys.Keys.normalize idempotencyKey) with'
        }) @($T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T)
    Assert-Checks 'new constructor with an option parameter' (Invoke-Case 'option-constructor' -Good -Edit {
            param($ws)
            Edit-File (Join-Path $ws 'Payments/Payments.fs') '/// Charges customers through a gateway.' "/// Options for a charge.`ntype ChargeOptions(key: string option) =`n    member _.HasKey = key.IsSome`n`n/// Charges customers through a gateway."
        }) @($T, $T, $T, $T, $T, $T, $T, $T, $F, $T, $T, $T, $T, $T, $T, $T, $T, $T)
    Assert-Checks 'idempotency cache that keeps only the last key' (Invoke-Case 'single-slot-cache' -Good -Edit {
            param($ws)
            Edit-File (Join-Path $ws 'Payments/Payments.fs') 'receipts\[idempotencyKey\] <- receipt' 'receipts.Clear(); receipts[idempotencyKey] <- receipt'
        }) @($T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $F, $T, $T, $T, $T, $T)
    Assert-Checks 'idempotency cache keyed by the key and the request' (Invoke-Case 'key-and-request-cache' -Good -Edit {
            param($ws)
            $file = Join-Path $ws 'Payments/Payments.fs'
            Edit-File $file 'receipts\.TryGetValue idempotencyKey' 'receipts.TryGetValue(idempotencyKey + string request.Amount)'
            Edit-File $file 'receipts\[idempotencyKey\] <- receipt' 'receipts[idempotencyKey + string request.Amount] <- receipt'
        }) @($T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $F, $T, $T, $T, $T, $T, $T, $T)
    Assert-Checks 'client that rejects a reused key with a different request' (Invoke-Case 'reject-changed-request' -Good -Edit {
            param($ws)
            Edit-File (Join-Path $ws 'Payments/Payments.fs') '\| true, receipt -> receipt' '| true, receipt -> if receipt.Amount <> request.Amount then invalidOp "The key was used for a different request." else receipt'
        }) @($T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $F, $T, $T, $T, $T, $T, $T, $T)
    $blocked = Invoke-Case 'blocking-constructor' -Good -GraderArgs @{ RunTimeoutSeconds = 45 } -Edit {
            param($ws)
            Edit-File (Join-Path $ws 'Payments/Payments.fs') '(    let receipts = .*)' "`$1`n    do System.Threading.Thread.Sleep System.Threading.Timeout.Infinite"
        }
    Assert-Checks 'constructor that never returns' $blocked @($T, $T, $T, $F, $F, $F, $F, $T, $T, $T, $F, $F, $F, $F, $T, $F, $F, $F)
    foreach ($i in 3, 5, 10, 15) {
        $evidence = ($blocked | Where-Object text -eq $names[$i]).evidence
        if ($evidence -notmatch 'timed out after 45 seconds') { $failures.Add("constructor that never returns: $($names[$i]) does not report the time limit.`n$evidence") }
    }
    $seqOverload = '    member _.ChargeAll(requests: seq<ChargeRequest>) : Receipt list = requests |> Seq.map charge |> List.ofSeq'
    Assert-Checks 'IReadOnlyList overload only' (Invoke-Case 'readonly-list' -Good -Edit {
            param($ws)
            Edit-File (Join-Path $ws 'Payments/Payments.fs') ([regex]::Escape($seqOverload)) '    member _.ChargeAll(requests: System.Collections.Generic.IReadOnlyList<ChargeRequest>) : Receipt list = requests |> Seq.map charge |> List.ofSeq'
        }) @($T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $F, $N, $N, $N)
    Assert-Checks 'writable list property' (Invoke-Case 'writable-property' -Good -Edit {
            param($ws)
            Edit-File (Join-Path $ws 'Payments/Payments.fs') ([regex]::Escape($seqOverload)) "$seqOverload`n`n    member val LastBatch: Receipt list = [] with get, set"
        }) @($T, $T, $T, $T, $T, $T, $T, $T, $F, $T, $T, $T, $T, $T, $T, $T, $T, $T)
    Assert-Checks 'lazy seq overload' (Invoke-Case 'lazy-seq' -Good -Edit {
            param($ws)
            Edit-File (Join-Path $ws 'Payments/Payments.fs') ([regex]::Escape($seqOverload)) '    member _.ChargeAll(requests: seq<ChargeRequest>) : seq<Receipt> = requests |> Seq.map charge'
        }) @($T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $F, $F, $F)
    Assert-Checks 'seq overload that repeats the first request' (Invoke-Case 'first-request' -Good -Edit {
            param($ws)
            Edit-File (Join-Path $ws 'Payments/Payments.fs') ([regex]::Escape($seqOverload)) '    member _.ChargeAll(requests: seq<ChargeRequest>) : Receipt list = let all = List.ofSeq requests in all |> List.map (fun _ -> charge all.Head)'
        }) @($T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $F, $F, $F)
    Assert-Checks 'seq overload without the fee' (Invoke-Case 'seq-no-fee' -Good -Edit {
            param($ws)
            Edit-File (Join-Path $ws 'Payments/Payments.fs') ([regex]::Escape($seqOverload)) '    member _.ChargeAll(requests: seq<ChargeRequest>) : Receipt list = requests |> Seq.map (fun r -> { charge r with Fee = 0m; Total = r.Amount }) |> List.ofSeq'
        }) @($T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $F, $F, $F)
    Assert-Checks 'indexer that returns option' (Invoke-Case 'option-indexer' -Good -Edit {
            param($ws)
            Edit-File (Join-Path $ws 'Payments/Payments.fs') ([regex]::Escape($seqOverload)) "$seqOverload`n`n    member _.Item with get (idempotencyKey: string) : Receipt option = None"
        }) @($T, $T, $T, $T, $T, $T, $T, $T, $F, $T, $T, $T, $T, $T, $T, $T, $T, $T)
    $renamed = Invoke-Case 'renamed-field-indexer' -Good -Edit {
            param($ws)
            $file = Join-Path $ws 'Payments/Payments.fs'
            Edit-File $file '\| Card of last4: string' '| Card of lastFour: string'
            Edit-File $file ([regex]::Escape($seqOverload)) "$seqOverload`n`n    member _.Item with get (idempotencyKey: string) : Receipt = receipts[idempotencyKey]"
        }
    Assert-Checks 'renamed union field and an indexer that returns Receipt' $renamed @($T, $T, $T, $T, $T, $F, $T, $F, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T)
    $removedEvidence = ($renamed | Where-Object text -eq $names[7]).evidence
    if ($removedEvidence -notmatch 'Card \| last4 : System\.String with get') { $failures.Add("renamed union field: the removed last4 getter is not reported.`n$removedEvidence") }
    Assert-Checks 'CLIMutable receipt' (Invoke-Case 'climutable-receipt' -Good -Edit {
            param($ws)
            Edit-File (Join-Path $ws 'Payments/Payments.fs') '/// The result of a successful charge\.' "/// The result of a successful charge.`n[<CLIMutable>]"
        }) @($T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T)
    $pinCore = { param($ws, $version) Edit-File (Join-Path $ws 'Payments/Payments.fsproj') '<Compile Include="Payments.fs" />' "<Compile Include=`"Payments.fs`" /><PackageReference Update=`"FSharp.Core`" Version=`"$version`" />" }
    Assert-Checks 'newer FSharp.Core' (Invoke-Case 'newer-core' -Good -Edit { param($ws) & $pinCore $ws '11.0.101-rc3.26522.148' }) @($T, $T, $T, $F, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T)
    Assert-Checks 'older FSharp.Core' (Invoke-Case 'older-core' -Good -Edit { param($ws) & $pinCore $ws '6.0.7' }) @($T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T)
} finally {
    Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Host "FAIL $_" }
    exit 1
}
Write-Host 'PASS all grader cases'
