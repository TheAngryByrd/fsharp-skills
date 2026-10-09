module Program

open System
open Microsoft.Extensions.Logging
open OrderLogging

type CaptureLogger() =
    interface ILogger with
        member _.BeginScope(_) = null
        member _.IsEnabled(_) = true
        member _.Log(level, _, state, ex, formatter) =
            Console.WriteLine("LOG " + string level + " | " + formatter.Invoke(state, ex))

let orders =
    [ { Id = 7; Customer = "Ada"; Total = 12.5m; Payment = Card "1234"; Lines = [ "SKU-1", 2; "SKU-2", 1 ] }
      { Id = 8; Customer = "Bob"; Total = 99.999m; Payment = Invoice 30; Lines = [] }
      { Id = 9; Customer = "Cy"; Total = 1m; Payment = Cash; Lines = [ "X", 5 ] }
      { Id = 10; Customer = "Di"; Total = 0m; Payment = Cash; Lines = [] }
      { Id = 11; Customer = "Ed"; Total = 5m; Payment = Invoice 120; Lines = [] } ]

[<EntryPoint>]
let main _ =
    let log = CaptureLogger() :> ILogger
    for o in orders do
        let run name f =
            try f () with e -> Console.WriteLine("EXN " + name + " " + e.GetType().Name + ": " + e.Message.Split('\n').[0])
        run "describe" (fun () -> Console.WriteLine("DESC " + describe o))
        run "logPlaced" (fun () -> logPlaced log o)
        run "logLines" (fun () -> logLines log o)
        run "validate" (fun () -> validate o; Console.WriteLine("VALID ok"))
    0
