// expect break from v1: old=wrong rebuild=same apicompat=clean strict=reports sig=reports api=reports
// expect safe from v1: old=same rebuild=same apicompat=clean strict=reports sig=reports api=reports
let describe state =
    match state with
    | Lib.Pending -> "pending"
    | Lib.Paid -> "paid"
    | Lib.Shipped -> "shipped"
    | Lib.Delivered -> "delivered"
    | Lib.Cancelled -> "cancelled"

for state in [ Lib.Pending; Lib.Paid; Lib.Shipped; Lib.Delivered; Lib.Cancelled ] do
    printfn "%s" (describe state)
