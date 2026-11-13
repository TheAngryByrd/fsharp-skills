namespace Sample

type Email = { Value: string }

type EmailError = | NotOneAtSign of count: int

[<RequireQualifiedAccess>]
module Email =
    let normalize (input: string) = input.Trim()

    let atSigns (input: string) = input.Split('@').Length - 1

    let isValid (input: string) = atSigns input = 1

    /// Implementation text that callers never see.
    let create (input: string) =
        let text = normalize input
        if isValid text then Ok { Value = text } else Error(NotOneAtSign(atSigns text))

    /// The text of the email address.
    let value (email: Email) = email.Value

[<RequireQualifiedAccess>]
type Status =
    | Active
    | Closed

type Ledger() =
    static member (+)(ledger: Ledger, _entries: int) = ledger

    interface System.IDisposable with
        member _.Dispose() = ()
