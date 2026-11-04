module Bench

open System
open System.Diagnostics
open System.Globalization
open Telemetry

let summarize: Map<string, float> -> float -> Reading list -> SensorStats list = Report.summarize
let render: SensorStats list -> string = Report.render

let threshold = 4.0

let toGoldenReading (r: Reading) : Golden.Reading =
    { Site = r.Site; Sensor = r.Sensor; Timestamp = r.Timestamp; Value = r.Value }

let toGoldenStats (s: SensorStats) : Golden.SensorStats =
    { Site = s.Site; Sensor = s.Sensor; Count = s.Count; Share = s.Share; Mean = s.Mean; Max = s.Max; Spikes = s.Spikes }

let ofGoldenStats (s: Golden.SensorStats) : SensorStats =
    { Site = s.Site; Sensor = s.Sensor; Count = s.Count; Share = s.Share; Mean = s.Mean; Max = s.Max; Spikes = s.Spikes }

let sitePool = [| "north"; "North"; "south"; "east-1"; "east_1"; "East1"; "west"; "WEST"; "plant.a"; "Plant.b" |]
let sensorPool = [| "pump"; "Pump"; "PUMP"; "valve"; "Valve"; "boiler"; "fan-"; "fan_"; "Fan" |]

let sensorName i =
    sensorPool[i % sensorPool.Length] + string (i / sensorPool.Length)

let offsetsFor (sensorsPerSite: int) =
    Map.ofList [ for i in 0..2 .. sensorsPerSite - 1 -> sensorName i, float (i % 7) - 3.25 ]

let generate (seed: int) (sites: int) (sensorsPerSite: int) (count: int) (special: bool) =
    let rng = Random seed
    let level = Array2D.init sites sensorsPerSite (fun _ _ -> rng.NextDouble() * 100.0 - 20.0)

    [ for i in 1..count do
          let site = rng.Next sites
          let sensor = rng.Next sensorsPerSite
          level[site, sensor] <- level[site, sensor] + (rng.NextDouble() - 0.45) * 8.0
          let roll = rng.Next 200

          let value =
              match roll with
              | 0
              | 1 -> nan
              | 2 when special -> infinity
              | 3 when special -> -infinity
              | _ -> Math.Round(level[site, sensor], rng.Next 5)

          { Site = sitePool[site]
            Sensor = sensorName sensor
            Timestamp =
              (match roll with
               | 4 -> 0L
               | 5 -> -int64 i
               | _ when special -> int64 (rng.Next(1, count + 1))
               | _ -> int64 i)
            Value = value } ]

let report ok (name: string) (detail: string) =
    let line = Text.RegularExpressions.Regex.Replace(detail, @"\s*\r?\n\s*", " ")
    printfn "%s %s [%s]" (if ok then "PASS" else "FAIL") name line

let sameStat (x: SensorStats) (y: SensorStats) =
    let close (a: float) (b: float) tolerance =
        if a = 0.0 && b = 0.0 then
            Double.IsNegative a = Double.IsNegative b
        elif Double.IsFinite a && Double.IsFinite b then
            abs (a - b) <= tolerance * max 1.0 (abs b)
        else
            a = b || (Double.IsNaN a && Double.IsNaN b)

    x.Site = y.Site
    && x.Sensor = y.Sensor
    && x.Count = y.Count
    && x.Spikes = y.Spikes
    && close x.Max y.Max 0.0
    && close x.Mean y.Mean 1e-9
    && close x.Share y.Share 1e-12

let firstDifference (actual: SensorStats list) (expected: SensorStats list) =
    if actual.Length <> expected.Length then
        Some $"{actual.Length} stats, expected {expected.Length}"
    else
        List.zip actual expected
        |> List.tryFind (fun (x, y) -> not (sameStat x y))
        |> Option.map (fun (x, y) -> $"got %A{x}, expected %A{y}")

let tryRun f =
    try
        Ok(f ())
    with ex ->
        Error(ex.GetType().Name + ": " + ex.Message)

