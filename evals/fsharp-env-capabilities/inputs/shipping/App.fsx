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

type AppEnv(services: IServiceProvider) =
    interface IProvideLogger with
        member _.Logger = services.GetRequiredService<ILogger>()

let configuration =
    ConfigurationBuilder()
        .SetBasePath(__SOURCE_DIRECTORY__)
        .AddJsonFile("appsettings.json", optional = false)
        .Build()

let services = ServiceCollection()
services.AddOptions<ShippingSettings>().Bind(configuration.GetSection "Shipping") |> ignore

services.AddSingleton<ILogger>(
    { new ILogger with
        member _.Info message = printfn "log: %s" message }
)
|> ignore

let provider = services.BuildServiceProvider()
let env = AppEnv(provider)
let options = provider.GetRequiredService<IOptions<ShippingSettings>>()

printfn "ready"

for order in sampleOrders do
    printfn "%s" (Shipping.quote env options order)
