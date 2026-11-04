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
    /// Charges the request and returns its receipt.
    member _.Charge(request: ChargeRequest) : Receipt =
        if request.Amount <= 0m then
            invalidArg (nameof request) "The amount must be positive."
        let fee = Fees.calculate request.Method request.Amount
        let total = request.Amount + fee
        let chargeId = gateway.Submit(request, total)
        { ChargeId = chargeId
          Amount = request.Amount
          Fee = fee
          Total = total }

    /// Charges each request in order and returns the receipts.
    member this.ChargeAll(requests: ChargeRequest list) : Receipt list = requests |> List.map this.Charge
