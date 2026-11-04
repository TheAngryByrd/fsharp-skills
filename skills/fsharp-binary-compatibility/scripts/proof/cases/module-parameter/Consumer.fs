// expect break from v1: old=MissingMethodException rebuild=differs apicompat=reports strict=reports sig=reports api=reports
// expect safe from v1: old=same rebuild=same apicompat=clean strict=reports sig=reports api=reports
for text in [ "2.50"; "-1"; "abc" ] do
    printfn "%A" (Lib.parsePrice text)
