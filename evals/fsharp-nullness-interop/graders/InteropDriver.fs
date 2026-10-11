module Driver

open System
open System.IO
open System.Text.Json
open Interop

let sigTryHost: string -> string option = tryHost
let sigTryName: JsonElement -> string option = tryName
let sigEnvOr: string -> string -> string = envOr
let sigRootMessage: exn -> string = rootMessage
let sigDescribe: exn -> string = describe
let sigTryParent: string -> string option = tryParent
let sigTryFirstLine: TextReader -> string option = tryFirstLine
let sigLoadSettings: string -> Result<Settings, string> = loadSettings
let sigRetryDelay: int -> int -> TimeSpan = retryDelay
let sigTimeout: int -> TimeSpan = timeout

let quote (o: string option) =
    match o with
    | Some v -> $"Some \"{v}\""
    | None -> "None"

let show (key: string) (f: unit -> string) =
    let value =
        try f () with ex -> $"EXN {ex.GetType().Name}"
    Console.WriteLine $"{key} | {value}"

let json (text: string) = (JsonDocument.Parse text).RootElement

[<EntryPoint>]
let main _ =
    let root = if OperatingSystem.IsWindows() then @"C:\" else "/"
    let chain = exn ("outer", exn ("middle", exn "inner"))
    Environment.SetEnvironmentVariable("NULLNESS_EVAL_SET", "value")
    show "tryHost-valid" (fun () -> quote (tryHost "https://example.com/a"))
    show "tryHost-invalid" (fun () -> quote (tryHost "not a uri"))
    show "tryName-value" (fun () -> quote (tryName (json """{"name":"Ada"}""")))
    show "tryName-null" (fun () -> quote (tryName (json """{"name":null}""")))
    show "tryName-missing" (fun () -> quote (tryName (json """{}""")))
    show "envOr-unset" (fun () -> envOr "NULLNESS_EVAL_UNSET" "fallback")
    show "envOr-set" (fun () -> envOr "NULLNESS_EVAL_SET" "fallback")
    show "rootMessage-single" (fun () -> rootMessage (exn "only"))
    show "rootMessage-chain" (fun () -> rootMessage chain)
    show "describe-single" (fun () -> describe (exn "only"))
    show "describe-chain" (fun () -> describe chain)
    show "tryParent-root" (fun () -> quote (tryParent root))
    show "tryParent-bare" (fun () -> quote (tryParent "file.txt"))
    show "tryParent-nested" (fun () -> quote (tryParent (Path.Combine("a", "b.txt"))))
    show "tryFirstLine-empty" (fun () -> quote (tryFirstLine (new StringReader "")))
    show "tryFirstLine-text" (fun () -> quote (tryFirstLine (new StringReader "x\ny")))
    show "loadSettings-null" (fun () ->
        match loadSettings "null" with
        | Ok s -> $"Ok {s.Name} {s.Retries}"
        | Error e -> $"Error {e}")
    show "loadSettings-value" (fun () ->
        match loadSettings """{"Name":"svc","Retries":3}""" with
        | Ok s -> $"Ok {s.Name} {s.Retries}"
        | Error e -> $"Error {e}")
    show "retryDelay-30-1" (fun () -> (retryDelay 30 1).ToString())
    show "retryDelay-30-4" (fun () -> (retryDelay 30 4).ToString())
    show "retryDelay-5-6" (fun () -> (retryDelay 5 6).ToString())
    show "timeout-2" (fun () -> (timeout 2).ToString())
    0
