open Shipping

let describe status =
    match status with
    | Created -> "label created"
    | Collected -> "collected by the driver"
    | InTransit -> "in transit"
    | Delivered -> "delivered"
    | Returned -> "returned to the sender"

let first = { Id = "P1"; WeightKg = 2.0M }
let heavier = { first with Id = "P5"; WeightKg = 29.5M }

for parcel in [ first; { Id = "P2"; WeightKg = 0M }; heavier; { Id = "P6"; WeightKg = 31M } ] do
    match quote parcel with
    | Ok price -> printfn "%s %.2f" parcel.Id price
    | Error message -> printfn "%s error: %s" parcel.Id message

for code in [ "CR"; "CO"; "IT"; "HD"; "DL"; "RT"; " dl "; "XX" ] do
    match statusOf code with
    | Some status -> printfn "%s %s" code (describe status)
    | None -> printfn "%s unknown" code
