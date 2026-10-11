module Reports

open System
open System.Threading
open System.Threading.Tasks

type Report = { Id: int; Rows: int }

type Library =
    { LoadRows: int -> Async<int>
      Audit: string -> Async<unit> }

let buildReport (lib: Library) (id: int) : Async<Report> =
    async {
        if id < 0 then
            return raise (ArgumentOutOfRangeException(nameof id, "Report id must not be negative."))
        else
            let! rows = lib.LoadRows id
            do! lib.Audit $"report {id} built with {rows} rows"
            return { Id = id; Rows = rows }
    }

let handle (lib: Library) (id: int) (ct: CancellationToken) : Task<Report> =
    let report = Async.RunSynchronously(buildReport lib id)
    Task.FromResult report
