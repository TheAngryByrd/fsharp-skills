#r "nuget: Microsoft.Extensions.Options, 10.0.0"

open System
open Microsoft.Extensions.Options

[<CLIMutable>]
type ShippingSettings =
    { Carrier: string
      MaxWeightKg: decimal
      RatePerKg: decimal
      FreeShippingOver: decimal
      BlockedRegions: string[] }

type Order =
    { Id: int
      WeightKg: decimal
      Subtotal: decimal
      Region: string }

type ILogger =
    abstract Info: string -> unit

type IProvideLogger =
    abstract Logger: ILogger

module Log =
    let info (env: #IProvideLogger) (message: string) = env.Logger.Info message

module Shipping =
    let cost (options: IOptions<ShippingSettings>) (order: Order) =
        let settings = options.Value

        if order.Subtotal >= settings.FreeShippingOver then
            0m
        else
            Math.Round(order.WeightKg * settings.RatePerKg, 2)

    let check (options: IOptions<ShippingSettings>) (order: Order) =
        let settings = options.Value

        if order.WeightKg > settings.MaxWeightKg then
            Some "too heavy"
        elif settings.BlockedRegions |> Array.contains order.Region then
            Some $"blocked region {order.Region}"
        else
            None

    let quote env (options: IOptions<ShippingSettings>) (order: Order) =
        let line =
            match check options order with
            | Some reason -> $"order {order.Id}: rejected ({reason})"
            | None -> $"order {order.Id}: {options.Value.Carrier} {cost options order:F2}"

        Log.info env line
        line

let sampleOrders =
    [ { Id = 1; WeightKg = 4m; Subtotal = 40m; Region = "US" }
      { Id = 2; WeightKg = 2m; Subtotal = 120m; Region = "CA" }
      { Id = 3; WeightKg = 45m; Subtotal = 60m; Region = "US" }
      { Id = 4; WeightKg = 1m; Subtotal = 10m; Region = "AQ" } ]
