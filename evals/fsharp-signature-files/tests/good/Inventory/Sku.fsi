namespace Inventory

/// A stock keeping unit: three upper-case letters, a dash, and four digits, for example ABC-1234.
type Sku

/// A count of whole units. It is never negative.
type Quantity

module Sku =
    /// Parses a SKU. Spaces around the text are removed and letters are made upper case.
    val tryParse: text: string -> Sku option

    /// The SKU text, for example ABC-1234.
    val value: sku: Sku -> string

module Quantity =
    /// Makes a quantity. Returns None for a negative count.
    val tryCreate: count: int -> Quantity option

    /// The number of units.
    val value: Quantity -> int

    val internal zero: Quantity

    val internal add: Quantity -> Quantity -> Quantity
