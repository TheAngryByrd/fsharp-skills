module OrderLogging

open Microsoft.Extensions.Logging

type PaymentMethod =
    | Card of last4: string
    | Invoice of days: int
    | Cash

type Order =
    { Id: int
      Customer: string
      Total: decimal
      Payment: PaymentMethod
      Lines: (string * int) list }

let describe (o: Order) =
    sprintf "Order %d for %s: %.2f via %A" o.Id o.Customer o.Total o.Payment

let logPlaced (logger: ILogger) (o: Order) =
    logger.LogInformation("Placed {Order}", o)
    logger.LogInformation(describe o)

let logLines (logger: ILogger) (o: Order) =
    for (sku, qty) in o.Lines do
        logger.LogDebug(sprintf "  line %s x%d" sku qty)

let validate (o: Order) =
    if o.Total <= 0m then
        failwithf "Order %d has invalid total %M" o.Id o.Total
    match o.Payment with
    | Invoice days when days > 90 -> failwithf "Invoice terms too long: %A" o.Payment
    | _ -> ()
