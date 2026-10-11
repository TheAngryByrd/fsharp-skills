#load "OrderProps.fsx"

open Orders
open OrderProps

let report name passed detail =
    if passed then printfn "PASS %s" name else printfn "FAIL %s [%s]" name detail

let validLine (line: OrderLine) =
    List.contains line.Sku [ "A1"; "B2"; "C3" ]
    && line.Quantity >= 1
    && line.Quantity <= 10
    && line.UnitPrice >= 1m
    && line.UnitPrice <= 100m
    && line.UnitPrice = System.Math.Round line.UnitPrice

let attempt f =
    try Ok(f ()) with ex -> Error(ex.GetType().Name + ": " + ex.Message.Split('\n')[0])

let typedLineGen: FsCheck.Gen<OrderLine> = lineGen

match attempt (fun () -> sampleLines 300 @ List.ofArray (FsCheck.FSharp.Gen.sample 100 typedLineGen)) with
| Ok lines ->
    let bad = lines |> List.filter (validLine >> not)
    report "sampleLines 300 returns 300 lines" (List.length lines = 400) (string (List.length lines - 100))
    report "Every sampled line meets the constraints" (List.isEmpty bad) (sprintf "%A" (List.truncate 3 bad))
    let skus = lines |> List.map _.Sku |> List.distinct |> List.length
    let quantities = lines |> List.map _.Quantity |> List.distinct |> List.length
    let prices = lines |> List.map _.UnitPrice |> List.distinct |> List.length
    report "Samples use every SKU and vary quantity and price" (skus = 3 && quantities >= 2 && prices >= 2) $"skus {skus}, quantities {quantities}, prices {prices}"
| Error e ->
    report "sampleLines 300 returns 300 lines" false e
    report "Every sampled line meets the constraints" false e
    report "Samples use every SKU and vary quantity and price" false e

match attempt (fun () -> FsCheck.FSharp.Gen.sample 200 orderArb.Generator) with
| Ok orders ->
    let bad = orders |> Array.filter (fun o -> List.isEmpty o || not (List.forall validLine o))
    report "orderArb gives non-empty orders of valid lines" (Array.isEmpty bad) (sprintf "%A" (Array.truncate 2 bad))
| Error e -> report "orderArb gives non-empty orders of valid lines" false e

let mutable calls = 0
let mutable invalidOrders = 0
let counted lines =
    calls <- calls + 1
    if List.isEmpty lines || not (List.forall validLine lines) then invalidOrders <- invalidOrders + 1
    total lines
match attempt (fun () -> checkTotal counted) with
| Ok () -> report "checkTotal passes the correct total in exactly 250 valid orders" (calls = 250 && invalidOrders = 0) $"{calls} calls, {invalidOrders} invalid orders"
| Error e -> report "checkTotal passes the correct total in exactly 250 valid orders" false e

let ignoresQuantity (lines: OrderLine list) = lines |> List.sumBy _.UnitPrice
match attempt (fun () -> checkTotal ignoresQuantity) with
| Ok () -> report "checkTotal throws for a total that ignores quantity" false "no exception"
| Error _ -> report "checkTotal throws for a total that ignores quantity" true ""
