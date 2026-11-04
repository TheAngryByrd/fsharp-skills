#load "Shipping.fsx"
open Microsoft.Extensions.Options
open Shipping
let env = { new IProvideLogger with member _.Logger = { new ILogger with member _.Info _ = () } }
let options = Options.Create { Carrier = "Test Post"; MaxWeightKg = 10m; RatePerKg = 2m; FreeShippingOver = 50m; BlockedRegions = [| "CA" |] }
for order in sampleOrders do printfn "%s" (Shipping.quote env options order)
