open Shipping

let p1 = { Id = "P1"; WeightKg = 2.0M }
let p4 = { Id = "P4"; WeightKg = 5.0M }

let show label result =
    match result with
    | Ok (price: decimal) -> printfn "%s %.2f" label price
    | Error message -> printfn "%s error: %s" label message

show "P1 standard" (quoteFor Standard p1)
show "P1 express" (quoteFor Express p1)
show "P4 insured" (quoteInsured 300.00M p4)

match statusOfCode "HD" with
| Some status -> printfn "HD %A" status
| None -> printfn "HD unknown"
