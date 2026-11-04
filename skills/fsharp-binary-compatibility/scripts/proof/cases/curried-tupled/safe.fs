module Lib

let lineTotal (quantity: int) (unitPrice: decimal) : decimal =
    if quantity < 0 then invalidArg (nameof quantity) "Negative quantity"
    decimal quantity * unitPrice

let lineTotalOf (quantity: int, unitPrice: decimal) : decimal = lineTotal quantity unitPrice
