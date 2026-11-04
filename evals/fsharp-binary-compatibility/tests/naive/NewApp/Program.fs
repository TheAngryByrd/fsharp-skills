open Shipping

let p1 = { Id = "P1"; WeightKg = 2.0M; DeclaredValue = None }
let p4 = { Id = "P4"; WeightKg = 5.0M; DeclaredValue = Some 300.00M }

let show label result =
    match result with
    | Ok (price: decimal) -> printfn "%s %.2f" label price
    | Error message -> printfn "%s error: %s" label message

show "P1 standard" (quote Standard p1)
show "P1 express" (quote Express p1)
show "P4 insured" (quote Standard p4)

match statusOf "HD" with
| Some status -> printfn "HD %A" status
| None -> printfn "HD unknown"
