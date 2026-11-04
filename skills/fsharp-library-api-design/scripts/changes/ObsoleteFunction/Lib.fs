// expect-source-fs: FS0044
// expect-source-cs: CS0618
// expect-binary-fs: same
// expect-binary-cs: same
// expect-package-validation: ok

namespace Lib

type Shape =
    | Circle of radius: float
    | Square of side: float

type Point = { X: float; Y: float }

type IStore =
    abstract Get: key: string -> string

module Geometry =
    let area shape =
        match shape with
        | Circle r -> 3.0 * r * r
        | Square s -> s * s

    [<System.Obsolete("Use scaleBy.")>]
    let scale (factor: float) (point: Point) = { X = point.X * factor; Y = point.Y * factor }

    let scaleBy (factor: float) (point: Point) = { X = point.X * factor; Y = point.Y * factor }

    let inline double (x: float) = x * 2.0

    let count (items: int list) = List.length items

type Client(store: IStore) =
    member _.Total(values: int list) : int = List.sum values

    member _.Send(message: string) : string = store.Get message + ":" + message
