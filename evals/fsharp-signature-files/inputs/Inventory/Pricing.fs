namespace Inventory

open System

module Pricing =
    let roundToCents (amount: decimal) =
        Math.Round(amount, 2, MidpointRounding.ToEven)

    let describe (amount: decimal) = amount.ToString("0.00", Globalization.CultureInfo.InvariantCulture)

    /// The price of a stock line: the unit price times the quantity, rounded to cents.
    let lineTotal (unitPrice: decimal) (units: Quantity) =
        roundToCents (unitPrice * decimal (Quantity.value units))
