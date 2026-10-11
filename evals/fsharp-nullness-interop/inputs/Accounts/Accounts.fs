module Accounts

open System
open System.IO
open System.Text.Json

/// Display name of a user document. An empty "display" is kept as "".
/// Falls back to the "login" property when "display" is JSON null.
let displayName (user: JsonElement) : string =
    string (user.GetProperty("display").GetString())

/// Email of a user document, or None when "email" is JSON null.
let tryEmail (user: JsonElement) =
    Some(user.GetProperty("email").GetString())

/// Path of the configuration file. "app.json" when APP_CONFIG is not set.
let configPath () : string =
    Environment.GetEnvironmentVariable "APP_CONFIG" |> nonNull

/// Lines of the reader until end of input.
let readLines (reader: TextReader) : string list =
    let rec go acc =
        let line: string = Unchecked.nonNull (reader.ReadLine())
        if obj.ReferenceEquals(line, null) then List.rev acc else go (line :: acc)
    go []

/// Message of the innermost exception.
let rec rootMessage (ex: exn) : string =
    let inner: exn = Unchecked.nonNull ex.InnerException
    if obj.ReferenceEquals(inner, null) then ex.Message else rootMessage inner

/// Country of an address document, upper case. None when "country" is JSON null.
let tryCountry (address: JsonElement) : string option =
    address.GetProperty("country").GetString()
    |> Option.ofObj
    |> Option.map (fun c -> c.ToUpperInvariant())

/// Nickname of a user document, or None when "nick" is JSON null.
let tryNick (user: JsonElement) : string option =
    match user.GetProperty("nick").GetString() with
    | null -> None
    | nick -> Some(string nick)
