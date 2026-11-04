#load "Codec.fsx"

open System.IO
open System.Text.Json
open System.Text.Json.Nodes
open Codec
open Domain

let report name (passed: bool) (detail: string) =
    let detail = detail.Replace('\n', ' ').Replace('\r', ' ')
    System.Console.WriteLine((if passed then "PASS " else "FAIL ") + name + (if passed then "" else " [" + detail + "]"))

let attempt f =
    try Ok(f ()) with ex -> Error ex

let describe (value: Result<Result<Order, string>, exn>) =
    match value with
    | Ok(Ok order) -> sprintf "Ok %A" order
    | Ok(Error e) -> "Error " + e
    | Error ex -> "threw " + ex.GetType().Name + ": " + ex.Message

let sameJson (expected: string) (actual: string) =
    try JsonNode.DeepEquals(JsonNode.Parse expected, JsonNode.Parse actual) with _ -> false

let saved name = File.ReadAllText(Path.Combine(__SOURCE_DIRECTORY__, "grader-samples", "billing", name))
let savedCustomer name = File.ReadAllText(Path.Combine(__SOURCE_DIRECTORY__, "grader-samples", "customers", name))

let line sku quantity note : Line = { Sku = Sku sku; Quantity = quantity; Note = note }

let cardOrder: Order =
    { Id = "ORD-1001"
      Status = Shipped
      Payment = Card("4242", "12/27")
      Lines = [ line "BOLT-M6" 40 (Some "zinc plated"); line "NUT-M6" 40 None ]
      Discount = Some 2.5m
      CustomerRef = None
      Reserved = Map [ 12, 3; 7, 1 ] }

let cashOrder: Order =
    { Id = "ORD-1002"
      Status = OnHold
      Payment = Cash
      Lines = [ line "WASHER-M6" 100 None ]
      Discount = None
      CustomerRef = Some "ACME-77"
      Reserved = Map.empty }

let giftCardOrder: Order =
    { Id = "ORD-1003"
      Status = Pending
      Payment = GiftCard "GC-100"
      Lines = []
      Discount = None
      CustomerRef = None
      Reserved = Map [ 3, 12 ] }

let fullOrder: Order =
    { Id = "ORD-2001"
      Status = OnHold
      Payment = GiftCard "GC-7"
      Lines = [ line "BOLT-M8" 5 (Some "rush"); line "NUT-M8" 6 (Some "") ]
      Discount = Some 0.75m
      CustomerRef = Some "ACME-12"
      Reserved = Map [ 1, 5; 20, 6; 300, 0 ] }

let checkDecode name json expected =
    let actual = attempt (fun () -> decodeOrder json)
    report name (actual = Ok(Ok expected)) (describe actual)

let checkEncode name order (expectedJson: string) =
    match attempt (fun () -> encodeOrder order) with
    | Ok json -> report name (sameJson expectedJson json) json
    | Error ex -> report name false ("threw " + ex.Message)

let checkError name json =
    let actual = attempt (fun () -> decodeOrder json)
    let passed =
        match actual with
        | Ok(Error _) -> true
        | _ -> false
    report name passed (describe actual)

let withoutProperty (name: string) (json: string) =
    let node = JsonNode.Parse(json).AsObject()
    node.Remove name |> ignore
    node.ToJsonString()

checkDecode "order-card.json decodes to the expected order" (saved "order-card.json") cardOrder
checkEncode "The card order encodes to the order-card.json shape" cardOrder (saved "order-card.json")
checkDecode "order-cash.json decodes to the expected order" (saved "order-cash.json") cashOrder
checkEncode "The cash order encodes to the order-cash.json shape" cashOrder (saved "order-cash.json")
checkDecode "order-gift-card.json decodes to the expected order and ignores the unknown property" (saved "order-gift-card.json") giftCardOrder
checkEncode "The gift card order encodes to the order-gift-card.json shape without the unknown property" giftCardOrder (withoutProperty "channel" (saved "order-gift-card.json"))

