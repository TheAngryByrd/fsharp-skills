open Inventory

let lines = [ "abc-1234, 12"; "XYZ-0001,3"; "QRS-9999,0"; "bad,1"; "ABC-1234,-2" ]

let label level =
    match level with
    | StockLevel.OutOfStock -> "out of stock"
    | StockLevel.Low -> "low"
    | StockLevel.Healthy -> "healthy"

[<EntryPoint>]
let main _ =
    use ledger = new StockLedger()

    for line in lines do
        match Stock.parseLine line with
        | Ok item ->
            ledger.Receive(item.Sku, item.OnHand)
            printfn "%s %d %s" (Sku.value item.Sku) (Quantity.value item.OnHand) (label (Stock.classify item.OnHand))
        | Error message -> printfn "skipped: %s" message

    match Sku.tryParse "ABC-1234", Quantity.tryCreate 4 with
    | Some sku, Some extra ->
        ledger.Receive(sku, extra)
        let onHand = ledger.OnHand sku
        printfn "%s on hand %d, value %M" (Sku.value sku) (Quantity.value onHand) (Pricing.lineTotal 2.125m onHand)
        0
    | _ ->
        printfn "unexpected"
        1
