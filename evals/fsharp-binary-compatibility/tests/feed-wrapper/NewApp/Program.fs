open Shipping

let show label result =
    match result with
    | Ok (price: decimal) -> printfn "%s %.2f" label price
    | Error message -> printfn "%s error: %s" label message

let p1 = { Id = "P1"; WeightKg = 2.0M }
let p4 = { Id = "P4"; WeightKg = 5.0M }

show "P1 standard" (quote p1)
show "P1 express" (quoteExpress p1)
show "P4 insured" (quoteInsured { Parcel = p4; DeclaredValue = 300.00M })

match parseTrackingCode "HD" with
| Ok status -> printfn "HD %A" status
| Error message -> printfn "HD %s" message
