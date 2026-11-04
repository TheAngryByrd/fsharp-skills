namespace Lib

open System
open System.Globalization

type Prices =
    static member Parse(text: string, currency: string) : decimal * string =
        match Decimal.TryParse(text.Trim(), NumberStyles.Number, CultureInfo.InvariantCulture) with
        | true, amount -> amount, currency
        | false, _ -> invalidArg (nameof text) $"Not a price: {text}"

    static member Parse(text: string) : decimal * string = Prices.Parse(text, "USD")
