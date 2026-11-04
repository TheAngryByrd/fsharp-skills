module Shipping

open System

type Parcel = { Id: string; WeightKg: decimal }

type ParcelStatus =
    | Created
    | Collected
    | InTransit
    | Delivered
    | Returned
    | Held

type Service =
    | Standard
    | Express

/// The standard price of a parcel in EUR: 4.50 plus 1.20 for each kg.
let quote (parcel: Parcel) : Result<decimal, string> =
    if parcel.WeightKg <= 0M then
        Error $"Parcel {parcel.Id}: the weight must be positive"
    elif parcel.WeightKg > 30M then
        Error $"Parcel {parcel.Id}: the weight is over 30 kg"
    else
        let baseRate = 4.50M
        let perKg = 1.20M
        Ok(Math.Round(baseRate + perKg * parcel.WeightKg, 2, MidpointRounding.AwayFromZero))

/// The price of a parcel in EUR for a service. Express is twice the standard price.
let quoteFor (service: Service) (parcel: Parcel) : Result<decimal, string> =
    match service with
    | Standard -> quote parcel
    | Express -> quote parcel |> Result.map (fun price -> price * 2M)

/// The standard price plus 1% of the declared value.
let quoteInsured (declaredValue: decimal) (parcel: Parcel) : Result<decimal, string> =
    quote parcel
    |> Result.map (fun price -> Math.Round(price + declaredValue * 0.01M, 2, MidpointRounding.AwayFromZero))

/// Reads a status code from a tracking event.
let statusOf (code: string) : ParcelStatus option =
    match code.Trim().ToUpperInvariant() with
    | "CR" -> Some Created
    | "CO" -> Some Collected
    | "IT" -> Some InTransit
    | "DL" -> Some Delivered
    | "RT" -> Some Returned
    | "HD" -> Some Held
    | _ -> None
