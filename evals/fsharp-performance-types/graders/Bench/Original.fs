namespace Golden

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
    /// offsets holds a calibration offset for some sensor names. The offset applies at every site.
    /// A spike is a calibrated value that is more than threshold above the previous valid value of the same sensor at the same site.
    let summarize (offsets: Map<string, float>) (threshold: float) (readings: Reading list) : SensorStats list =
        let valid = readings |> Seq.filter isValid

        if Seq.isEmpty valid then
            []
        else
            let total = Seq.length valid
            let mutable groups = Map.empty

            for r in valid do
                let value =
                    match Map.tryFind r.Sensor offsets with
                    | Some offset -> r.Value + offset
                    | None -> r.Value

                let key = (r.Site, r.Sensor)

                let values =
                    match Map.tryFind key groups with
                    | Some vs -> vs @ [ value ]
                    | None -> [ value ]

                groups <- Map.add key values groups

            [ for KeyValue((site, sensor), values) in groups do
                  let mutable spikes = 0

                  for i in 1 .. List.length values - 1 do
                      if List.item i values - List.item (i - 1) values > threshold then
                          spikes <- spikes + 1

                  { Site = site
                    Sensor = sensor
                    Count = List.length values
                    Share = float (List.length values) / float total
                    Mean = List.average values
                    Max = List.max values
                    Spikes = spikes } ]
            |> List.sortBy (fun s -> s.Site, s.Sensor)

    /// Renders one line for each sensor.
    let render (stats: SensorStats list) : string =
        stats
        |> List.fold
            (fun acc s ->
                acc
                + sprintf
                    "%s/%s count=%d share=%.4f mean=%.3f max=%.3f spikes=%d\n"
                    s.Site
                    s.Sensor
                    s.Count
                    s.Share
                    s.Mean
                    s.Max
                    s.Spikes)
            ""
