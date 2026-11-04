#load "Shipping.fsx"

open Shipping

type TestEnv(settings: ShippingSettings) =
    interface IProvideShippingSettings with
        member _.ShippingSettings = settings

    interface IProvideLogger with
        member _.Logger =
            { new ILogger with
                member _.Info _ = () }

let testEnv =
    TestEnv
        { Carrier = "Test Post"
          MaxWeightKg = 10m
          RatePerKg = 2m
          FreeShippingOver = 50m
          BlockedRegions = [ "CA" ] }

for order in sampleOrders do
    printfn "%s" (Shipping.quote testEnv order)
