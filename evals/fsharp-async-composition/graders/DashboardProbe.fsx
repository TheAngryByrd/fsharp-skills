#load "Dashboard.fsx"

open System
open System.Collections.Concurrent
open System.Diagnostics
open System.Threading
open System.Threading.Tasks
open Dashboard

let private loadPanelSignature: PanelApi -> string -> Async<string> = loadPanel

let report name (passed: bool) (detail: string) =
    Console.WriteLine((if passed then "PASS " else "FAIL ") + name + (if passed then "" else " [" + detail + "]"))

type Behavior =
    | Returns of delayMs: int
    | NotFound of delayMs: int
    | TimesOut of failures: int
    | Slow of delayMs: int

type FakeApi(behaviors: Map<string, Behavior>) =
    member val Calls = ConcurrentDictionary<string, int>()
    member val CancelledAfterMs = ConcurrentDictionary<string, int64>()
    member val Clock = Stopwatch.StartNew()

    interface PanelApi with
        member this.GetPanel(name, ct) =
            let call = this.Calls.AddOrUpdate(name, 1, fun _ n -> n + 1)
            task {
                match behaviors.[name] with
                | Returns ms ->
                    do! Task.Delay ms
                    return name.ToUpperInvariant()
                | NotFound ms ->
                    do! Task.Delay ms
                    return raise (PanelNotFound name)
                | TimesOut failures ->
                    do! Task.Delay 10
                    if call <= failures then return raise (TimeoutException name)
                    else return name.ToUpperInvariant()
                | Slow ms ->
                    use _ = ct.Register(fun () -> this.CancelledAfterMs.[name] <- this.Clock.ElapsedMilliseconds)
                    do! Task.Delay(ms, ct)
                    return name.ToUpperInvariant()
            }

let run (api: FakeApi) names timeoutMs =
    let work = Async.StartAsTask(loadDashboard api names)
    if work.Wait(timeoutMs: int) then
        Ok work.Result
    else
        Error $"no result after {timeoutMs} ms"

let attempt name (body: unit -> unit) =
    try body () with ex ->
        let inner = match ex with :? AggregateException as a -> a.InnerException | e -> e
        report name false $"threw {inner.GetType().Name}: {inner.Message}"

attempt "loadDashboard returns every panel in order" (fun () ->
    let api = FakeApi(Map [ "a", Returns 60; "b", Returns 10; "c", Returns 30 ])
    let r = run api [ "a"; "b"; "c" ] 5000
    report "loadDashboard returns every panel in order" (r = Ok(Ok [ "A"; "B"; "C" ])) $"%A{r}")

attempt "loadDashboard loads panels concurrently" (fun () ->
    let api = FakeApi(Map [ "a", Returns 300; "b", Returns 300; "c", Returns 300 ])
    let sw = Stopwatch.StartNew()
    let r = run api [ "a"; "b"; "c" ] 5000
    report "loadDashboard loads panels concurrently" (r = Ok(Ok [ "A"; "B"; "C" ]) && sw.ElapsedMilliseconds < 750) $"{sw.ElapsedMilliseconds} ms, %A{r}")

attempt "a missing panel gives Error missing" (fun () ->
    let api = FakeApi(Map [ "a", Returns 10; "gone", NotFound 30 ])
    let r = run api [ "a"; "gone" ] 5000
    report "a missing panel gives Error missing" (r = Ok(Error "missing: gone")) $"%A{r}")

attempt "a missing panel cancels the other panel loads" (fun () ->
    let api = FakeApi(Map [ "slow", Slow 3000; "gone", NotFound 50 ])
    let r = run api [ "slow"; "gone" ] 5000
    let cancelled, at = api.CancelledAfterMs.TryGetValue "slow"
    report "a missing panel gives Error missing while another panel is slow" (r = Ok(Error "missing: gone")) $"%A{r}"
    report "a missing panel cancels the other panel loads" (cancelled && at < 1000) $"slow panel token cancelled={cancelled} at {at} ms")

attempt "a timeout is retried with a new request" (fun () ->
    let api = FakeApi(Map [ "a", Returns 10; "flaky", TimesOut 2 ])
    let r = run api [ "a"; "flaky" ] 5000
    let calls = match api.Calls.TryGetValue "flaky" with | true, n -> n | _ -> 0
    report "a timeout is retried with a new request" (r = Ok(Ok [ "A"; "FLAKY" ]) && calls = 3) $"GetPanel calls {calls}, %A{r}")

attempt "each panel has its own retry budget" (fun () ->
    let api = FakeApi(Map [ "x", TimesOut 2; "y", TimesOut 2 ])
    let r = run api [ "x"; "y" ] 5000
    let calls name = match api.Calls.TryGetValue name with | true, n -> n | _ -> 0
    let x, y = calls "x", calls "y"
    report "each panel has its own retry budget" (r = Ok(Ok [ "X"; "Y" ]) && x = 3 && y = 3) $"GetPanel calls x={x} y={y}, %A{r}")

attempt "three timeouts give Error timeout" (fun () ->
    let api = FakeApi(Map [ "down", TimesOut 99 ])
    let r = run api [ "down" ] 5000
    let calls = match api.Calls.TryGetValue "down" with | true, n -> n | _ -> 0
    report "three timeouts give Error timeout" (r = Ok(Error "timeout: down") && calls = 3) $"GetPanel calls {calls}, %A{r}")
