module Lib

type OrderLine = { Sku: string; Quantity: int }

type NotedLine = { Line: OrderLine; Note: string option }

let describe (line: OrderLine) : string = $"{line.Quantity} x {line.Sku}"

let describeNoted (noted: NotedLine) : string =
    match noted.Note with
    | Some note -> $"{describe noted.Line} ({note})"
    | None -> describe noted.Line
