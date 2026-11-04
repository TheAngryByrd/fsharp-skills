// expect break from v1: old=MissingMethodException rebuild=same apicompat=reports strict=reports sig=reports api=reports
let more = { Lib.sample with Quantity = 3 }
printfn "%d x %s" more.Quantity more.Sku
