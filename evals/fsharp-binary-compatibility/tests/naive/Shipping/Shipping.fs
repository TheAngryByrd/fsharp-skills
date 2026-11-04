module Shipping

open System

type Parcel =
    { Id: string
      WeightKg: decimal
      DeclaredValue: decimal option }

type ParcelStatus =
    | Created
    | Collected
    | InTransit
    | Held
    | Delivered
    | Returned

type Service =
    | Standard
    | Express

/// The price of a parcel in EUR: 4.50 plus 1.20 for each kg, twice for express, plus 1% of the declared value.
let quote (service: Service) (parcel: Parcel) : Result<decimal, string> =
    if parcel.WeightKg <= 0M then
        Error $"Parcel {parcel.Id}: the weight must be positive"
    elif parcel.WeightKg > 30M then
        Error $"Parcel {parcel.Id}: the weight is over 30 kg"
    else
        let baseRate = 4.50M
        let perKg = 1.20M
        let standard = Math.Round(baseRate + perKg * parcel.WeightKg, 2, MidpointRounding.AwayFromZero)
        let price = if service = Express then standard * 2M else standard
        let insurance = parcel.DeclaredValue |> Option.map (fun v -> v * 0.01M) |> Option.defaultValue 0M
        Ok(Math.Round(price + insurance, 2, MidpointRounding.AwayFromZero))

/// Reads a status code from a tracking event.
let statusOf (code: string) : ParcelStatus option =
    match code.Trim().ToUpperInvariant() with
    | "CR" -> Some Created
    | "CO" -> Some Collected
    | "IT" -> Some InTransit
    | "HD" -> Some Held
    | "DL" -> Some Delivered
    | "RT" -> Some Returned
    | _ -> None
