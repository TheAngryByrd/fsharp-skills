[<AutoOpen>]
module Prelude

let clamp (low: decimal) (high: decimal) (value: decimal) = max low (min high value)
