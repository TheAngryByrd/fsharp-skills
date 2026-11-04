module Shipping

open System

type Parcel = { Id: string; WeightKg: decimal }

type ParcelStatus =
    | Created
    | Collected
    | InTransit
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

/// Reads a status code from a tracking event.
let statusOf (code: string) : ParcelStatus option =
    match code.Trim().ToUpperInvariant() with
    | "CR" -> Some Created
    | "CO" -> Some Collected
    | "IT" -> Some InTransit
    | "DL" -> Some Delivered
    | "RT" -> Some Returned
    | _ -> None
