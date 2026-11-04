// expect break from v1: old=stale rebuild=differs apicompat=clean strict=clean sig=reports api=reports
// expect safe from v1-plain: old=updated rebuild=differs apicompat=clean strict=clean sig=clean api=clean
// expect plain-default from v1-plain-default: old=stale rebuild=differs apicompat=clean strict=clean sig=clean api=clean
printfn "%d" Lib.MaxLines
