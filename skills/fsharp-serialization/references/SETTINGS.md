# Serializer settings for F# types

Each result in this file has a check in `scripts/Serialization.fsx`. The checks use .NET 10, FSharp.SystemTextJson 1.4.36, and Thoth.Json.System.Text.Json 0.5.0.
Run `pwsh ./scripts/run.ps1` again after a package upgrade.

## System.Text.Json without a converter

| F# type or input | Result |
| --- | --- |
| Union | Throws `NotSupportedException`: "F# discriminated union serialization is not supported." |
| `Some 3` and `None` | `3` and `null`. A missing option field reads as `None`. |
| Record with a missing field | The field gets `null` or `0`. No error. |
| Record, with `RespectRequiredConstructorParameters = true` | A missing field throws `JsonException`. |
| `[<CLIMutable>]` record with a missing field | The field gets `null` or `0`. No error. |
| The JSON `null` for a record | A `null` record. |
| `Map<int, string>` | An object: `{"1":"a"}`. |
| Class with read-only properties and a constructor | Reads each property through the constructor parameter with the same name. Writes each read-only property, and ignores a read-only property with no constructor parameter on read. |

In an F# script, `RespectNullableAnnotations = true` does not reject `null` for a `string` field.

## FSharp.SystemTextJson

Create one options value for each wire contract, and use it for each call on that contract:

```fsharp
let options =
    JsonFSharpOptions
        .Default()
        .WithUnionInternalTag()
        .WithUnionNamedFields()
        .WithUnionTagName("type")
        .WithUnionTagNamingPolicy(JsonNamingPolicy.CamelCase)
        .WithSkippableOptionFields(SkippableOptionFields.Always, deserializeNullAsNone = true)
        .ToJsonSerializerOptions(PropertyNamingPolicy = JsonNamingPolicy.CamelCase)
```

`options.Converters.Add(JsonFSharpConverter())` gives the same defaults as `JsonFSharpOptions.Default()`.

### Union encodings

Output for `Circle 2.0` and `Point`, where `type Shape = Circle of radius: float | Point`:

| Settings | `Circle 2.0` | `Point` |
| --- | --- | --- |
| `Default()` (adjacent tag) | `{"Case":"Circle","Fields":[2]}` | `{"Case":"Point"}` |
| `WithUnionAdjacentTag().WithUnionNamedFields()` | `{"Case":"Circle","Fields":{"radius":2}}` | `{"Case":"Point"}` |
| `WithUnionExternalTag()` | `{"Circle":[2]}` | `{"Point":[]}` |
| `WithUnionExternalTag().WithUnionNamedFields()` | `{"Circle":{"radius":2}}` | `{"Point":{}}` |
| `WithUnionInternalTag()` | `["Circle",2]` | `["Point"]` |
| `WithUnionInternalTag().WithUnionNamedFields()` | `{"Case":"Circle","radius":2}` | `{"Case":"Point"}` |
| `WithUnionUntagged()` | `{"radius":2}` | `{}` |
| `WithUnionInternalTag().WithUnionNamedFields().WithUnionUnwrapFieldlessTags()` | `{"Case":"Circle","radius":2}` | `"Point"` |
| `NewtonsoftLike()` | `{"Case":"Circle","Fields":[2]}` | `{"Case":"Point"}` |
| `ThothLike()` | `["Circle",2]` | `"Point"` |
| `FSharpLuLike()` | `{"Circle":2}` | `"Point"` |

- `WithUnionTagName("type")` changes the `Case` property name.
- `WithUnionTagNamingPolicy(JsonNamingPolicy.KebabCaseLower)` writes `VeryHigh` as `"very-high"`. `PropertyNamingPolicy` changes field names but not union tags.
- Tag names are case-sensitive on read.
- `Untagged` throws `JsonException` on read when two cases have a field with the same name.
- A single-case union such as `type Sku = Sku of string` writes `"A-1"` by default (`UnwrapSingleCaseUnions`).
- An unknown case throws `JsonException`. The internal tag can come after the fields when `AllowUnorderedTag` is set, which is the default.

### One encoding for each type

`WithUnionUnwrapFieldlessTags()` and the other flags apply to every union. When one union needs a different shape, override that type:

```fsharp
let options =
    JsonFSharpOptions
        .Default()
        .WithUnionInternalTag()
        .WithUnionNamedFields()
        .WithUnionUnwrapFieldlessTags()
        .WithOverrides(fun o -> dict [ typeof<Shape>, o.WithUnionUnwrapFieldlessTags(false) ])
        .ToJsonSerializerOptions()
```

`o` is the base options value. Then `Shape.Point` writes `{"Case":"Point"}`, and a field-less case of another union writes a string.
A `[<JsonFSharpConverter(...)>]` attribute on the type works only when no global options exist, or when the global options call `WithAllowOverride()`.
A value boxed as `obj` does not get its override. Serialize the typed value.

### Options

| Settings | Write `None` | Read absent | Read `null` |
| --- | --- | --- | --- |
| Default | `null` | Throws `JsonException` | `None` |
| `WithSkippableOptionFields()` | Left out | `None` | `Some null` for `string option`. Throws for `decimal option`. |
| `WithSkippableOptionFields(SkippableOptionFields.Always, deserializeNullAsNone = true)` | Left out | `None` | `None` |
| `ToJsonSerializerOptions(DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull)` | Left out | `None` | `None` |

`WhenWritingNull` also changes required fields. A missing `string` reads as `null`, and a missing `int` throws `NullReferenceException`.
`ValueSome 1` writes `1`. `ValueNone` writes `null` by default and is left out with skippable option fields.
`Some None` writes `null`, so an option of an option cannot round-trip.
`Box None`, where `type Box = Box of int option`, writes `null`. At the top level and as a list item, it reads back as a `null` union.

### Records

- A missing field throws `JsonException` that names the field. A `null` for a `string` or list field throws `JsonException`.
- An unknown property is ignored. FSharp.SystemTextJson ignores `UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow` for records. To reject an unknown property, use a DTO or a Thoth.Json decoder.
- The JSON `null` for a record, or as a list item of records, throws `JsonException`.

### Maps and sets

| Type | Default | `WithMapFormat(MapFormat.Object)` |
| --- | --- | --- |
| `Map<string, _>` | `{"a":1}` | `{"a":1}` |
| `Map<Sku, _>` (single-case union of `string`) | `{"A-1":1}` | `{"A-1":1}` |
| `Map<int, _>` | `[[1,"a"]]` | `{"1":"a"}` |
| `Set<string>` | `["a","b"]` | `["a","b"]` |

Tuples write as arrays: `(1, "x")` writes `[1,"x"]`.

## Decode boundary

```fsharp
let decode (json: string) : Result<Shape, string> =
    try
        Ok(JsonSerializer.Deserialize<Shape>(json, options))
    with :? JsonException as ex ->
        Error ex.Message
```

With FSharp.SystemTextJson, the JSON `null` for a record or a union throws `JsonException`. A single-case union around an option is the exception: it reads `null` as a `null` union. With System.Text.Json alone, or for a DTO class, `Deserialize` returns `null`. In these cases, check the result for `null` before you use it.

A `NullReferenceException` or `NotSupportedException` from `Deserialize` shows a settings problem. Fix the settings, and do not catch it.
