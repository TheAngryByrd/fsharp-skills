module Dashboard

open System
open System.Threading
open System.Threading.Tasks

exception PanelNotFound of string

type PanelApi =
    abstract GetPanel: name: string * ct: CancellationToken -> Task<string>

let loadPanel (api: PanelApi) (name: string) : Async<string> =
    Async.AwaitTask(api.GetPanel(name, CancellationToken.None))

let loadDashboard (api: PanelApi) (names: string list) : Async<Result<string list, string>> =
    async {
        let results = ResizeArray()
        for name in names do
            let! panel = loadPanel api name
            results.Add panel
        return Ok(List.ofSeq results)
    }
