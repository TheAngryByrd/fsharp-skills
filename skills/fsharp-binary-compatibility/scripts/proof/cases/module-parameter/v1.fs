module Lib

open System
open System.Globalization

type PriceError =
    | Negative of amount: decimal
    | NotAPrice of raw: string

let parsePrice (text: string) : Result<decimal * string, PriceError> =
    match Decimal.TryParse(text.Trim(), NumberStyles.Number, CultureInfo.InvariantCulture) with
    | true, amount when amount >= 0M -> Ok(amount, "USD")
    | true, amount -> Error(Negative amount)
    | false, _ -> Error(NotAPrice text)
