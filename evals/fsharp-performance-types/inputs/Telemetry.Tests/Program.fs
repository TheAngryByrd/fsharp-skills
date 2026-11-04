open Telemetry

let mutable failures = 0

let check name actual expected =
    if actual = expected then
        printfn "PASS %s" name
    else
        failures <- failures + 1
        printfn "FAIL %s\n  expected: %A\n  actual:   %A" name expected actual

let r site sensor ts value =
    { Site = site; Sensor = sensor; Timestamp = ts; Value = value }

let noOffsets = Map.empty

check "empty input gives no stats" (Report.summarize noOffsets 1.0 []) []

check
    "invalid readings are ignored"
    (Report.summarize noOffsets 1.0 [ r "n" "a" 0L 1.0; r "n" "a" 1L nan; r "n" "b" -5L 2.0 ])
    []

check
    "one sensor"
    (Report.summarize noOffsets 1.0 [ r "n" "a" 1L 1.0; r "n" "a" 2L 3.0; r "n" "a" 3L 2.0 ])
    [ { Site = "n"; Sensor = "a"; Count = 3; Share = 1.0; Mean = 2.0; Max = 3.0; Spikes = 1 } ]

check
    "stats are sorted by site, then sensor, and share counts only valid readings"
    (Report.summarize noOffsets 5.0 [ r "s" "a" 1L 1.0; r "n" "b" 2L 10.0; r "s" "a" 3L 20.0; r "n" "b" 4L nan ])
    [ { Site = "n"; Sensor = "b"; Count = 1; Share = 1.0 / 3.0; Mean = 10.0; Max = 10.0; Spikes = 0 }
      { Site = "s"; Sensor = "a"; Count = 2; Share = 2.0 / 3.0; Mean = 10.5; Max = 20.0; Spikes = 1 } ]

check
    "a spike compares with the previous valid reading of the same sensor at the same site"
    (Report.summarize noOffsets 2.0 [ r "n" "a" 1L 0.0; r "s" "a" 2L 100.0; r "n" "a" 3L nan; r "n" "a" 4L 3.0 ]
     |> List.map (fun s -> s.Site, s.Sensor, s.Spikes))
    [ "n", "a", 1; "s", "a", 0 ]

check
    "an offset applies to its sensor name at every site"
    (Report.summarize (Map.ofList [ "a", 10.0 ]) 100.0 [ r "n" "a" 1L 1.0; r "s" "a" 2L 2.0; r "s" "b" 3L 3.0 ]
     |> List.map (fun s -> s.Site, s.Sensor, s.Max))
    [ "n", "a", 11.0; "s", "a", 12.0; "s", "b", 3.0 ]

check
    "render writes one line for each sensor"
    (Report.render [ { Site = "n"; Sensor = "a"; Count = 2; Share = 0.5; Mean = 1.25; Max = 2.0; Spikes = 1 } ])
    "n/a count=2 share=0.5000 mean=1.250 max=2.000 spikes=1\n"

check "render of no stats is empty" (Report.render []) ""

exit (if failures = 0 then 0 else 1)
