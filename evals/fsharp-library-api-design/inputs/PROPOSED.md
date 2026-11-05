# Proposed changes to Payments 1.0.0

Each change is separate. Each one starts from the 1.0.0 code in `Payments/Payments.fs`.

## add-bank-transfer

Add a payment method. `Fees.calculate` gets a branch for it.

```fsharp
[<RequireQualifiedAccess>]
type PaymentMethod =
    | Card of last4: string
    | PayPal of email: string
    | BankTransfer of iban: string
```

## tupled-calculate

Make `Fees.calculate` take a tuple, so that C# and F# calls look the same.

```fsharp
let calculate (method: PaymentMethod, amount: decimal) : decimal = ...
```

## default-currency

Give `Charge` a currency parameter that callers can leave out.

```fsharp
member _.Charge(request: ChargeRequest, [<Optional; DefaultParameterValue("USD")>] settlementCurrency: string) : Receipt = ...
```

This member replaces `member _.Charge(request: ChargeRequest) : Receipt`.

## chargeall-seq

Let `ChargeAll` accept any sequence.

```fsharp
member this.ChargeAll(requests: seq<ChargeRequest>) : Receipt list = ...
```

This member replaces `member this.ChargeAll(requests: ChargeRequest list) : Receipt list`.

## key-fsharp-optional

Give `Charge` an optional idempotency key.

```fsharp
member _.Charge(request: ChargeRequest, ?idempotencyKey: string) : Receipt = ...
```

This member replaces `member _.Charge(request: ChargeRequest) : Receipt`.

## key-overload

Add an idempotency key with a second member. The 1.0.0 `Charge` member stays.

```fsharp
member _.Charge(request: ChargeRequest, idempotencyKey: string) : Receipt = ...
```

## receipt-currency

Show the currency on each receipt. `Charge` fills the new field.

```fsharp
type Receipt =
    { ChargeId: string
      Amount: decimal
      Fee: decimal
      Total: decimal
      Currency: string }
```

## status-qualified

Require the type name for `ChargeStatus` cases.

```fsharp
[<RequireQualifiedAccess>]
type ChargeStatus =
    | Approved
    | Declined
```

## gateway-refund

Let gateways refund charges.

```fsharp
type IPaymentGateway =
    abstract Submit: request: ChargeRequest * total: decimal -> string
    abstract Refund: chargeId: string -> unit
```

## obsolete-calculate

Add `Fees.calculateFor`, which also takes the currency, and retire `Fees.calculate`.

```fsharp
[<System.Obsolete("Use calculateFor.")>]
let calculate (method: PaymentMethod) (amount: decimal) : decimal = ...

let calculateFor (currency: string) (method: PaymentMethod) (amount: decimal) : decimal = ...
```
