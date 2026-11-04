// expect break from v1: old=wrong rebuild=MatchFailureException rebuildwarn=FS0025 apicompat=clean strict=reports sig=reports api=reports
// expect safe from v1: old=same rebuild=same apicompat=clean strict=reports sig=reports api=reports
let describe state =
    match state with
    | Lib.Pending -> "pending"
    | Lib.Paid -> "paid"
    | Lib.Shipped -> "shipped"

for state in Lib.history 1 do
    printfn "%s" (describe state)
