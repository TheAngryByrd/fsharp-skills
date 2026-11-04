// expect break from v1: old=stale rebuild=differs apicompat=clean strict=clean sig=clean api=clean
// expect safe from v1-noopt: old=updated rebuild=differs apicompat=clean strict=clean sig=clean api=clean
// expect safe from v1: old=stale rebuild=differs apicompat=clean strict=clean sig=clean api=clean
printfn "%M" (Lib.tax 10M)
