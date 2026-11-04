// expect break from v1: old=same rebuild=FS0003 apicompat=clean strict=clean sig=reports api=reports
// expect safe from v1: old=same rebuild=same apicompat=clean strict=reports sig=reports api=reports
printfn "%M" (Lib.lineTotal 2 1.5M)
