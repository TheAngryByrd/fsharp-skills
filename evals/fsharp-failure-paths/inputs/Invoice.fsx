type OrderLine = { Sku: string; Quantity: int }

// The tenant settings file. Operations removed the global currency default, so each tenant sets "currency".
type Settings = Map<string, string>

let currencyOf (settings: Settings) =
    defaultArg (Map.tryFind "currency" settings) "USD"

let checkLine (line: OrderLine) : Result<OrderLine, string> =
    if line.Quantity > 0 then Ok line
    else Error $"{line.Sku}: quantity must be positive"

let checkLines (lines: OrderLine list) : Result<OrderLine list, string> =
    let results = lines |> List.map checkLine
    let errors = results |> List.choose (function Error e -> Some e | Ok _ -> None)
    if List.isEmpty errors then
        Ok(results |> List.choose (function Ok l -> Some l | Error _ -> None))
    else
        Error(List.head errors)

let loadPrices (fetchPrices: unit -> Map<string, decimal>) =
    try fetchPrices () with _ -> Map.empty

let lineTotal (prices: Map<string, decimal>) (line: OrderLine) =
    Map.find line.Sku prices * decimal line.Quantity

/// Builds the invoice summary. An invoice has at least one line.
let invoice (settings: Settings) (fetchPrices: unit -> Map<string, decimal>) (lines: OrderLine list) : string =
    let currency = currencyOf settings
    let valid =
        match checkLines lines with
        | Ok valid -> valid
        | Error e -> failwith e
    let prices = loadPrices fetchPrices
    let total = valid |> List.sumBy (lineTotal prices)
    let first = List.head valid
    $"{List.length valid} lines, first {first.Sku}, total {total:F2} {currency}"
