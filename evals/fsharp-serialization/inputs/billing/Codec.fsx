#r "nuget: FSharp.SystemTextJson, 1.4.36"
#load "Domain.fsx"

open System.Text.Json
open System.Text.Json.Serialization
open Domain

let options = JsonFSharpOptions.Default().ToJsonSerializerOptions()

let encodeCustomer (customer: Customer) : string = JsonSerializer.Serialize(customer, options)

let decodeCustomer (json: string) : Result<Customer, string> =
    try
        Ok(JsonSerializer.Deserialize<Customer>(json, options))
    with :? JsonException as ex ->
        Error ex.Message

let encodeOrder (order: Order) : string = JsonSerializer.Serialize(order, options)

let decodeOrder (json: string) : Result<Order, string> =
    try
        Ok(JsonSerializer.Deserialize<Order>(json, options))
    with :? JsonException as ex ->
        Error ex.Message
