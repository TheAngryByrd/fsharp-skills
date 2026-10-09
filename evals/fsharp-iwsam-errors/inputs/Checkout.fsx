#r "nuget: FsToolkit.ErrorHandling, 5.2.0"
#nowarn "3535"

open System
open FsToolkit.ErrorHandling

type SkuError<'e> =
    static abstract InvalidSku: raw: string -> 'e

type Sku = private Sku of string

module Sku =
    let value (Sku s) = s

    let parse<'e when SkuError<'e>> (raw: string) : Result<Sku, 'e> =
        if raw.Length >= 1 && raw.Length <= 8 && raw |> Seq.forall Char.IsAsciiLetterOrDigit then
            Ok(Sku raw)
        else
            Error('e.InvalidSku raw)

type StockError<'e> =
    static abstract OutOfStock: sku: Sku -> 'e
    static abstract Discontinued: sku: Sku -> 'e

type PaymentError<'e> =
    static abstract Declined: amount: decimal -> 'e
    static abstract CardExpired: 'e

type Card = { Balance: decimal; ExpiryYear: int }

let reserveStock (onHand: Map<Sku, int>) (sku: Sku) (quantity: int) : Result<unit, 'e> =
    match Map.tryFind sku onHand with
    | None -> Error('e.Discontinued sku)
    | Some n when n < quantity -> Error('e.OutOfStock sku)
    | Some _ -> Ok()

let charge<'e when PaymentError<'e>> (card: Card) (amount: decimal) : Result<unit, 'e> =
    if card.ExpiryYear < 2026 then Error 'e.CardExpired
    elif card.Balance < amount then Error('e.Declined amount)
    else Ok()

let checkout onHand rawSku quantity card =
    result {
        let! sku = Sku.parse rawSku
        do! reserveStock onHand sku quantity
        do! charge card (decimal quantity * 10m)
    }

type ApiError =
    | BadSku of raw: string
    | NoStock of sku: Sku
    | Gone of sku: Sku
    | PaymentDeclined of amount: decimal
    | Expired

    interface SkuError<ApiError> with
        static member InvalidSku raw = BadSku raw

    interface StockError<ApiError> with
        static member OutOfStock sku = NoStock sku
        static member Discontinued sku = Gone sku

    interface PaymentError<ApiError> with
        static member Declined amount = PaymentDeclined amount

let describe (error: ApiError) =
    match error with
    | BadSku raw -> $"bad sku {raw}"
    | NoStock sku -> $"out of stock {Sku.value sku}"
    | Gone sku -> $"discontinued {Sku.value sku}"
    | PaymentDeclined amount -> $"declined {amount}"
    | Expired -> "card expired"

let onHand =
    [ ("ABC1", 5) ]
    |> List.choose (fun (raw, n) ->
        match Sku.parse<ApiError> raw with
        | Ok sku -> Some(sku, n)
        | Error _ -> None)
    |> Map.ofList

let goodCard = { Balance = 100m; ExpiryYear = 2030 }

let cases =
    [ "ABC1", 1, goodCard
      "bad sku!", 1, goodCard
      "ZZZ9", 1, goodCard
      "ABC1", 9, goodCard
      "ABC1", 1, { goodCard with ExpiryYear = 2020 }
      "ABC1", 4, { goodCard with Balance = 5m } ]

for (raw, quantity, card) in cases do
    let outcome = checkout onHand raw quantity card

    match outcome with
    | Ok() -> printfn "%s x%d: ok" raw quantity
    | Error e -> printfn "%s x%d: %s" raw quantity (describe e)

let smokeTest = checkout onHand "ABC1" 1 goodCard |> Result.isOk
printfn "smoke test: %b" smokeTest
