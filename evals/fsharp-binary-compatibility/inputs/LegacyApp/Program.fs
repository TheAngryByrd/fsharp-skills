open Shipping

let describe status =
    match status with
    | Created -> "label created"
    | Collected -> "collected by the driver"
    | InTransit -> "in transit"
    | Delivered -> "delivered"
    | Returned -> "returned to the sender"

let parcels =
    [ { Id = "P1"; WeightKg = 2.0M }
      { Id = "P2"; WeightKg = 0M }
      { Id = "P3"; WeightKg = 12.5M } ]

for parcel in parcels do
    match quote parcel with
    | Ok price -> printfn "%s %.2f" parcel.Id price
    | Error message -> printfn "%s error: %s" parcel.Id message

for code in [ "CR"; "CO"; "IT"; "DL"; "RT"; "XX" ] do
    match statusOf code with
    | Some status -> printfn "%s %s" code (describe status)
    | None -> printfn "%s unknown" code
