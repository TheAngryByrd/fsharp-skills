#r "nuget: FsToolkit.ErrorHandling, 5.2.0"
#r "nuget: Microsoft.Extensions.Configuration.Binder, 10.0.0"
#r "nuget: Microsoft.Extensions.Options.ConfigurationExtensions, 10.0.0"
#r "nuget: Microsoft.Extensions.DependencyInjection, 10.0.0"

open System
open System.Collections.Generic
open FsToolkit.ErrorHandling
open Microsoft.Extensions.Configuration
open Microsoft.Extensions.DependencyInjection
open Microsoft.Extensions.Options

let mutable failures = 0

let expect name (expected: string) (actual: string) =
    if expected = actual then
        printfn "ok    %s -> %s" name actual
    else
        failures <- failures + 1
        printfn "FAIL  %s\n      expected: %s\n      actual:   %s" name expected actual

let outcome f =
    try
        match box (f ()) with
        | null -> "null"
        | value -> Text.RegularExpressions.Regex.Replace(sprintf "%A" value, @"\s+", " ")
    with e ->
        $"throws {e.GetType().Name}"

let config (pairs: (string * string) list) =
    ConfigurationBuilder()
        .AddInMemoryCollection(pairs |> List.map KeyValuePair)
        .Build()

[<CLIMutable>]
type RetryDto = { Attempts: string }

[<CLIMutable>]
type MailSettingsDto =
    { Host: string
      Port: string
      From: string
      Recipients: string[]
      Retry: RetryDto }

type RetrySettings = { Attempts: int }

type MailSettings =
    { Host: string
      Port: int
      From: string
      Recipients: string list
      Retry: RetrySettings option }

module MailSettings =
    let private required key (value: string) =
        if String.IsNullOrWhiteSpace value then Error $"{key} is required" else Ok value

    let private wholeNumber key (value: string) =
        match Int32.TryParse(value, Globalization.NumberStyles.Integer, Globalization.CultureInfo.InvariantCulture) with
        | true, number -> Ok number
        | false, _ -> Error $"{key} must be a whole number, got '{value}'"

    let private port (value: string) =
        if String.IsNullOrWhiteSpace value then
            Error "Port is required"
        else
            wholeNumber "Port" value
            |> Result.bind (fun number ->
                if number < 1 || number > 65535 then Error $"Port must be 1 to 65535, got {number}" else Ok number)

    let private retry (dto: RetryDto) =
        if isNull (box dto) || String.IsNullOrWhiteSpace dto.Attempts then
            Ok None
        else
            wholeNumber "Retry:Attempts" dto.Attempts
            |> Result.bind (fun attempts ->
                if attempts < 1 then Error $"Retry:Attempts must be 1 or more, got {attempts}" else Ok(Some { Attempts = attempts }))

    let parse (dto: MailSettingsDto) : Result<MailSettings, string list> =
        match Option.ofObj (box dto) with
        | None -> Error [ "the Mail section is missing" ]
        | Some _ ->
            validation {
                let! host = required "Host" dto.Host
                and! port = port dto.Port
                and! from = required "From" dto.From
                and! retry = retry dto.Retry
                return
                    { Host = host
                      Port = port
                      From = from
                      Recipients = dto.Recipients |> Option.ofObj |> Option.map List.ofArray |> Option.defaultValue []
                      Retry = retry }
            }

type MailSettingsValidator() =
    interface IValidateOptions<MailSettingsDto> with
        member _.Validate(_, dto) =
            match MailSettings.parse dto with
            | Ok _ -> ValidateOptionsResult.Success
            | Error errors -> ValidateOptionsResult.Fail errors

type ILogger =
    abstract Info: string -> unit

type IProvideLogger =
    abstract Logger: ILogger

type IProvideMailSettings =
    abstract MailSettings: MailSettings

