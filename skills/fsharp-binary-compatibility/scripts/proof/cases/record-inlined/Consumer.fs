// expect break from v1: old=MissingMethodException rebuild=same apicompat=reports strict=reports sig=reports api=reports
// expect safe from v1-noopt: old=same rebuild=same apicompat=reports strict=reports sig=reports api=reports
let line = Lib.line "A-1" 2
printfn "%d x %s" line.Quantity line.Sku
