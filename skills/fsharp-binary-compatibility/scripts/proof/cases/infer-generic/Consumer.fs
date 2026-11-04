// expect break from v1: old=MissingMethodException rebuild=same apicompat=reports strict=reports sig=reports api=reports
// expect safe from v1: old=same rebuild=same apicompat=clean strict=clean sig=clean api=clean
printfn "%d %d" (Lib.firstOr 7 []) (Lib.firstOr 7 [ 1; 2 ])
