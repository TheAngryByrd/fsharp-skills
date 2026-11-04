// flags: --nooptimizationdata
module Lib

let inline tax (amount: decimal) : decimal = amount * 0.20M
