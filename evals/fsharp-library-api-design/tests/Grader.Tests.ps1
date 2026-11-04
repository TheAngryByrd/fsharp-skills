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
    'A second charge with the same key returns the first receipt and does not call the gateway'
    'A charge with a new key calls the gateway'
    'Charges without a key call the gateway each time'
    'A C# probe that passes an array, a List<ChargeRequest>, and an iterator to ChargeAll builds against the new Payments'
    'ChargeAll charges each request of a C# array'
    'ChargeAll charges each request of a List<ChargeRequest>'
    'ChargeAll charges each request of an IEnumerable<ChargeRequest> iterator'
)

function Edit-File([string]$Path, [string]$Pattern, [string]$Replacement) {
    $text = Get-Content -Raw $Path
    if ($text -notmatch $Pattern) { throw "Pattern '$Pattern' not found in $Path." }
    Set-Content $Path ($text -replace $Pattern, $Replacement) -NoNewline
}

function Invoke-Case {
    param([string]$Name, [switch]$Good, [scriptblock]$Edit)
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
    & (Join-Path $PSScriptRoot '../graders/minor-release.ps1') -Workspace $ws -OutDir $out
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

$chargeMembers = '(?s)    /// Charges the request and returns its receipt\..*?(?=    /// Charges each request in order)'

try {
    $T = $true; $F = $false; $N = $null
    Assert-Checks 'good' (Invoke-Case 'good' -Good) @($T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T)
    Assert-Checks 'original input' (Invoke-Case 'stub') @($T, $F, $F, $T, $T, $T, $T, $T, $T, $F, $N, $N, $N, $F, $N, $N, $N)
    Assert-Checks 'optional attribute on the existing Charge' (Invoke-Case 'optional-attribute' -Good -Edit {
            param($ws)
            Edit-File (Join-Path $ws 'Payments/Payments.fs') $chargeMembers @'
    /// Charges the request. A repeated idempotency key returns the first receipt.
    member _.Charge(request: ChargeRequest, [<System.Runtime.InteropServices.Optional; System.Runtime.InteropServices.DefaultParameterValue(null: string)>] idempotencyKey: string) : Receipt =
        chargeOnce request idempotencyKey


'@
        }) @($T, $T, $T, $T, $T, $F, $F, $F, $T, $T, $T, $T, $T, $T, $T, $T, $T)
    Assert-Checks 'F# optional parameter on the existing Charge' (Invoke-Case 'fsharp-optional' -Good -Edit {
            param($ws)
            Edit-File (Join-Path $ws 'Payments/Payments.fs') $chargeMembers @'
    /// Charges the request. A repeated idempotency key returns the first receipt.
    member _.Charge(request: ChargeRequest, ?idempotencyKey: string) : Receipt =
        chargeOnce request (defaultArg idempotencyKey null)


'@
        }) @($T, $T, $T, $T, $F, $F, $F, $F, $F, $F, $N, $N, $N, $T, $T, $T, $T)
    Assert-Checks 'seq parameter on the existing ChargeAll' (Invoke-Case 'seq-parameter' -Good -Edit {
            param($ws)
            Edit-File (Join-Path $ws 'Payments/Payments.fs') '(?s)    /// Charges each request in order.*$' @'
    /// Charges each request in order and returns the receipts.
    member _.ChargeAll(requests: seq<ChargeRequest>) : Receipt list = requests |> Seq.map charge |> List.ofSeq
'@
        }) @($T, $T, $T, $T, $T, $F, $F, $F, $T, $T, $T, $T, $T, $T, $T, $T, $T)
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
        }) @($T, $T, $T, $F, $F, $F, $F, $F, $F, $F, $N, $N, $N, $F, $N, $N, $N)
    Assert-Checks 'new interface member' (Invoke-Case 'interface-member' -Good -Edit {
            param($ws)
            Edit-File (Join-Path $ws 'Payments/Payments.fs') '(    abstract Submit: request: ChargeRequest \* total: decimal -> string)' "`$1`n    abstract Forget: idempotencyKey: string -> unit"
        }) @($T, $T, $T, $F, $F, $F, $F, $T, $T, $F, $N, $N, $N, $F, $N, $N, $N)
    Assert-Checks 'new dependency project' (Invoke-Case 'new-dependency' -Good -Edit {
            param($ws)
            $dep = Join-Path $ws 'PaymentsKeys'
            New-Item -ItemType Directory -Force -Path $dep | Out-Null
            Set-Content (Join-Path $dep 'PaymentsKeys.fsproj') '<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><TargetFramework>net10.0</TargetFramework></PropertyGroup><ItemGroup><Compile Include="Keys.fs" /></ItemGroup></Project>'
            Set-Content (Join-Path $dep 'Keys.fs') "module PaymentsKeys.Keys`n`nlet normalize (key: string) = key.Trim()"
            Edit-File (Join-Path $ws 'Payments/Payments.fsproj') '<Compile Include="Payments.fs" />' '<Compile Include="Payments.fs" /><ProjectReference Include="../PaymentsKeys/PaymentsKeys.fsproj" />'
            Edit-File (Join-Path $ws 'Payments/Payments.fs') 'match receipts.TryGetValue idempotencyKey with' 'match receipts.TryGetValue(PaymentsKeys.Keys.normalize idempotencyKey) with'
        }) @($T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T)
    Assert-Checks 'new constructor with an option parameter' (Invoke-Case 'option-constructor' -Good -Edit {
            param($ws)
            Edit-File (Join-Path $ws 'Payments/Payments.fs') '/// Charges customers through a gateway.' "/// Options for a charge.`ntype ChargeOptions(key: string option) =`n    member _.HasKey = key.IsSome`n`n/// Charges customers through a gateway."
        }) @($T, $T, $T, $T, $T, $T, $T, $T, $F, $T, $T, $T, $T, $T, $T, $T, $T)
    $seqOverload = '    member _.ChargeAll(requests: seq<ChargeRequest>) : Receipt list = requests |> Seq.map charge |> List.ofSeq'
    Assert-Checks 'IReadOnlyList overload only' (Invoke-Case 'readonly-list' -Good -Edit {
            param($ws)
            Edit-File (Join-Path $ws 'Payments/Payments.fs') ([regex]::Escape($seqOverload)) '    member _.ChargeAll(requests: System.Collections.Generic.IReadOnlyList<ChargeRequest>) : Receipt list = requests |> Seq.map charge |> List.ofSeq'
        }) @($T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $F, $N, $N, $N)
    Assert-Checks 'writable list property' (Invoke-Case 'writable-property' -Good -Edit {
            param($ws)
            Edit-File (Join-Path $ws 'Payments/Payments.fs') ([regex]::Escape($seqOverload)) "$seqOverload`n`n    member val LastBatch: Receipt list = [] with get, set"
        }) @($T, $T, $T, $T, $T, $T, $T, $T, $F, $T, $T, $T, $T, $T, $T, $T, $T)
    Assert-Checks 'lazy seq overload' (Invoke-Case 'lazy-seq' -Good -Edit {
            param($ws)
            Edit-File (Join-Path $ws 'Payments/Payments.fs') ([regex]::Escape($seqOverload)) '    member _.ChargeAll(requests: seq<ChargeRequest>) : seq<Receipt> = requests |> Seq.map charge'
        }) @($T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T, $T)
} finally {
    Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Host "FAIL $_" }
    exit 1
}
Write-Host 'PASS all grader cases'
