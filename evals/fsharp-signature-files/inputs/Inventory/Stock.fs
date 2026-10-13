namespace Inventory

open System

/// How much stock is left for a SKU.
[<RequireQualifiedAccess>]
type StockLevel =
    | OutOfStock
    | Low
    | Healthy

/// One line of a stock file.
type StockItem = { Sku: Sku; OnHand: Quantity }

module Stock =
    let lowThreshold = 5

    let splitFields (line: string) =
        line.Split(',', StringSplitOptions.TrimEntries)

    /// Classifies a quantity: 0 is OutOfStock, 1 to 5 is Low, and more is Healthy.
    let classify (onHand: Quantity) =
        match Quantity.value onHand with
        | 0 -> StockLevel.OutOfStock
        | n when n <= lowThreshold -> StockLevel.Low
        | _ -> StockLevel.Healthy

    /// Parses a stock line with the shape "SKU,count", for example "ABC-1234,12".
    let parseLine (line: string) : Result<StockItem, string> =
        match splitFields line with
        | [| skuText; countText |] ->
            match Sku.tryParse skuText, Int32.TryParse countText with
            | Some sku, (true, count) ->
                match Quantity.tryCreate count with
                | Some onHand -> Ok { Sku = sku; OnHand = onHand }
                | None -> Error $"Negative count in '{line}'."
            | None, _ -> Error $"Bad SKU in '{line}'."
            | _, _ -> Error $"Bad count in '{line}'."
        | _ -> Error $"Expected two fields in '{line}'."

/// Keeps the quantity on hand for each SKU while it is open.
type StockLedger() =
    let counts = Collections.Generic.Dictionary<Sku, Quantity>()

    /// Adds received units to the quantity on hand.
    member _.Receive(sku: Sku, units: Quantity) =
        match counts.TryGetValue sku with
        | true, current -> counts[sku] <- Quantity.add current units
        | _ -> counts[sku] <- units

    /// The quantity on hand. It is zero for a SKU that the ledger has not received.
    member _.OnHand(sku: Sku) =
        match counts.TryGetValue sku with
        | true, current -> current
        | _ -> Quantity.zero

    interface IDisposable with
        member _.Dispose() = counts.Clear()
