module Lib

type OrderLine = { Sku: string; Quantity: int }

let line (sku: string) (quantity: int) : OrderLine = { Sku = sku; Quantity = quantity }
