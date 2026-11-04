module Lib

type OrderLine =
    { Sku: string
      Quantity: int
      Note: string option }

let sample: OrderLine = { Sku = "A-1"; Quantity = 2; Note = None }
