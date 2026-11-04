module Lib

type OrderLine =
    { Sku: string
      Quantity: int
      Note: string option }

let describe (line: OrderLine) : string = $"{line.Quantity} x {line.Sku}"
