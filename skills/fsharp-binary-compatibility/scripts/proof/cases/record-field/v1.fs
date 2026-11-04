module Lib

type OrderLine = { Sku: string; Quantity: int }

let describe (line: OrderLine) : string = $"{line.Quantity} x {line.Sku}"
