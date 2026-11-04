#r "nuget: FsToolkit.ErrorHandling, 5.2.0"

open System
open FsToolkit.ErrorHandling

[<CLIMutable>]
type ShippingSettingsDto =
    { Carrier: string
      MaxWeightKg: Nullable<decimal>
      RatePerKg: Nullable<decimal>
      FreeShippingOver: Nullable<decimal>
      BlockedRegions: string[] }

type ShippingSettings =
    { Carrier: string
      MaxWeightKg: decimal
      RatePerKg: decimal
      FreeShippingOver: decimal
      BlockedRegions: string list }

module ShippingSettings =
    let private positive key (value: Nullable<decimal>) =
        if not value.HasValue then Error $"{key} is required"
        elif value.Value <= 0m then Error $"{key} must be greater than 0, got {value.Value}"
        else Ok value.Value

    let private region (code: string) =
        not (isNull code) && code.Length = 2 && code |> Seq.forall Char.IsAsciiLetterUpper

    let parse (dto: ShippingSettingsDto) : Result<ShippingSettings, string list> =
        if isNull (box dto) then
            Error [ "the Shipping section is missing" ]
        else
            validation {
                let! carrier =
                    if String.IsNullOrWhiteSpace dto.Carrier then Error "Carrier is required" else Ok dto.Carrier
                and! maxWeight = positive "MaxWeightKg" dto.MaxWeightKg
                and! rate = positive "RatePerKg" dto.RatePerKg
                and! freeOver =
                    if not dto.FreeShippingOver.HasValue then Error "FreeShippingOver is required"
                    elif dto.FreeShippingOver.Value < 0m then Error "FreeShippingOver must be 0 or more"
                    else Ok dto.FreeShippingOver.Value
                and! regions =
                    let regions = dto.BlockedRegions |> Option.ofObj |> Option.map List.ofArray |> Option.defaultValue []
                    match regions |> List.filter (region >> not) with
                    | [] -> Ok regions
                    | bad -> Error $"""BlockedRegions has invalid codes: {String.Join(", ", bad)}"""
                return
                    { Carrier = carrier
                      MaxWeightKg = maxWeight
                      RatePerKg = rate
                      FreeShippingOver = freeOver
                      BlockedRegions = regions }
            }

type Order =
    { Id: int
      WeightKg: decimal
      Subtotal: decimal
      Region: string }

type ILogger =
    abstract Info: string -> unit

type IProvideLogger =
    abstract Logger: ILogger

type IProvideShippingSettings =
    abstract ShippingSettings: ShippingSettings

module Log =
    let info (env: #IProvideLogger) (message: string) = env.Logger.Info message

module Shipping =
    let cost (env: #IProvideShippingSettings) (order: Order) =
        let settings = env.ShippingSettings

        if order.Subtotal >= settings.FreeShippingOver then
            0m
        else
            Math.Round(order.WeightKg * settings.RatePerKg, 2)

    let check (env: #IProvideShippingSettings) (order: Order) =
        let settings = env.ShippingSettings

        if order.WeightKg > settings.MaxWeightKg then
            Some "too heavy"
        elif settings.BlockedRegions |> List.contains order.Region then
            Some $"blocked region {order.Region}"
        else
            None

    let quote env (order: Order) =
        let line =
            match check env order with
            | Some reason -> $"order {order.Id}: rejected ({reason})"
            | None -> $"order {order.Id}: {env.ShippingSettings.Carrier} {cost env order:F2}"

        Log.info env line
        line

let sampleOrders =
    [ { Id = 1; WeightKg = 4m; Subtotal = 40m; Region = "US" }
      { Id = 2; WeightKg = 2m; Subtotal = 120m; Region = "CA" }
      { Id = 3; WeightKg = 45m; Subtotal = 60m; Region = "US" }
      { Id = 4; WeightKg = 1m; Subtotal = 10m; Region = "AQ" } ]
