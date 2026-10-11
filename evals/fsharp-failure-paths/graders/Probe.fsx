#load "Invoice.fsx"

open Microsoft.FSharp.Reflection
open Invoice

System.Globalization.CultureInfo.CurrentCulture <- System.Globalization.CultureInfo.InvariantCulture

let caseOf (value: obj) =
    if isNull value then "null"
    elif value :? exn then "exception"
    elif FSharpType.IsUnion(value.GetType(), true) && value.GetType().Name.StartsWith "FSharpResult" then
        (fst (FSharpValue.GetUnionFields(value, value.GetType(), true))).Name
    else "value"

let describe (value: obj) =
    match caseOf value with
    | "exception" -> (value :?> exn).GetType().Name + ": " + (value :?> exn).Message
    | "Ok" | "Error" -> sprintf "%A" (snd (FSharpValue.GetUnionFields(value, value.GetType(), true))).[0]
    | _ -> sprintf "%A" value

let attempt f = try box (f ()) with ex -> box ex

let report name (passed: bool) (value: obj) =
    let detail = (caseOf value + " " + describe value).Replace('\n', ' ').Replace('\r', ' ')
    System.Console.WriteLine((if passed then "PASS " else "FAIL ") + name + (if passed then "" else " [" + detail + "]"))

let mentions (words: string list) (value: obj) =
    let text = (describe value).ToLowerInvariant()
    words |> List.forall (fun w -> text.Contains(w.ToLowerInvariant()))

let euro: Settings = Map [ "currency", "EUR" ]
let catalog () = Map [ "SKU-1", 10.00m; "SKU-2", 5.00m ]
let line sku qty : OrderLine = { Sku = sku; Quantity = qty }
let order = [ line "SKU-1" 2; line "SKU-2" 1 ]

let valid = attempt (fun () -> invoice euro catalog order)
report "A valid order returns Ok with the unchanged summary" (caseOf valid = "Ok" && describe valid = "\"2 lines, first SKU-1, total 25.00 EUR\"") valid

let empty = attempt (fun () -> invoice euro catalog [])
report "An empty order returns Error" (caseOf empty = "Error") empty

let unknown = attempt (fun () -> invoice euro catalog [ line "SKU-1" 1; line "SKU-9" 1 ])
report "A SKU with no price returns Error that names the SKU" (caseOf unknown = "Error" && mentions [ "SKU-9" ] unknown) unknown

let down = attempt (fun () -> invoice euro (fun () -> failwith "catalog unavailable") order)
report "A failed price fetch returns Error that keeps the cause" (caseOf down = "Error" && mentions [ "catalog unavailable" ] down) down

let noCurrency = attempt (fun () -> invoice Map.empty catalog order)
report "Settings without a currency return Error that names the setting" (caseOf noCurrency = "Error" && mentions [ "currency" ] noCurrency) noCurrency

let twoBad = attempt (fun () -> invoice euro catalog [ line "SKU-1" 0; line "SKU-2" -3 ])
report "Two invalid lines return Error that reports both" (caseOf twoBad = "Error" && mentions [ "SKU-1"; "SKU-2" ] twoBad) twoBad
