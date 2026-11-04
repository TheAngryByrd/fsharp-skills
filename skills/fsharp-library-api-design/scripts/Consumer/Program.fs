open Lib

type Store() =
    interface IStore with
        member _.Get key = string key.Length

let name shape =
    match shape with
    | Circle _ -> "circle"
    | Square _ -> "square"

let doubled = List.map (Geometry.scale 2.0) [ { X = 1.0; Y = 2.0 } ]
printfn "%s %g" (name (Circle 1.0)) (Geometry.area (Square 3.0))
printfn "%g %g" doubled.Head.X (Geometry.double 2.0)
printfn "%d %s %d" (Geometry.count [ 1; 2; 3 ]) (Client(Store()).Send "hi") (Client(Store()).Total [ 4; 5 ])
