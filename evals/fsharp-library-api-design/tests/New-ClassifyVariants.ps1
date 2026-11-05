#Requires -Version 7.4
param([Parameter(Mandatory)][string]$Destination)
$ErrorActionPreference = 'Stop'

$base = Get-Content -Raw (Join-Path $PSScriptRoot '../inputs/Payments/Payments.fs')
$base = $base.Replace("`r`n", "`n")

function Set-Variant([string]$Id, [string[]]$Pairs) {
    $text = $base
    for ($i = 0; $i -lt $Pairs.Count; $i += 2) {
        if (-not $text.Contains($Pairs[$i])) { throw "${Id}: text not found: $($Pairs[$i])" }
        $text = $text.Replace($Pairs[$i], $Pairs[$i + 1])
    }
    $dir = Join-Path $Destination $Id
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Set-Content (Join-Path $dir 'Payments.fs') $text -NoNewline
}

$charge = '    member _.Charge(request: ChargeRequest) : Receipt ='
$chargeAll = '    member this.ChargeAll(requests: ChargeRequest list) : Receipt list = requests |> List.map this.Charge'

Set-Variant 'add-bank-transfer' @(
    "    | PayPal of email: string`n`n/// The state", "    | PayPal of email: string`n    | BankTransfer of iban: string`n`n/// The state"
    "        | PaymentMethod.PayPal _ -> Math.Round(amount * 0.034m, 2)", "        | PaymentMethod.PayPal _ -> Math.Round(amount * 0.034m, 2)`n        | PaymentMethod.BankTransfer _ -> 0.25m")
Set-Variant 'tupled-calculate' @(
    'let calculate (method: PaymentMethod) (amount: decimal) : decimal =', 'let calculate (method: PaymentMethod, amount: decimal) : decimal ='
    'let fee = Fees.calculate request.Method request.Amount', 'let fee = Fees.calculate (request.Method, request.Amount)')
Set-Variant 'default-currency' @(
    $charge, '    member _.Charge(request: ChargeRequest, [<System.Runtime.InteropServices.Optional; System.Runtime.InteropServices.DefaultParameterValue("USD")>] settlementCurrency: string) : Receipt ='
    'requests |> List.map this.Charge', 'requests |> List.map (fun request -> this.Charge(request))')
Set-Variant 'chargeall-seq' @(
    $chargeAll, '    member this.ChargeAll(requests: seq<ChargeRequest>) : Receipt list = requests |> Seq.map this.Charge |> List.ofSeq')
Set-Variant 'key-fsharp-optional' @(
    $charge, '    member _.Charge(request: ChargeRequest, ?idempotencyKey: string) : Receipt ='
    'requests |> List.map this.Charge', 'requests |> List.map (fun request -> this.Charge(request))')
Set-Variant 'key-overload' @(
    $chargeAll, "$chargeAll`n`n    member this.Charge(request: ChargeRequest, idempotencyKey: string) : Receipt = this.Charge(request)"
    'requests |> List.map this.Charge', 'requests |> List.map (fun (request: ChargeRequest) -> this.Charge(request))')
Set-Variant 'receipt-currency' @(
    "      Total: decimal }", "      Total: decimal`n      Currency: string }"
    "          Total = total }", "          Total = total`n          Currency = request.Currency }")
Set-Variant 'status-qualified' @(
    "/// The state of a charge at the provider.`ntype ChargeStatus =", "/// The state of a charge at the provider.`n[<RequireQualifiedAccess>]`ntype ChargeStatus =")
Set-Variant 'gateway-refund' @(
    '    abstract Submit: request: ChargeRequest * total: decimal -> string', "    abstract Submit: request: ChargeRequest * total: decimal -> string`n    abstract Refund: chargeId: string -> unit")
Set-Variant 'obsolete-calculate' @(
    '    let calculate (method: PaymentMethod) (amount: decimal) : decimal =', "    let calculateFor (currency: string) (method: PaymentMethod) (amount: decimal) : decimal =`n        match method with`n        | PaymentMethod.Card _ -> Math.Round(amount * 0.029m + 0.30m, 2)`n        | PaymentMethod.PayPal _ -> Math.Round(amount * 0.034m, 2)`n`n    [<System.Obsolete(`"Use calculateFor.`")>]`n    let calculate (method: PaymentMethod) (amount: decimal) : decimal ="
    'let fee = Fees.calculate request.Method request.Amount', 'let fee = Fees.calculateFor request.Currency request.Method request.Amount')