let summarizeFailure offsets (readings: Reading list) =
    let expected =
        Golden.Report.summarize offsets threshold (List.map toGoldenReading readings)
        |> List.map ofGoldenStats

    match tryRun (fun () -> summarize offsets threshold readings) with
    | Ok actual -> firstDifference actual expected
    | Error e -> Some $"summarize threw {e}"

let shrink (fails: Reading list -> bool) (readings: Reading list) =
    let mutable current = List.toArray readings
    let mutable chunk = max 1 (current.Length / 2)
    let mutable budget = 300
    let deadline = Stopwatch.StartNew()
    let inTime () = budget > 0 && deadline.Elapsed < TimeSpan.FromSeconds 30.0

    while chunk >= 1 && inTime () do
        let mutable start = 0
        let mutable removed = false

        while start < current.Length && inTime () do
            let candidate = Array.append current[.. start - 1] current[start + chunk ..]
            budget <- budget - 1

            if candidate.Length < current.Length && fails (List.ofArray candidate) then
                current <- candidate
                removed <- true
            else
                start <- start + chunk

        if not removed then chunk <- chunk / 2

    List.ofArray current

let describe (readings: Reading list) =
    let shown =
        readings
        |> List.truncate 6
        |> List.map (fun r -> $"{r.Site}/{r.Sensor} t={r.Timestamp} v={r.Value.ToString(CultureInfo.InvariantCulture)}")
        |> String.concat "; "

    $"{readings.Length} readings: {shown}"

let renderFailure (stats: SensorStats list) =
    let expectedText = Golden.Report.render (List.map toGoldenStats stats)

    match tryRun (fun () -> render stats) with
    | Ok text when text = expectedText -> None
    | Ok text ->
        let i =
            Seq.zip text expectedText
            |> Seq.tryFindIndex (fun (a, b) -> a <> b)
            |> Option.defaultValue (min text.Length expectedText.Length)

        let around (s: string) =
            let start = max 0 (i - 20)
            s.Substring(start, min 50 (s.Length - start))

        Some $"render differs at char {i}: got '{around text}', expected '{around expectedText}'"
    | Error e -> Some $"render threw {e}"

let correctness (bigOffsets: Map<string, float>) (big: Reading list) =
    let cases =
        [ "empty", Map.empty, []
          "all invalid", Map.empty, [ { Site = "n"; Sensor = "a"; Timestamp = 0L; Value = 1.0 }; { Site = "n"; Sensor = "b"; Timestamp = 2L; Value = nan } ]
          "one reading", Map.ofList [ "solo", 1.5 ], [ { Site = "n"; Sensor = "solo"; Timestamp = 1L; Value = -2.5 } ]
          "negative zero", Map.empty, [ { Site = "n"; Sensor = "z"; Timestamp = 1L; Value = -0.0 } ] ]
        @ [ for seed in 1..6 -> $"seed {seed}", offsetsFor (2 + seed * 3), generate seed (1 + seed % 10) (2 + seed * 3) (seed * 400) (seed % 2 = 0) ]
        @ [ "production size", bigOffsets, big ]

    let summarizeError =
        cases
        |> List.tryPick (fun (name, offsets, readings) ->
            summarizeFailure offsets readings
            |> Option.map (fun d ->
                let minimal = shrink (fun rs -> (summarizeFailure offsets rs).IsSome) readings
                let minimalDifference = defaultArg (summarizeFailure offsets minimal) d
                $"{name}: {d}. Smallest failing input found: {describe minimal}: {minimalDifference}"))

    let renderError =
        cases
        |> List.tryPick (fun (name, offsets, readings) ->
            let stats =
                Golden.Report.summarize offsets threshold (List.map toGoldenReading readings)
                |> List.map ofGoldenStats

            renderFailure stats |> Option.map (fun d -> $"{name}: {d}"))

    report summarizeError.IsNone "summarize gives the same stats as the original code" (defaultArg summarizeError "")
    report renderError.IsNone "render gives the same text as the original code under the de-DE culture" (defaultArg renderError "")
    summarizeError.IsNone, renderError.IsNone

