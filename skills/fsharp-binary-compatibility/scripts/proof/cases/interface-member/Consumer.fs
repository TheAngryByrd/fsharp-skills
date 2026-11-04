// expect break from v1: old=TypeLoadException rebuild=FS0366 apicompat=reports strict=reports sig=reports api=reports
// expect safe from v1: old=same rebuild=same apicompat=clean strict=reports sig=reports api=reports
let pricer =
    { new Lib.IPricer with
        member _.Price quantity = decimal quantity * 1.5M }

printfn "%M" (Lib.total pricer [ 1; 2 ])
