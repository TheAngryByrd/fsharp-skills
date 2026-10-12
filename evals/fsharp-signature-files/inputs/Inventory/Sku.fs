namespace Inventory

open System

/// A stock keeping unit: three upper-case letters, a dash, and four digits, for example ABC-1234.
type Sku = { Code: string }

/// A count of whole units. It is never negative.
type Quantity = Quantity of int

module Sku =
    let normalize (text: string) = text.Trim().ToUpperInvariant()

    let isValidCode (code: string) =
        code.Length = 8
        && code |> Seq.take 3 |> Seq.forall Char.IsAsciiLetterUpper
        && code[3] = '-'
        && code |> Seq.skip 4 |> Seq.forall Char.IsAsciiDigit

    /// Parses a SKU. Spaces around the text are removed and letters are made upper case.
    let tryParse (text: string) : Sku option =
        let code = normalize text
        if isValidCode code then Some { Code = code } else None

    /// The SKU text, for example ABC-1234.
    let value (sku: Sku) = sku.Code

module Quantity =
    /// Makes a quantity. Returns None for a negative count.
    let tryCreate (count: int) : Quantity option =
        if count < 0 then None else Some(Quantity count)

    /// The number of units.
    let value (Quantity count) = count

    let zero = Quantity 0

    let add (Quantity a) (Quantity b) = Quantity(a + b)
