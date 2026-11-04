// expect break from v1: old=MissingMethodException rebuild=same apicompat=reports strict=reports sig=reports api=reports
// expect safe from v1: old=same rebuild=same apicompat=clean strict=reports sig=reports api=reports
printfn "%A" (Lib.Prices.Parse "2.50")
