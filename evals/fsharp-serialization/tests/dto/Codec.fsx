#r "nuget: FSharp.SystemTextJson, 1.4.36"
#load "Domain.fsx"

open System
open System.Collections.Generic
open System.Text.Json
open System.Text.Json.Serialization
open Domain

let options = JsonFSharpOptions.Default().ToJsonSerializerOptions()

[<CLIMutable>]
type PaymentDto =
    { Kind: string
      Last4: string
      Expiry: string
      Code: string }

[<CLIMutable>]
type LineDto =
    { Sku: string
      Quantity: Nullable<int>
      Note: string }

[<CLIMutable>]
type OrderDto =
    { Id: string
      Status: string
      Payment: PaymentDto
      Lines: LineDto[]
      Discount: Nullable<decimal>
      CustomerRef: string
      Reserved: Dictionary<int, int> }

let private dtoOptions =
    JsonSerializerOptions(
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
    )

let private required name (value: 'T) =
    if isNull (box value) then Error $"missing {name}" else Ok value

let private parseStatus =
    function
    | "pending" -> Ok Pending
    | "shipped" -> Ok Shipped
    | "on_hold" -> Ok OnHold
    | other -> Error $"unknown status {other}"

let private parsePayment (dto: PaymentDto) =
    match dto.Kind with
    | "card" when not (isNull dto.Last4 || isNull dto.Expiry) -> Ok(Card(dto.Last4, dto.Expiry))
    | "gift_card" when not (isNull dto.Code) -> Ok(GiftCard dto.Code)
    | "cash" -> Ok Cash
    | other -> Error $"invalid payment {other}"

let private parseLine (dto: LineDto) =
    if isNull (box dto) || isNull dto.Sku || not dto.Quantity.HasValue then
        Error "invalid line"
    else
        Ok({ Sku = Sku dto.Sku; Quantity = dto.Quantity.Value; Note = Option.ofObj dto.Note }: Line)

let private sequence results =
    List.foldBack (fun r acc -> Result.bind (fun xs -> Result.map (fun x -> x :: xs) r) acc) results (Ok [])

let private toOrder (dto: OrderDto) : Result<Order, string> =
    if isNull (box dto) then
        Error "The JSON is null."
    else
        match required "id" dto.Id, required "status" dto.Status, required "payment" dto.Payment, required "lines" dto.Lines, required "reserved" dto.Reserved with
        | Ok id, Ok status, Ok payment, Ok lines, Ok reserved ->
            match parseStatus status, parsePayment payment, sequence (lines |> Array.toList |> List.map parseLine) with
            | Ok status, Ok payment, Ok lines ->
                Ok
                    { Id = id
                      Status = status
                      Payment = payment
                      Lines = lines
                      Discount = Option.ofNullable dto.Discount
                      CustomerRef = Option.ofObj dto.CustomerRef
                      Reserved = reserved |> Seq.map (fun kv -> kv.Key, kv.Value) |> Map.ofSeq }
            | Error e, _, _
            | _, Error e, _
            | _, _, Error e -> Error e
        | Error e, _, _, _, _
        | _, Error e, _, _, _
        | _, _, Error e, _, _
        | _, _, _, Error e, _
        | _, _, _, _, Error e -> Error e

let private fromOrder (order: Order) : OrderDto =
    { Id = order.Id
      Status =
        match order.Status with
        | Pending -> "pending"
        | Shipped -> "shipped"
        | OnHold -> "on_hold"
      Payment =
        match order.Payment with
        | Card(last4, expiry) -> { Kind = "card"; Last4 = last4; Expiry = expiry; Code = null }
        | GiftCard code -> { Kind = "gift_card"; Last4 = null; Expiry = null; Code = code }
        | Cash -> { Kind = "cash"; Last4 = null; Expiry = null; Code = null }
      Lines =
        order.Lines
        |> List.map (fun l ->
            { Sku = (let (Sku s) = l.Sku in s)
              Quantity = Nullable l.Quantity
              Note = Option.toObj l.Note })
        |> List.toArray
      Discount = Option.toNullable order.Discount
      CustomerRef = Option.toObj order.CustomerRef
      Reserved = Dictionary(order.Reserved) }

let encodeCustomer (customer: Customer) : string = JsonSerializer.Serialize(customer, options)

let decodeCustomer (json: string) : Result<Customer, string> =
    try
        Ok(JsonSerializer.Deserialize<Customer>(json, options))
    with :? JsonException as ex ->
        Error ex.Message

let encodeOrder (order: Order) : string = JsonSerializer.Serialize(fromOrder order, dtoOptions)

let decodeOrder (json: string) : Result<Order, string> =
    try
        toOrder (JsonSerializer.Deserialize<OrderDto>(json, dtoOptions))
    with :? JsonException as ex ->
        Error ex.Message
