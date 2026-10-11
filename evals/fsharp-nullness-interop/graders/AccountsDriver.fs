module Driver

open System
open System.IO
open System.Text.Json
open Accounts

let sigDisplayName: JsonElement -> string = displayName
let sigConfigPath: unit -> string = configPath
let sigReadLines: TextReader -> string list = readLines
let sigRootMessage: exn -> string = rootMessage
let sigTryCountry: JsonElement -> string option = tryCountry
let sigTryNick: JsonElement -> string option = tryNick

let quote (o: string option) =
    match o with
    | Some v -> $"Some \"{v}\""
    | None -> "None"

let show (key: string) (f: unit -> string) =
    let value =
        try f () with ex -> $"EXN {ex.GetType().Name}"
    Console.WriteLine $"{key} | {value}"

let json (text: string) = (JsonDocument.Parse text).RootElement

let email (user: JsonElement) =
    match tryEmail user with
    | Some v ->
        match box v with
        | null -> "Some null"
        | _ -> $"Some \"{v}\""
    | None -> "None"

[<EntryPoint>]
let main _ =
    Environment.SetEnvironmentVariable("APP_CONFIG", null)
    show "displayName-value" (fun () -> displayName (json """{"display":"Ada L","login":"ada"}"""))
    show "displayName-empty" (fun () ->
        let name = displayName (json """{"display":"","login":"ada"}""")
        $"\"{name}\"")
    show "displayName-null" (fun () -> displayName (json """{"display":null,"login":"ada"}"""))
    // The task allows tryEmail to change from (string | null) option to string option, so only its parameter type is checked here.
    show "tryEmail-parameter" (fun () ->
        match Type.GetType "Accounts, Accounts" with
        | null -> "module not found"
        | accounts ->
            match accounts.GetMethod "tryEmail" with
            | null -> "method not found"
            | m -> m.GetParameters() |> Array.map (fun p -> p.ParameterType.Name) |> String.concat ",")
    show "tryEmail-value" (fun () -> email (json """{"email":"a@b.c"}"""))
    show "tryEmail-null" (fun () -> email (json """{"email":null}"""))
    show "configPath-unset" (fun () -> configPath ())
    Environment.SetEnvironmentVariable("APP_CONFIG", "custom.json")
    show "configPath-set" (fun () -> configPath ())
    show "readLines-text" (fun () -> readLines (new StringReader "a\nb") |> String.concat ",")
    show "readLines-empty" (fun () -> readLines (new StringReader "") |> List.length |> string)
    show "rootMessage-single" (fun () -> rootMessage (exn "only"))
    show "rootMessage-chain" (fun () -> rootMessage (exn ("outer", exn "inner")))
    show "tryCountry-value" (fun () -> quote (tryCountry (json """{"country":"nz"}""")))
    show "tryCountry-null" (fun () -> quote (tryCountry (json """{"country":null}""")))
    show "tryNick-value" (fun () -> quote (tryNick (json """{"nick":"al"}""")))
    show "tryNick-null" (fun () -> quote (tryNick (json """{"nick":null}""")))
    0
