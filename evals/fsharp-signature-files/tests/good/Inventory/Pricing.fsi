namespace Inventory

module Pricing =
    val internal roundToCents: amount: decimal -> decimal

    /// The price of a stock line: the unit price times the quantity, rounded to cents.
    val lineTotal: unitPrice: decimal -> units: Quantity -> decimal
