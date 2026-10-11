#load "Frames.fsx"

open System
open System.Threading.Tasks
open System.Threading.Tasks.Sources
open Frames

let report name (passed: bool) (detail: string) =
    Console.WriteLine((if passed then "PASS " else "FAIL ") + name + (if passed then "" else " [" + detail + "]"))

// Like a socket's pooled source: GetResult recycles the source, so a second GetResult on the same ValueTask throws.
type PooledSource(frames: int list, delayMs: int) =
    let mutable core = ManualResetValueTaskSourceCore<int>(RunContinuationsAsynchronously = true)
    let mutable remaining = frames
    member val StaleReads = 0 with get, set

    interface IFrameSource with
        member this.ReadAsync() =
            core.Reset()
            let version = core.Version
            let next = List.head remaining
            remaining <- List.tail remaining
            if delayMs = 0 then
                core.SetResult next
            else
                Task.Delay(delayMs).ContinueWith(fun (_: Task) -> core.SetResult next) |> ignore
            ValueTask<int>(this :> IValueTaskSource<int>, version)

    interface IValueTaskSource<int> with
        member this.GetResult(token) =
            if token <> core.Version then this.StaleReads <- this.StaleReads + 1
            let value = core.GetResult token
            core.Reset()
            value
        member _.GetStatus(token) = core.GetStatus token
        member _.OnCompleted(continuation, state, token, flags) = core.OnCompleted(continuation, state, token, flags)

let awaitObj (value: obj) : obj =
    let t =
        match value with
        | :? Task as t -> t
        | other -> other.GetType().GetMethod("AsTask").Invoke(other, [||]) :?> Task
    if not (t.Wait 5000) then failwith "timed out after 5 s"
    t.GetType().GetProperty("Result").GetValue t

let check name (expected: obj) (source: PooledSource) (call: unit -> obj) =
    try
        let actual = awaitObj (call ())
        let ok = actual = expected && source.StaleReads = 0
        report name ok $"result {actual}, stale reads {source.StaleReads}"
    with ex ->
        let inner = match ex with :? AggregateException as a -> a.InnerException | e -> e
        report name false $"threw {inner.GetType().Name}: {inner.Message}; stale reads {source.StaleReads}"

let source () = PooledSource([ 1; 2; 3 ], 5)
let s1 = source ()
check "sumFrames adds frames from a pooled ValueTask source" (box 6) s1 (fun () -> box (sumFrames s1 3))
let s2 = PooledSource([ 7 ], 5)
check "readWithTimeout returns a frame that arrives in time" (box (Some 7)) s2 (fun () -> box (readWithTimeout s2 1000))
let s3 = PooledSource([ 7 ], 0)
check "readWithTimeout returns a frame that is already complete" (box (Some 7)) s3 (fun () -> box (readWithTimeout s3 1000))
let s4 = PooledSource([ 7 ], 600)
let timer = System.Diagnostics.Stopwatch.StartNew()
check "readWithTimeout returns None after the timeout" (box None) s4 (fun () -> box (readWithTimeout s4 50))
report "readWithTimeout returns before the slow read completes" (timer.ElapsedMilliseconds < 400) $"returned after {timer.ElapsedMilliseconds} ms; the read takes 600 ms"
let s5 = PooledSource([ 9 ], 5)
check "readLabelled labels a valid frame" (box "cam: 9") s5 (fun () -> box (readLabelled s5 "cam"))
let s6 = PooledSource([ -4 ], 5)
check "readLabelled reports an invalid frame" (box "cam: invalid frame -4") s6 (fun () -> box (readLabelled s6 "cam"))
