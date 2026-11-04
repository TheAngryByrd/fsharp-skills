// expect insert from v1: old=same rebuild=same apicompat=clean strict=reports sig=reports api=reports
let describe state =
    match state with
    | Lib.Pending -> "pending"
    | Lib.Paid amount -> $"paid {amount}"
    | Lib.Shipped -> "shipped"

for state in [ Lib.Pending; Lib.Paid 2M; Lib.Shipped ] do
    printfn "%s" (describe state)
