# Wire compatibility

JSON that a service stored or sent before a change must stay readable after it.
The results in this file use FSharp.SystemTextJson 1.4.36 with `WithSkippableOptionFields(SkippableOptionFields.Always, deserializeNullAsNone = true)`.

## Type changes

| Change | JSON written before the change | JSON written after the change, read by old code |
| --- | --- | --- |
| Add a union case | Reads. | The new case throws `JsonException`. |
| Rename a union case | Throws `JsonException`. Keep the old name with `[<JsonName "Old">]` on the case. | Throws. |
| Add a required record field | Throws `JsonException` for the missing field. | Reads. The new field is ignored. |
| Add an `option` record field | Reads as `None`. | Reads. The new field is ignored. |
| Rename a required record field | Throws `JsonException`. Keep the old name with `[<JsonPropertyName "Old">]`. | Throws. |
| Rename an `option` record field | Reads as `None`, and the saved value is lost. Keep the old name with `[<JsonPropertyName "Old">]`. | Reads as `None` in old code, and the value is lost. |
| Remove a record field | Reads. The old field is ignored. | Throws when old code requires the field. |
| Change a field type | Throws. | Throws. |
| Reorder record fields or union cases | Reads. | Reads. |
| Reorder the fields of a union case | With a positional `Fields` array, two fields of the same type swap values with no error. Keep the field order. | Same. |

Add the case or field to the reader before the writer sends it.
To keep old readers working when you add a union case, ask whether each reader has a fallback case. FSharp.SystemTextJson has no fallback for an unknown case. A DTO or a Thoth.Json decoder can map it to an `Unknown` case.

## Saved-sample tests

Save the JSON that the other side sent, or that the current code wrote, before you change a type. Each sample is a file. Each test reads a file, decodes it, and compares it with an F# value. Then it encodes the value and compares the parsed JSON with the file.

```fsharp
open System.IO
open System.Text.Json.Nodes

let sample name = File.ReadAllText(Path.Combine(__SOURCE_DIRECTORY__, "samples", name))

let sameJson (expected: string) (actual: string) =
    JsonNode.DeepEquals(JsonNode.Parse expected, JsonNode.Parse actual)

let circleJson = sample "circle.json"

if decode circleJson <> Ok(Circle 2.0) then
    failwith "circle.json does not decode to Circle 2.0"

if not (sameJson circleJson (encode (Circle 2.0))) then
    failwith "Circle 2.0 does not encode to the circle.json shape"
```

`JsonNode.DeepEquals` ignores property order and white space, and compares numbers by value, so `2.50` equals `2.5`.

Do not regenerate a sample from the new code. A regenerated sample cannot find a change in the wire format.
Add a case for each contract rule that no sample shows: an absent optional value, a `null` optional value, a missing or `null` required field, an unknown property, an unknown case, the JSON `null`, and malformed JSON.

## Thoth.Json

Thoth.Json uses explicit decoders and encoders. The wire format is in the code, so a settings change cannot change it.
`Thoth.Json.Core` holds the coders. `Thoth.Json.System.Text.Json` runs them on System.Text.Json. `Thoth.Json.Net` runs them on Newtonsoft.Json.

```fsharp
open Thoth.Json.Core
open Thoth.Json.System.Text.Json

let shapeDecoder: Decoder<Shape> =
    Decode.field "shape" Decode.string
    |> Decode.andThen (function
        | "circle" -> Decode.field "radius" Decode.float |> Decode.map Circle
        | "point" -> Decode.succeed Point
        | other -> Decode.fail $"unknown shape {other}")

let encodeShape shape =
    match shape with
    | Circle r -> Encode.object [ "shape", Encode.string "circle"; "radius", Encode.float r ]
    | Point -> Encode.object [ "shape", Encode.string "point" ]

Decode.fromString shapeDecoder """{"shape":"circle","radius":2}""" // Ok (Circle 2.0)
Encode.toString 0 (encodeShape Point)                               // {"shape":"point"}
```

`Decode.fromString` returns `Result<'T, string>` and does not throw for bad input.
Use Thoth.Json when the wire shape differs from the F# types, when a decoder must parse into a validated domain type, or when you need a fallback for an unknown case.

## DTO layer

A DTO is a record or class whose shape equals the wire shape. Serialize the DTO, and map between the DTO and the domain type in F# code.

- Use a DTO when the domain type has private constructors, when two services need two shapes of one type, or when converter settings cannot express the shape.
- Map from the DTO with a parse function that returns `Result`. Check each required field for `null`, because System.Text.Json fills a missing field with `null` or `0`.
- Give each required value-type field a `Nullable<int>` or `int option` type in the DTO. A missing `int` field reads as `0`, and the parse step cannot see that it is missing.
- Keep the DTO in the module that owns the wire format. Domain code does not use it.
