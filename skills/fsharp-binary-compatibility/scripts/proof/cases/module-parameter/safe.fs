module Lib

open System
open System.Globalization

type PriceError =
    | Negative of amount: decimal
    | NotAPrice of raw: string

let parsePriceIn (currency: string) (text: string) : Result<decimal * string, PriceError> =
    match Decimal.TryParse(text.Trim(), NumberStyles.Number, CultureInfo.InvariantCulture) with
    | true, amount when amount >= 0M -> Ok(amount, currency)
    | true, amount -> Error(Negative amount)
    | false, _ -> Error(NotAPrice text)

let parsePrice (text: string) : Result<decimal * string, PriceError> = parsePriceIn "USD" text
