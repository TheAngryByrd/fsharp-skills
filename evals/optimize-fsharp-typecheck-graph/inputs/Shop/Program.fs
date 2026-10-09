module Program

open Shop.Customers
open Shop.Products
open Shop.Inventory
open Shop.Pricing
open Shop.Reports

[<EntryPoint>]
let main _ =
    let p = { Sku = "ABC1"; Price = 10m }
    printfn "%s" (Report.customers [ { Id = 1; Name = "ann"; Tier = 2 } ])
    printfn "%M" (Discount.apply 150m p)
    printfn "%d" (Stock.available (Map.ofList [ ("ABC1", 3) ]) p)
    0
