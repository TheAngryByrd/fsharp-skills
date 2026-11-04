// flags: --nooptimizationdata
module Lib

type OrderLine =
    { Sku: string
      Quantity: int
      Note: string option }

let line (sku: string) (quantity: int) : OrderLine = { Sku = sku; Quantity = quantity; Note = None }
