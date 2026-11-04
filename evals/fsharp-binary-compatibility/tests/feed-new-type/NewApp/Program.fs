open System.Globalization
open Shipping

let printPrice id service result =
    match result with
    | Ok (price: decimal) ->
        printfn "%s %s %s" id service (price.ToString("F2", CultureInfo.InvariantCulture))
    | Error message -> failwith message

let p1 = { Id = "P1"; WeightKg = 2.0M }
let p4 = { Id = "P4"; WeightKg = 5.0M }

quote p1 |> printPrice p1.Id "standard"
quoteExpress p1 |> printPrice p1.Id "express"
quoteInsured 300.00M p4 |> printPrice p4.Id "insured"

match trackingStatusOf "HD" with
| Some status -> printfn "HD %A" status
| None -> failwith "Unknown tracking status: HD"
