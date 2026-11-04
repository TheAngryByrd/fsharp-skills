#r "nuget: Microsoft.Extensions.Configuration.Json, 10.0.0"
#r "nuget: Microsoft.Extensions.Configuration.Binder, 10.0.0"
#r "nuget: Microsoft.Extensions.Options.ConfigurationExtensions, 10.0.0"
#r "nuget: Microsoft.Extensions.DependencyInjection, 10.0.0"
#load "Shipping.fsx"

open System
open Microsoft.Extensions.Configuration
open Microsoft.Extensions.DependencyInjection
open Microsoft.Extensions.Options
open Shipping

type ShippingSettingsValidator() =
    interface IValidateOptions<ShippingSettingsDto> with
        member _.Validate(_, dto) =
            match ShippingSettings.parse dto with
            | Ok _ -> ValidateOptionsResult.Success
            | Error errors -> ValidateOptionsResult.Fail errors

type IAppEnv =
    inherit IProvideLogger
    inherit IProvideShippingSettings

type AppEnv(services: IServiceProvider) =
    interface IAppEnv with
        member _.Logger = services.GetRequiredService<ILogger>()
        member _.ShippingSettings = services.GetRequiredService<ShippingSettings>()

let configuration =
    ConfigurationBuilder()
        .SetBasePath(__SOURCE_DIRECTORY__)
        .AddJsonFile("appsettings.json", optional = false)
        .Build()

let services = ServiceCollection()
services.AddOptions<ShippingSettingsDto>().Bind(configuration.GetSection "Shipping").ValidateOnStart() |> ignore
services.AddSingleton<IValidateOptions<ShippingSettingsDto>, ShippingSettingsValidator>() |> ignore

services.AddSingleton<ShippingSettings>(fun sp ->
    match ShippingSettings.parse (sp.GetRequiredService<IOptions<ShippingSettingsDto>>().Value) with
    | Ok settings -> settings
    | Error errors -> invalidOp (String.concat "; " errors))
|> ignore

services.AddSingleton<ILogger>(
    { new ILogger with
        member _.Info message = printfn "log: %s" message }
)
|> ignore

let provider = services.BuildServiceProvider()

try
    provider.GetRequiredService<IStartupValidator>().Validate()
with :? OptionsValidationException as e ->
    eprintfn "Invalid Shipping settings:"
    for failure in e.Failures do
        eprintfn "  %s" failure
    exit 1

let env = AppEnv(provider)

printfn "ready"

for order in sampleOrders do
    printfn "%s" (Shipping.quote env order)
