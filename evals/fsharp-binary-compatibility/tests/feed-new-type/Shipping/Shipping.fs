module Shipping

open System

type Parcel = { Id: string; WeightKg: decimal }

type ParcelStatus =
    | Created
    | Collected
    | InTransit
    | Delivered
    | Returned

[<RequireQualifiedAccess>]
type TrackingStatus =
    | Created
    | Collected
    | InTransit
    | Held
    | Delivered
    | Returned

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

let quoteExpress (parcel: Parcel) : Result<decimal, string> =
    quote parcel |> Result.map (fun price -> price * 2M)

let quoteInsured (declaredValue: decimal) (parcel: Parcel) : Result<decimal, string> =
    if declaredValue < 0M then
        Error $"Parcel {parcel.Id}: the declared value must not be negative"
    else
        quote parcel
        |> Result.map (fun price ->
            Math.Round(price + declaredValue * 0.01M, 2, MidpointRounding.AwayFromZero))

/// Reads a status code from a tracking event.
let statusOf (code: string) : ParcelStatus option =
    match code.Trim().ToUpperInvariant() with
    | "CR" -> Some Created
    | "CO" -> Some Collected
    | "IT" -> Some InTransit
    | "DL" -> Some Delivered
    | "RT" -> Some Returned
    | _ -> None

let trackingStatusOf (code: string) : TrackingStatus option =
    match code.Trim().ToUpperInvariant() with
    | "CR" -> Some TrackingStatus.Created
    | "CO" -> Some TrackingStatus.Collected
    | "IT" -> Some TrackingStatus.InTransit
    | "HD" -> Some TrackingStatus.Held
    | "DL" -> Some TrackingStatus.Delivered
    | "RT" -> Some TrackingStatus.Returned
    | _ -> None
