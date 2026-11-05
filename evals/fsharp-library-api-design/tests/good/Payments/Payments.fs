namespace Payments

open System

/// How the customer pays.
[<RequireQualifiedAccess>]
type PaymentMethod =
    | Card of last4: string
    | PayPal of email: string

/// The state of a charge at the provider.
type ChargeStatus =
    | Approved
    | Declined

/// One charge that a merchant asks for.
type ChargeRequest =
    { Amount: decimal
      Currency: string
      Method: PaymentMethod }

/// The result of a successful charge.
type Receipt =
    { ChargeId: string
      Amount: decimal
      Fee: decimal
      Total: decimal }

/// Sends a charge to the payment provider and returns the provider's charge id.
type IPaymentGateway =
    abstract Submit: request: ChargeRequest * total: decimal -> string

module Fees =
    /// The fee for an amount paid with a payment method.
    let calculate (method: PaymentMethod) (amount: decimal) : decimal =
        match method with
        | PaymentMethod.Card _ -> Math.Round(amount * 0.029m + 0.30m, 2)
        | PaymentMethod.PayPal _ -> Math.Round(amount * 0.034m, 2)

/// Charges customers through a gateway.
type PaymentClient(gateway: IPaymentGateway) =
    let receipts = System.Collections.Generic.Dictionary<string, Receipt>()

    let charge (request: ChargeRequest) =
        if request.Amount <= 0m then
            invalidArg (nameof request) "The amount must be positive."
        let fee = Fees.calculate request.Method request.Amount
        let total = request.Amount + fee
        let chargeId = gateway.Submit(request, total)
        { ChargeId = chargeId
          Amount = request.Amount
          Fee = fee
          Total = total }

    let chargeOnce (request: ChargeRequest) (idempotencyKey: string) =
        if isNull idempotencyKey then
            charge request
        else
            match receipts.TryGetValue idempotencyKey with
            | true, receipt -> receipt
            | false, _ ->
                let receipt = charge request
                receipts[idempotencyKey] <- receipt
                receipt

    /// Charges the request and returns its receipt.
    member _.Charge(request: ChargeRequest) : Receipt = charge request

    /// Charges the request once for each idempotency key. A repeated key returns the first receipt.
    member _.Charge(request: ChargeRequest, idempotencyKey: string) : Receipt = chargeOnce request idempotencyKey

    /// Charges each request in order and returns the receipts.
    member _.ChargeAll(requests: ChargeRequest list) : Receipt list = requests |> List.map charge

    /// Charges each request of any sequence in order and returns the receipts.
    member _.ChargeAll(requests: seq<ChargeRequest>) : Receipt list = requests |> Seq.map charge |> List.ofSeq
