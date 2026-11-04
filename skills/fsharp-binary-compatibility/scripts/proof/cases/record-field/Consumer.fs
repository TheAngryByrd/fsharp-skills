// expect break from v1: old=MissingMethodException rebuild=FS0764 apicompat=reports strict=reports sig=reports api=reports
// expect constructor from v1: build=FS0871
// expect safe from v1: old=same rebuild=same apicompat=clean strict=reports sig=reports api=reports
let line: Lib.OrderLine = { Sku = "A-1"; Quantity = 2 }
let more = { line with Quantity = 3 }
printfn "%s / %s" (Lib.describe line) (Lib.describe more)
