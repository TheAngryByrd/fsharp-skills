// expect break from v1: old=stale rebuild=differs apicompat=clean strict=clean sig=clean api=clean
// expect noopt from v1: old=stale rebuild=differs apicompat=clean strict=clean sig=clean api=clean
// expect safe from v1-plain: old=updated rebuild=differs apicompat=clean strict=clean sig=clean api=clean
printfn "%M" (Lib.tax 10M)