checkDecode
    "Optional properties sent as null decode to None"
    """{"id":"ORD-1001","status":"shipped","payment":{"kind":"card","last4":"4242","expiry":"12/27"},"lines":[{"sku":"BOLT-M6","quantity":40,"note":"zinc plated"},{"sku":"NUT-M6","quantity":40,"note":null}],"discount":2.5,"customerRef":null,"reserved":{"12":3,"7":1}}"""
    cardOrder
checkDecode
    "A null discount decodes to None"
    """{"id":"ORD-1002","status":"on_hold","payment":{"kind":"cash"},"lines":[{"sku":"WASHER-M6","quantity":100}],"discount":null,"customerRef":"ACME-77","reserved":{}}"""
    cashOrder
checkDecode
    "Unknown properties in a line and in the payment are ignored"
    """{"id":"ORD-1001","status":"shipped","payment":{"kind":"card","last4":"4242","expiry":"12/27","brand":"visa"},"lines":[{"sku":"BOLT-M6","quantity":40,"note":"zinc plated","warehouse":12},{"sku":"NUT-M6","quantity":40,"bin":{"row":2}}],"discount":2.5,"reserved":{"12":3,"7":1},"meta":{"v":2}}"""
    cardOrder


checkError "A missing required id returns Error" """{"status":"pending","payment":{"kind":"cash"},"lines":[],"reserved":{}}"""
checkError "A null required id returns Error" """{"id":null,"status":"pending","payment":{"kind":"cash"},"lines":[],"reserved":{}}"""
checkError "A line without quantity returns Error" """{"id":"ORD-9","status":"pending","payment":{"kind":"cash"},"lines":[{"sku":"BOLT-M6"}],"reserved":{}}"""
checkError "A missing lines property returns Error" """{"id":"ORD-9","status":"pending","payment":{"kind":"cash"},"reserved":{}}"""
checkError "A missing reserved property returns Error" """{"id":"ORD-9","status":"pending","payment":{"kind":"cash"},"lines":[]}"""
checkError "A null reserved property returns Error" """{"id":"ORD-9","status":"pending","payment":{"kind":"cash"},"lines":[],"reserved":null}"""
checkError "An unknown payment kind returns Error" """{"id":"ORD-9","status":"pending","payment":{"kind":"crypto","wallet":"x"},"lines":[],"reserved":{}}"""
checkError "An unknown status returns Error" """{"id":"ORD-9","status":"lost","payment":{"kind":"cash"},"lines":[],"reserved":{}}"""
checkError "The JSON null returns Error" "null"
checkError "Malformed JSON returns Error" """{"id": "ORD-9", """

let rec caseOrFields (node: JsonNode) =
    match node with
    | :? JsonObject as o -> o |> Seq.exists (fun kv -> kv.Key = "Case" || kv.Key = "Fields" || (not (isNull kv.Value) && caseOrFields kv.Value))
    | :? JsonArray as a -> a |> Seq.exists (fun n -> not (isNull n) && caseOrFields n)
    | _ -> false

let outputs = [ cardOrder; cashOrder; giftCardOrder; fullOrder ] |> List.map (fun o -> attempt (fun () -> encodeOrder o))
let leaked =
    outputs
    |> List.choose (function
        | Ok json -> (try (if caseOrFields (JsonNode.Parse json) then Some json else None) with ex -> Some ex.Message)
        | Error ex -> Some("threw " + ex.Message))
report "No encoded order has a Case or Fields property" (List.isEmpty leaked) (String.concat " | " leaked)

let ann: Customer = { Name = "Ann Lee"; Tier = Gold; Email = Some "ann@example.com" }
let bo: Customer = { Name = "Bo Chen"; Tier = Basic; Email = None }

for (file, customer) in [ "ann.json", ann; "bo.json", bo ] do
    let json = savedCustomer file
    let decoded: Result<Result<Customer, string>, exn> = attempt (fun () -> decodeCustomer json)
    report $"Stored customer {file} decodes to the same customer" (decoded = Ok(Ok customer)) (sprintf "%A" decoded)
    match attempt (fun () -> encodeCustomer customer) with
    | Ok written -> report $"encodeCustomer still writes the {file} shape" (sameJson json written) written
    | Error ex -> report $"encodeCustomer still writes the {file} shape" false ("threw " + ex.Message)
