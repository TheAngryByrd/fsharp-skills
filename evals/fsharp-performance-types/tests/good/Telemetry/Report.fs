namespace Telemetry

open System
open System.Collections.Generic
open System.Globalization
open System.Text

type Reading =
    { Site: string
      Sensor: string
      Timestamp: int64
      Value: float }

type SensorStats =
    { Site: string
      Sensor: string
      Count: int
      Share: float
      Mean: float
      Max: float
      Spikes: int }

[<Sealed>]
type internal Acc(first: float) =
    member val Count = 1 with get, set
    member val Sum = 0.0 + first with get, set
    member val Max = first with get, set
    member val Last = first with get, set
    member val Spikes = 0 with get, set

module Report =
    let summarize (offsets: Map<string, float>) (threshold: float) (readings: Reading list) : SensorStats list =
        let offsetOf = Dictionary<string, float>(offsets, StringComparer.Ordinal)
        let accs = Dictionary<struct (string * string), Acc>()
        let mutable total = 0

        for r in readings do
            if r.Timestamp > 0L && not (Double.IsNaN r.Value) then
                total <- total + 1

                let value =
                    match offsetOf.TryGetValue r.Sensor with
                    | true, offset -> r.Value + offset
                    | _ -> r.Value

                let key = struct (r.Site, r.Sensor)

                match accs.TryGetValue key with
                | true, a ->
                    a.Count <- a.Count + 1
                    a.Sum <- a.Sum + value
                    if value > a.Max then a.Max <- value
                    if value - a.Last > threshold then a.Spikes <- a.Spikes + 1
                    a.Last <- value
                | _ -> accs[key] <- Acc value

        let stats = Array.zeroCreate<SensorStats> accs.Count
        let mutable i = 0

        for kv in accs do
            let a = kv.Value
            let struct (site, sensor) = kv.Key

            stats[i] <-
                { Site = site
                  Sensor = sensor
                  Count = a.Count
                  Share = float a.Count / float total
                  Mean = a.Sum / float a.Count
                  Max = a.Max
                  Spikes = a.Spikes }

            i <- i + 1

        Array.sortInPlaceWith
            (fun (x: SensorStats) (y: SensorStats) ->
                match String.CompareOrdinal(x.Site, y.Site) with
                | 0 -> String.CompareOrdinal(x.Sensor, y.Sensor)
                | c -> c)
            stats

        List.ofArray stats

    let render (stats: SensorStats list) : string =
        let inv = CultureInfo.InvariantCulture
        let sb = StringBuilder()

        for s in stats do
            sb
                .Append(s.Site)
                .Append('/')
                .Append(s.Sensor)
                .Append(" count=")
                .Append(s.Count.ToString(inv))
                .Append(" share=")
                .Append(s.Share.ToString("F4", inv))
                .Append(" mean=")
                .Append(s.Mean.ToString("F3", inv))
                .Append(" max=")
                .Append(s.Max.ToString("F3", inv))
                .Append(" spikes=")
                .Append(s.Spikes.ToString(inv))
                .Append('\n')
            |> ignore

        sb.ToString()
