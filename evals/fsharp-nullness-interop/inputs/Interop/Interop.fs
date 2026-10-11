module Interop

open System
open System.IO
open System.Text.Json

type Settings = { Name: string; Retries: int }

/// Host of an absolute URI, or None when s is not an absolute URI.
let tryHost (s: string) : string option =
    match Uri.TryCreate(s, UriKind.Absolute) with
    | true, u -> Some u.Host
    | _ -> None

/// The "name" property. None when the property is missing or is JSON null.
let tryName (e: JsonElement) : string option =
    match e.TryGetProperty "name" with
    | true, p -> Some(p.GetString())
    | _ -> None

/// Value of the environment variable, or fallback when the variable is not set.
let envOr (name: string) (fallback: string) : string =
    let v = Environment.GetEnvironmentVariable name
    if isNull v then fallback else v

/// Message of the innermost exception.
let rec rootMessage (ex: exn) : string =
    if isNull ex.InnerException then ex.Message else rootMessage ex.InnerException

/// Messages of the exception chain, outer first, joined with " <- ".
let describe (ex: exn) : string =
    let rec go (e: exn) acc =
        if isNull e then List.rev acc else go e.InnerException (e.Message :: acc)
    go ex [] |> String.concat " <- "

/// Parent directory. None for a root path or a bare file name.
let tryParent (path: string) : string option =
    let dir = Path.GetDirectoryName path
    if String.IsNullOrEmpty dir then None else Some dir

/// First line of the reader, or None at end of input.
let tryFirstLine (reader: TextReader) : string option =
    let line = reader.ReadLine()
    if isNull line then None else Some line

/// Settings from JSON. Error "empty document" when the JSON is null.
let loadSettings (json: string) : Result<Settings, string> =
    let s = JsonSerializer.Deserialize<Settings> json
    if isNull (box s) then Error "empty document" else Ok s

/// Delay before retry attempt n (1-based): 2^(n-1) seconds, at most maxSeconds.
let retryDelay (maxSeconds: int) (attempt: int) : TimeSpan =
    TimeSpan.FromSeconds(min maxSeconds (pown 2 (attempt - 1)))

/// Request timeout in minutes.
let timeout (minutes: int) : TimeSpan = TimeSpan.FromMinutes minutes
