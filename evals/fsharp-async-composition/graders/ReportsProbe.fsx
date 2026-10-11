#load "Reports.fsx"

open System
open System.Collections.Concurrent
open System.Diagnostics
open System.Threading
open System.Threading.Tasks
open Reports

let report name (passed: bool) (detail: string) =
    Console.WriteLine((if passed then "PASS " else "FAIL ") + name + (if passed then "" else " [" + detail + "]"))

type Probe() =
    member val Steps = 0 with get, set
    member val LoadCancelled = false with get, set
    member val Audits = ConcurrentQueue<string>()
    member val Events = ConcurrentQueue<string>()

let library (probe: Probe) (steps: int) (servedDelayMs: int) : Library =
    { LoadRows =
        fun id ->
            async {
                use! _ = Async.OnCancel(fun () -> probe.LoadCancelled <- true)
                for _ in 1..steps do
                    do! Async.Sleep 20
                    probe.Steps <- probe.Steps + 1
                return id * 10
            }
      Audit =
        fun text ->
            async {
                probe.Events.Enqueue("start " + text)
                if text.Contains "served" then
                    do! Async.Sleep(max servedDelayMs 0)
                    if servedDelayMs < 0 then failwith "audit store unavailable"
                probe.Audits.Enqueue text
                probe.Events.Enqueue("done " + text)
            } }

let unwrap (ex: exn) =
    match ex with
    | :? AggregateException as agg when agg.InnerExceptions.Count = 1 -> agg.InnerExceptions.[0]
    | other -> other

let start (f: unit -> Task<Report>) =
    try Ok(f ()) with ex -> Error ex

let finishes (t: Task) (ms: int) = try t.Wait ms with _ -> true

let run name (body: unit -> unit) =
    try body () with ex -> report name false $"probe threw {ex.GetType().Name}: {ex.Message}"

run "handle returns the report for a valid id" (fun () ->
    let probe = Probe()
    match start (fun () -> handle (library probe 2 0) 4 CancellationToken.None) with
    | Ok t ->
        let ok = finishes t 5000 && t.Status = TaskStatus.RanToCompletion && t.Result = { Id = 4; Rows = 40 }
        report "handle returns the report for a valid id" ok (string t.Status)
    | Error ex -> report "handle returns the report for a valid id" false (ex.GetType().Name))

run "handle returns before the rows are loaded" (fun () ->
    let probe = Probe()
    let sw = Stopwatch.StartNew()
    match start (fun () -> handle (library probe 25 0) 1 CancellationToken.None) with
    | Ok t ->
        let elapsed = sw.ElapsedMilliseconds
        report "handle returns before the rows are loaded" (elapsed < 250 && not t.IsCompleted) $"returned after {elapsed} ms, completed={t.IsCompleted}"
        finishes t 5000 |> ignore
    | Error ex -> report "handle returns before the rows are loaded" false (ex.GetType().Name))

run "cancelling the token cancels the request" (fun () ->
    let probe = Probe()
    use cts = new CancellationTokenSource()
    match start (fun () -> handle (library probe 100 0) 2 cts.Token) with
    | Ok t ->
        Thread.Sleep 150
        cts.Cancel()
        let ended = finishes t 1000
        let error = if t.IsFaulted then Some(unwrap t.Exception) else None
        let cancelled =
            t.IsCanceled
            || (match error with
                | Some(:? OperationCanceledException) -> true
                | _ -> false)
        report "cancelling the token cancels the request" (ended && cancelled) $"status after cancel: {t.Status}"
        let stepsAtCancel = probe.Steps
        Thread.Sleep 300
        report "cancelling the token stops LoadRows" (probe.LoadCancelled && probe.Steps <= stepsAtCancel + 1) $"LoadRows cancelled={probe.LoadCancelled}, steps {stepsAtCancel} then {probe.Steps} of 100"
        finishes t 5000 |> ignore
    | Error ex ->
        report "cancelling the token cancels the request" false (ex.GetType().Name)
        report "cancelling the token stops LoadRows" false (ex.GetType().Name))

run "a negative id gives a faulted task with ArgumentOutOfRangeException" (fun () ->
    let probe = Probe()
    let name = "a negative id gives a faulted task with ArgumentOutOfRangeException"
    match start (fun () -> handle (library probe 1 0) -3 CancellationToken.None) with
    | Ok t ->
        if not (finishes t 5000) then
            report name false "the task did not complete within 5 s"
        else
            let thrown = try t.GetAwaiter().GetResult() |> ignore; None with ex -> Some ex
            match thrown with
            | Some(:? ArgumentOutOfRangeException) -> report name true ""
            | Some ex -> report name false $"awaiting the task threw {ex.GetType().Name}"
            | None -> report name false "the task succeeded"
    | Error ex -> report name false $"handle threw {ex.GetType().Name} before it returned a task")

run "the served audit entry is written without delaying the response" (fun () ->
    let probe = Probe()
    let name = "the served audit entry is written without delaying the response"
    let sw = Stopwatch.StartNew()
    match start (fun () -> handle (library probe 1 600) 7 CancellationToken.None) with
    | Ok t ->
        let ended = finishes t 5000
        let elapsed = sw.ElapsedMilliseconds
        report name (ended && t.Status = TaskStatus.RanToCompletion && elapsed < 450) $"response after {elapsed} ms, status {t.Status}"
        Thread.Sleep 1500
        let audits = List.ofSeq probe.Events
        let served = audits |> List.tryFindIndex (fun a -> a = "start report 7 served")
        let built = audits |> List.tryFindIndex (fun a -> a = "done report 7 built with 70 rows")
        let completed = probe.Audits |> Seq.contains "report 7 served"
        let ordered =
            match served, built with
            | Some s, Some b -> completed && b < s
            | _ -> false
        report "the served audit entry is written after the report is built" ordered $"audit entries: {String.Join(';', audits)}"
    | Error ex ->
        report name false (ex.GetType().Name)
        report "the served audit entry is written after the report is built" false (ex.GetType().Name))

run "a failed request writes no served audit entry" (fun () ->
    let probe = Probe()
    let name = "a failed request writes no served audit entry"
    match start (fun () -> handle (library probe 1 0) -3 CancellationToken.None) with
    | Ok t ->
        finishes t 5000 |> ignore
        Thread.Sleep 500
        let served = probe.Audits |> Seq.exists (fun a -> a.Contains "served")
        report name (not served) $"audit entries: {String.Join(';', probe.Audits)}"
    | Error _ ->
        Thread.Sleep 500
        let served = probe.Audits |> Seq.exists (fun a -> a.Contains "served")
        report name (not served) $"audit entries: {String.Join(';', probe.Audits)}")

// Runs last: an unhandled exception in fire-and-forget work stops this process, and the grader then records the check as failed.
run "a failed served audit does not stop the process" (fun () ->
    let probe = Probe()
    match start (fun () -> handle (library probe 1 -1) 8 CancellationToken.None) with
    | Ok t ->
        finishes t 5000 |> ignore
        Thread.Sleep 1000
        report "a failed served audit does not stop the process" (t.Status = TaskStatus.RanToCompletion) $"status {t.Status}"
    | Error ex -> report "a failed served audit does not stop the process" false (ex.GetType().Name))
