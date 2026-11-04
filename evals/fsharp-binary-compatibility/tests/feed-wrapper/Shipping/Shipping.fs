module Shipping

open System

type Parcel = { Id: string; WeightKg: decimal }

type ParcelStatus =
    | Created
    | Collected
    | InTransit
    | Delivered
    | Returned

type TrackingStatus =
    | Created
    | Collected
    | InTransit
    | Held
    | Delivered
    | Returned

type InsuredParcel = { Parcel: Parcel; DeclaredValue: decimal }

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

/// The express price: twice the standard price.
let quoteExpress (parcel: Parcel) : Result<decimal, string> =
    quote parcel |> Result.map (fun price -> price * 2M)

/// The standard price plus 1% of the declared value.
let quoteInsured (insured: InsuredParcel) : Result<decimal, string> =
    quote insured.Parcel
    |> Result.map (fun price -> Math.Round(price + insured.DeclaredValue * 0.01M, 2, MidpointRounding.AwayFromZero))

/// Reads a status code from a tracking event.
let statusOf (code: string) : ParcelStatus option =
    match code.Trim().ToUpperInvariant() with
    | "CR" -> Some ParcelStatus.Created
    | "CO" -> Some ParcelStatus.Collected
    | "IT" -> Some ParcelStatus.InTransit
    | "DL" -> Some ParcelStatus.Delivered
    | "RT" -> Some ParcelStatus.Returned
    | _ -> None

/// Reads a tracking code, with the statuses that were added after 1.0.0.
let parseTrackingCode (code: string) : Result<TrackingStatus, string> =
    match code.Trim().ToUpperInvariant() with
    | "CR" -> Ok TrackingStatus.Created
    | "CO" -> Ok TrackingStatus.Collected
    | "IT" -> Ok TrackingStatus.InTransit
    | "HD" -> Ok TrackingStatus.Held
    | "DL" -> Ok TrackingStatus.Delivered
    | "RT" -> Ok TrackingStatus.Returned
    | other -> Error $"Unknown code {other}"
