#r "nuget: FsToolkit.ErrorHandling, 5.2.0"

open System
open FsToolkit.ErrorHandling

type SkuError = InvalidSku of raw: string

type QuantityError = NotPositive of value: int

type StockError =
    | OutOfStock of sku: string
    | Discontinued of sku: string

type PricingError = NoPrice of sku: string

type PlaceOrderError =
    | Sku of SkuError
    | Quantity of QuantityError
    | Stock of StockError
    | Pricing of PricingError

let parseSku (raw: string) : Result<string, SkuError> =
    if raw.Length >= 1 && raw.Length <= 8 && raw |> Seq.forall Char.IsAsciiLetterOrDigit then
        Ok raw
    else
        Error(InvalidSku raw)

let parseQuantity (value: int) : Result<int, QuantityError> =
    if value > 0 then Ok value else Error(NotPositive value)

let reserveStock (onHand: Map<string, int>) (sku: string) (quantity: int) : Result<unit, StockError> =
    match Map.tryFind sku onHand with
    | None -> Error(Discontinued sku)
    | Some n when n < quantity -> Error(OutOfStock sku)
    | Some _ -> Ok()

let price (prices: Map<string, decimal>) (sku: string) (quantity: int) : Result<decimal, PricingError> =
    match Map.tryFind sku prices with
    | Some p -> Ok(p * decimal quantity)
    | None -> Error(NoPrice sku)

let placeOrder onHand prices rawSku rawQuantity : Result<decimal, PlaceOrderError> =
    result {
        let! sku = parseSku rawSku |> Result.mapError Sku
        let! quantity = parseQuantity rawQuantity |> Result.mapError Quantity
        do! reserveStock onHand sku quantity |> Result.mapError Stock
        return! price prices sku quantity |> Result.mapError Pricing
    }

let describe (error: PlaceOrderError) =
    match error with
    | Sku(InvalidSku raw) -> $"bad sku {raw}"
    | Quantity(NotPositive value) -> $"bad quantity {value}"
    | Stock(OutOfStock sku) -> $"out of stock {sku}"
    | Stock(Discontinued sku) -> $"discontinued {sku}"
    | Pricing(NoPrice sku) -> $"no price {sku}"

// Demo. Keep this output unchanged.
let onHand = Map.ofList [ ("ABC1", 5); ("NOPRICE", 3) ]
let prices = Map.ofList [ ("ABC1", 2.5m) ]

let cases =
    [ ("ABC1", 2)
      ("bad sku!", 1)
      ("ABC1", 0)
      ("ZZZ9", 1)
      ("ABC1", 9)
      ("NOPRICE", 1) ]

for (rawSku, rawQuantity) in cases do
    match placeOrder onHand prices rawSku rawQuantity with
    | Ok total -> printfn "%s x%d: total %M" rawSku rawQuantity total
    | Error e -> printfn "%s x%d: %s" rawSku rawQuantity (describe e)
