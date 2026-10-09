module Formatting

open Microsoft.Extensions.Logging

type Status =
    | Pending
    | Shipped of trackingNumber: string

type Code =
    | Ok200
    | Err of int
    override this.ToString() =
        match this with
        | Ok200 -> "Ok200"
        | Err n -> "Err " + string n

type Settings = { Url: string; Retries: int; Proxy: string option }

type Envelope = { Id: int; Status: Status }

let examples (logger: ILogger) (name: string) (id: int) (total: decimal) (flag: bool)
             (code: int) (settings: Settings) (status: Status) (pair: int * int)
             (env: Envelope) (c: Code) =
    let l1 = sprintf "%s" name                        // L1
    let l2 = sprintf "Order %d" id                    // L2
    let l3 = $"Order %d{id}"                          // L3
    let l4 = $"Total {total:N2}"                      // L4
    let l5 = sprintf "%A" settings                    // L5
    let l6 = string status                            // L6
    let l7 = $"%A{pair}"                              // L7
    let l8 () = failwithf "bad id %d" id              // L8
    let l9 () = failwithf $"bad id %d{id}"            // L9
    let l10 = sprintf "%A" (Some 5)                   // L10
    let l11 = string env                              // L11
    let l12 = sprintf "%b" flag                       // L12
    let l13 = $"%x{code}"                             // L13
    let l14 = string c                                // L14
    let l15 = sprintf "%A" c                          // L15
    logger.LogInformation("Status {Status}", status)  // L16
    logger.LogInformation($"Id %d{id} name %s{name}") // L17
    ()
