module Lib

open System
open System.Globalization

let parsePrice (text: string) (currency: string) : Result<decimal * string, string> =
    match Decimal.TryParse(text.Trim(), NumberStyles.Number, CultureInfo.InvariantCulture) with
    | true, amount when amount >= 0M -> Ok(amount, currency)
    | true, _ -> Error $"Negative price: {text}"
    | false, _ -> Error $"Not a price: {text}"
