#r "nuget: FSharp.SystemTextJson, 1.4.36"
#load "Domain.fsx"

module Codec =
    open System.Text.Json
    open System.Text.Json.Serialization
    open Domain

    let options = JsonFSharpOptions.Default().ToJsonSerializerOptions()

    let private orderOptions =
        JsonFSharpOptions
            .Default()
            .WithUnionInternalTag()
            .WithUnionNamedFields()
            .WithUnionTagName("kind")
            .WithUnionTagNamingPolicy(JsonNamingPolicy.SnakeCaseLower)
            .WithUnionUnwrapFieldlessTags()
            .WithSkippableOptionFields(SkippableOptionFields.Always, deserializeNullAsNone = true)
            .WithMapFormat(MapFormat.Object)
            .WithOverrides(fun o -> dict [ typeof<Payment>, o.WithUnionUnwrapFieldlessTags(false) ])
            .ToJsonSerializerOptions(PropertyNamingPolicy = JsonNamingPolicy.CamelCase)

    let encodeCustomer (customer: Customer) : string = JsonSerializer.Serialize(customer, options)

    let decodeCustomer (json: string) : Result<Customer, string> =
        try
            Ok(JsonSerializer.Deserialize<Customer>(json, options))
        with :? JsonException as ex ->
            Error ex.Message

    let encodeOrder (order: Order) : string = JsonSerializer.Serialize(order, orderOptions)

    let decodeOrder (json: string) : Result<Order, string> =
        try
            Ok(JsonSerializer.Deserialize<Order>(json, orderOptions))
        with :? JsonException as ex ->
            Error ex.Message
