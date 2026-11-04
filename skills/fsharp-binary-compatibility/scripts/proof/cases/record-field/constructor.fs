module Lib

type OrderLine =
    { Sku: string
      Quantity: int
      Note: string option }

    new(sku: string, quantity: int) = { Sku = sku; Quantity = quantity; Note = None }

let describe (line: OrderLine) : string = $"{line.Quantity} x {line.Sku}"