module Log =
    let info (env: #IProvideLogger) (message: string) = env.Logger.Info message

module Mail =
    let route (env: #IProvideMailSettings) (recipient: string) =
        let settings = env.MailSettings
        let attempts = settings.Retry |> Option.map _.Attempts |> Option.defaultValue 1
        $"{settings.From} -> {recipient} via {settings.Host}:{settings.Port} x{attempts}"

let notify env (recipient: string) =
    let route = Mail.route env recipient
    Log.info env route
    route

type IAppEnvironment =
    inherit IProvideLogger
    inherit IProvideMailSettings

type AppEnvironment(services: IServiceProvider) =
    interface IAppEnvironment with
        member _.Logger = services.GetRequiredService<ILogger>()
        member _.MailSettings = services.GetRequiredService<MailSettings>()

let consoleLogger =
    { new ILogger with
        member _.Info message = printfn "      log: %s" message }

let compose (configuration: IConfiguration) =
    let services = ServiceCollection()
    services.AddOptions<MailSettingsDto>().Bind(configuration.GetSection "Mail").ValidateOnStart() |> ignore
    services.AddSingleton<IValidateOptions<MailSettingsDto>, MailSettingsValidator>() |> ignore
    services.AddSingleton<MailSettings>(fun sp ->
        match MailSettings.parse (sp.GetRequiredService<IOptions<MailSettingsDto>>().Value) with
        | Ok settings -> settings
        | Error errors -> invalidOp (String.concat "; " errors))
    |> ignore
    services.AddSingleton<ILogger>(consoleLogger) |> ignore
    services.AddTransient<IAppEnvironment, AppEnvironment>() |> ignore
    services.BuildServiceProvider()

let composeDirect (configuration: IConfiguration) =
    let settings =
        match configuration.GetSection("Mail").Get<MailSettingsDto>() |> MailSettings.parse with
        | Ok settings -> settings
        | Error errors -> failwithf "Invalid Mail settings:\n  %s" (String.concat "\n  " errors)

    let services = ServiceCollection()
    services.AddSingleton<MailSettings>(settings) |> ignore
    services.AddSingleton<ILogger>(consoleLogger) |> ignore
    services.AddTransient<IAppEnvironment, AppEnvironment>() |> ignore
    services.BuildServiceProvider()

let start (provider: IServiceProvider) =
    provider.GetRequiredService<IStartupValidator>().Validate()
    provider.GetRequiredService<IAppEnvironment>()

let validationFailures (error: exn) =
    match error with
    | :? OptionsValidationException as e -> List.ofSeq e.Failures
    | :? AggregateException as e ->
        [ for inner in e.InnerExceptions do
              match inner with
              | :? OptionsValidationException as o -> yield! o.Failures
              | other -> yield other.Message ]
    | other -> [ other.Message ]

printfn "Binder rules for [<CLIMutable>] records"

[<CLIMutable>]
type OptionDto = { Nick: string option }

[<CLIMutable>]
type ListDto = { Codes: string list }

[<CLIMutable>]
type IntDto = { Count: int }

type PlainDto = { Name: string; Count: int }

[<CLIMutable>]
type DecimalDto = { Rate: decimal }

[<CLIMutable>]
type NullableDto = { Limit: Nullable<int> }

[<CLIMutable>]
type ReadOnlyListDto = { Items: IReadOnlyList<string> }

let errorMessage f =
    try
        f () |> ignore
        "no error"
    with e ->
        e.Message

expect "string option, key present" "{ Nick = None }" (outcome (fun () -> (config [ ("Nick", "ann") ]).Get<OptionDto>()))
expect "string list, key present" "throws InvalidOperationException" (outcome (fun () -> (config [ ("Codes:0", "a") ]).Get<ListDto>()))
expect "string list, key absent" "{ Codes = null }" (outcome (fun () -> (config [ ("Other", "x") ]).Get<ListDto>()))
expect "int, key absent" "{ Count = 0 }" (outcome (fun () -> (config [ ("Other", "x") ]).Get<IntDto>()))
expect "int, key not a number" "throws InvalidOperationException" (outcome (fun () -> (config [ ("Count", "ten") ]).Get<IntDto>()))
expect "Nullable<int>, key absent" "{ Limit = null }" (outcome (fun () -> (config [ ("Other", "x") ]).Get<NullableDto>()))
expect "Nullable<int>, key not a number" "throws InvalidOperationException" (outcome (fun () -> (config [ ("Limit", "ten") ]).Get<NullableDto>()))
expect "string[], key present" "[|\"a\"; \"b\"|]" (outcome (fun () -> (config [ "Recipients:0", "a"; "Recipients:1", "b" ]).Get<MailSettingsDto>().Recipients))
expect "nested record, section absent" "null" (outcome (fun () -> (config [ ("Host", "h") ]).Get<MailSettingsDto>().Retry))
expect "whole section absent" "null" (outcome (fun () -> (config []).GetSection("Mail").Get<MailSettingsDto>()))
expect "decimal, key absent" "{ Rate = 0M }" (outcome (fun () -> (config [ ("Other", "x") ]).Get<DecimalDto>()))
expect "decimal, key not a number" "throws InvalidOperationException" (outcome (fun () -> (config [ ("Rate", "cheap") ]).Get<DecimalDto>()))
expect "IReadOnlyList<string>, key present" "{ Items = [|\"a\"|] }" (outcome (fun () -> (config [ ("Items:0", "a") ]).Get<ReadOnlyListDto>()))
expect "record without CLIMutable, key absent" "throws InvalidOperationException" (outcome (fun () -> (config [ ("Name", "n") ]).Get<PlainDto>()))

let plainError = errorMessage (fun () -> (config [ ("Other", "x") ]).Get<PlainDto>())
expect "record without CLIMutable, two keys absent, error names" "name only" (if plainError.Contains "'name'" && not (plainError.Contains "'count'") then "name only" else plainError)

let optionsDefault =
    let services = ServiceCollection()
    services.AddOptions<MailSettingsDto>().Bind((config []).GetSection "Mail") |> ignore
    services.BuildServiceProvider().GetRequiredService<IOptions<MailSettingsDto>>().Value

let plainOptions () =
    let services = ServiceCollection()
    services.AddOptions<PlainDto>().Bind(config [ "Name", "n"; "Count", "3" ]) |> ignore
    services.BuildServiceProvider().GetRequiredService<IOptions<PlainDto>>().Value

expect "record without CLIMutable, AddOptions().Bind, every key present" "throws MissingMethodException" (outcome plainOptions)

expect "AddOptions().Bind, section absent" "instance, Port null, Retry null" (if isNull (box optionsDefault) then "null" elif not (isNull optionsDefault.Port) || not (isNull (box optionsDefault.Retry)) then "field set" else "instance, Port null, Retry null")

printfn "Parse reports every error"

let bad = config [ "Mail:From", " "; "Mail:Port", "70000"; "Mail:Retry:Attempts", "0" ]
expect "parse bad section"
    "Error [\"Host is required\"; \"Port must be 1 to 65535, got 70000\"; \"From is required\"; \"Retry:Attempts must be 1 or more, got 0\"]"
    (outcome (fun () -> bad.GetSection("Mail").Get<MailSettingsDto>() |> MailSettings.parse))

expect "parse text that is not a number, with missing keys"
    "Error [\"Host is required\"; \"Port must be a whole number, got 'ten'\"; \"From is required\"; \"Retry:Attempts must be a whole number, got 'x'\"]"
    (outcome (fun () -> (config [ "Mail:Port", "ten"; "Mail:Retry:Attempts", "x" ]).GetSection("Mail").Get<MailSettingsDto>() |> MailSettings.parse))

expect "parse a missing section"
    "Error [\"the Mail section is missing\"]"
    (outcome (fun () -> (config []).GetSection("Mail").Get<MailSettingsDto>() |> MailSettings.parse))

printfn "Startup"

let badProvider = compose bad
let lateEnv = badProvider.GetRequiredService<IAppEnvironment>()
expect "ValidateOnStart with no host, env resolves" "true" (outcome (fun () -> not (isNull (box lateEnv))))
expect "ValidateOnStart with no host, first read" "throws OptionsValidationException" (outcome (fun () -> Mail.route lateEnv "dev@example.com"))

let startError =
    try
        start badProvider |> ignore
        "started"
    with e ->
        e.GetType().Name + ": " + (validationFailures e |> String.concat " | ")

expect "IStartupValidator.Validate with bad settings"
    "OptionsValidationException: Host is required | Port must be 1 to 65535, got 70000 | From is required | Retry:Attempts must be 1 or more, got 0"
    startError

let good =
    config [ "Mail:Host", "smtp.example.com"; "Mail:Port", "587"; "Mail:From", "ops@example.com"; "Mail:Recipients:0", "dev@example.com" ]

expect "parse in the composition root, bad settings" "throws Exception" (outcome (fun () -> composeDirect bad))
expect "IStartupValidator with no ValidateOnStart" "throws InvalidOperationException" (outcome (fun () -> (composeDirect good).GetRequiredService<IStartupValidator>()))

[<CLIMutable>]
type QueueSettingsDto = { Name: string }

let twoSections =
    let services = ServiceCollection()
    services.AddOptions<MailSettingsDto>().Bind(bad.GetSection "Mail").ValidateOnStart() |> ignore
    services.AddSingleton<IValidateOptions<MailSettingsDto>, MailSettingsValidator>() |> ignore
    services.AddOptions<QueueSettingsDto>().Bind(bad.GetSection "Queue").Validate((fun dto -> not (String.IsNullOrWhiteSpace dto.Name)), "Queue:Name is required").ValidateOnStart() |> ignore
    let provider = services.BuildServiceProvider()

    try
        provider.GetRequiredService<IStartupValidator>().Validate()
        "started"
    with e ->
        e.GetType().Name + ": " + (validationFailures e |> String.concat " | ")

expect "IStartupValidator.Validate with two bad sections"
    "AggregateException: Host is required | Port must be 1 to 65535, got 70000 | From is required | Retry:Attempts must be 1 or more, got 0 | Queue:Name is required"
    twoSections

let appEnv = start (compose good)
expect "container env" "\"ops@example.com -> dev@example.com via smtp.example.com:587 x1\"" (outcome (fun () -> notify appEnv "dev@example.com"))

let directEnv = (composeDirect good).GetRequiredService<IAppEnvironment>()
expect "parse in the composition root, container env" "\"ops@example.com -> ops@example.com via smtp.example.com:587 x1\"" (outcome (fun () -> Mail.route directEnv "ops@example.com"))

let testEnv =
    { new IProvideMailSettings with
        member _.MailSettings =
            { Host = "localhost"
              Port = 2525
              From = "test@example.com"
              Recipients = []
              Retry = Some { Attempts = 3 } } }

expect "test env, no configuration" "\"test@example.com -> qa@example.com via localhost:2525 x3\"" (outcome (fun () -> Mail.route testEnv "qa@example.com"))

if failures > 0 then
    eprintfn "%d settings check(s) failed" failures
    exit 1
