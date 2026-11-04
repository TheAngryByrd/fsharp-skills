// expect break from v1: old=MissingMethodException rebuild=FS0039 apicompat=reports strict=reports sig=reports api=reports
// expect compiledname from v1: old=same rebuild=FS0039 apicompat=clean strict=clean sig=reports api=reports
// expect safe from v1: old=same rebuild=same strictrebuild=ok apicompat=clean strict=reports sig=reports api=reports
// expect obsolete from v1: old=same rebuild=same rebuildwarn=FS0044 strictrebuild=FS0044 apicompat=clean strict=reports sig=reports api=reports
printfn "%M" (Lib.computeTotal 2 1.5M)
