namespace Telemetry

open System

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

module Report =
    let private isValid (r: Reading) =
        r.Timestamp > 0L && not (Double.IsNaN r.Value)

    /// Summarizes the valid readings of each sensor at each site, sorted by site and then by sensor.
    let summarize (offsets: Map<string, float>) (threshold: float) (readings: Reading list) : SensorStats list =
        let valid = readings |> List.filter isValid
        let total = List.length valid

        valid
        |> List.groupBy (fun r -> r.Site, r.Sensor)
        |> List.map (fun ((site, sensor), rs) ->
            let offset = Map.tryFind sensor offsets |> Option.defaultValue 0.0
            let values = rs |> List.map (fun r -> if Map.containsKey sensor offsets then r.Value + offset else r.Value)

            { Site = site
              Sensor = sensor
              Count = List.length values
              Share = float (List.length values) / float total
              Mean = List.average values
              Max = List.max values
              Spikes = values |> List.pairwise |> List.filter (fun (a, b) -> b - a > threshold) |> List.length })
        |> List.sortBy (fun s -> s.Site, s.Sensor)

    /// Renders one line for each sensor.
    let render (stats: SensorStats list) : string =
        stats
        |> List.map (fun s ->
            sprintf "%s/%s count=%d share=%.4f mean=%.3f max=%.3f spikes=%d" s.Site s.Sensor s.Count s.Share s.Mean s.Max s.Spikes
            + "\n")
        |> String.concat ""
