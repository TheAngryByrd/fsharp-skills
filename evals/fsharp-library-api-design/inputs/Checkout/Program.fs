open System.Globalization
open Payments

CultureInfo.DefaultThreadCurrentCulture <- CultureInfo.InvariantCulture
CultureInfo.CurrentCulture <- CultureInfo.InvariantCulture

type FakeGateway() =
    let mutable count = 0
    interface IPaymentGateway with
        member _.Submit(request, total) =
            count <- count + 1
            sprintf "ch_%d_%s_%M" count request.Currency total

let describe method =
    match method with
    | PaymentMethod.Card last4 -> sprintf "card ending %s" last4
    | PaymentMethod.PayPal email -> sprintf "PayPal %s" email

let client = PaymentClient(FakeGateway())

let orders =
    [ { Amount = 25.00m; Currency = "USD"; Method = PaymentMethod.Card "4242" }
      { Amount = 80.00m; Currency = "EUR"; Method = PaymentMethod.PayPal "ana@example.com" } ]

for order in orders do
    let receipt = client.Charge(order)
    printfn "%s | %s | fee %M | total %M" receipt.ChargeId (describe order.Method) receipt.Fee receipt.Total

let batch = client.ChargeAll(orders)
printfn "batch %d | total %M" batch.Length (batch |> List.sumBy _.Total)

let status = Approved
printfn "status %A" status

let cardFee = Fees.calculate (PaymentMethod.Card "0000")
[ 10m; 100m ] |> List.map cardFee |> List.iter (printfn "card fee %M")
