open Inventory

let mutable failures = 0

let check name condition =
    if condition then
        printfn "PASS %s" name
    else
        printfn "FAIL %s" name
        failures <- failures + 1

check "tryParse normalizes" (Sku.tryParse " abc-1234 " |> Option.map Sku.value = Some "ABC-1234")
check "tryParse rejects a short code" (Sku.tryParse "AB-1234" = None)
check "tryCreate rejects a negative count" (Quantity.tryCreate -1 = None)
check "classify 0 is OutOfStock" (Quantity.tryCreate 0 |> Option.map Stock.classify = Some StockLevel.OutOfStock)
check "classify 5 is Low" (Quantity.tryCreate 5 |> Option.map Stock.classify = Some StockLevel.Low)
check "classify 6 is Healthy" (Quantity.tryCreate 6 |> Option.map Stock.classify = Some StockLevel.Healthy)
check "parseLine reports a bad SKU" (Stock.parseLine "nope,1" = Error "Bad SKU in 'nope,1'.")
check "roundToCents rounds a midpoint to even" (Pricing.roundToCents 2.125m = 2.12m)
check "roundToCents rounds up above a midpoint" (Pricing.roundToCents 2.126m = 2.13m)

exit (if failures = 0 then 0 else 1)