let allocatedBy (f: unit -> 'a) =
    let before = GC.GetTotalAllocatedBytes true
    let result = f ()
    GC.GetTotalAllocatedBytes true - before, result

let timed (f: unit -> 'a) =
    GC.Collect()
    let sw = Stopwatch.StartNew()
    let result = f ()
    sw.ElapsedTicks, result

let median (samples: ResizeArray<int64>) =
    let a = samples.ToArray()
    Array.sortInPlace a
    a[a.Length / 2]

let measure
    (name: string)
    (prepare: int -> 'input * 'expected)
    (agent: 'input -> 'a)
    (reference: 'input -> 'a)
    (validate: 'expected -> 'a -> string option)
    =
    let allocationCheck = $"{name} allocates no more than 2 x the reference + 64 KB"
    let timeCheck = $"{name} median run time is no more than 3 x the reference + 1 ms"
    let mutable call = 0

    let next () =
        call <- call + 1
        prepare call

    let check (label: string) (expected: 'expected) (result: 'a) =
        match validate expected result with
        | Some d -> failwith $"the {label} call gave a different result: {d}"
        | None -> ()

    let outcome =
        try
            for i in 1..3 do
                let input, expected = next ()
                check $"warm-up {i}" expected (agent input)
                reference input |> ignore

            let input, expected = next ()
            let agentBytes, measured = allocatedBy (fun () -> agent input)
            check "allocation" expected measured
            let referenceBytes, _ = allocatedBy (fun () -> reference input)
            let agentTimes = ResizeArray()
            let referenceTimes = ResizeArray()
            let deadline = Stopwatch.StartNew()
            let mutable rounds = 0

            while rounds < 15 && deadline.Elapsed < TimeSpan.FromSeconds 60.0 do
                let input, expected = next ()

                let timeAgent () =
                    let ticks, result = timed (fun () -> agent input)
                    check $"timed {rounds + 1}" expected result
                    agentTimes.Add ticks

                let timeReference () = referenceTimes.Add(fst (timed (fun () -> reference input)))

                if rounds % 2 = 0 then
                    timeAgent ()
                    timeReference ()
                else
                    timeReference ()
                    timeAgent ()

                rounds <- rounds + 1

            Ok(agentBytes, referenceBytes, median agentTimes, median referenceTimes, rounds)
        with ex ->
            Error $"threw {ex.GetType().Name}: {ex.Message}"

    match outcome with
    | Ok(agentBytes, referenceBytes, a, r, rounds) ->
        let limit = 2L * referenceBytes + 65536L
        let ms (t: int64) = float t * 1000.0 / float Stopwatch.Frequency
        let limitTicks = 3L * r + Stopwatch.Frequency / 1000L
        report (agentBytes <= limit) allocationCheck $"agent {agentBytes} bytes, reference {referenceBytes} bytes, limit {limit} bytes"
        report (a <= limitTicks) timeCheck $"agent %.2f{ms a} ms, reference %.2f{ms r} ms, limit %.2f{ms limitTicks} ms, {rounds} rounds"
    | Error detail ->
        report false allocationCheck detail
        report false timeCheck detail

[<EntryPoint>]
let main argv =
    CultureInfo.CurrentCulture <- CultureInfo "de-DE"
    CultureInfo.CurrentUICulture <- CultureInfo "de-DE"
    let big = generate 42 10 100 200_000 false
    let offsets = offsetsFor 100
    let summarizeOk, renderOk = correctness offsets big

    if summarizeOk then
        measure
            "summarize of 200,000 readings"
            (fun call ->
                let batch = generate (1000 + call) 10 100 200_000 false
                batch, Fast.Report.summarize offsets threshold batch)
            (summarize offsets threshold)
            (Fast.Report.summarize offsets threshold)
            (fun expected actual -> firstDifference actual expected)
    else
        printfn "SKIP summarize of 200,000 readings: the output differs from the original code"

    if renderOk then
        measure
            "render of 1,000 sensors"
            (fun call ->
                let stats = Fast.Report.summarize offsets threshold (generate (2000 + call) 10 100 50_000 false)
                stats, Golden.Report.render (List.map toGoldenStats stats))
            render
            Fast.Report.render
            (fun expected text -> if text = expected then None else Some "render text differs")
    else
        printfn "SKIP render of 1,000 sensors: the output differs from the original code"

    printfn "BENCH DONE %s" argv[0]
    0
