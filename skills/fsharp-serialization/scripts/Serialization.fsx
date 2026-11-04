#r "nuget: FSharp.SystemTextJson, 1.4.36"
#r "nuget: Thoth.Json.System.Text.Json, 0.5.0"

open System.Text.Json
open System.Text.Json.Serialization

let mutable failures = 0

let check name (expected: 'a) (actual: 'a) =
    if expected = actual then
        printfn "PASS %s" name
    else
        failures <- failures + 1
        printfn "FAIL %s: expected %A, got %A" name expected actual

let messageOf f =
    try
        f () |> ignore
        ""
    with ex ->
        ex.Message

let outcome f =
    try Ok(f ()) with ex -> Error(ex.GetType().Name)

type Shape =
    | Circle of radius: float
    | Square of side: float
    | Point

type Level =
    | Low
    | High
    | VeryHigh

type Reading =
    { Sensor: string
      Value: int
      Unit: string option }

type Box<'T> = Box of 'T option

type Price = { Amount: decimal option }

type Pick =
    | First of id: int
    | Second of id: int

[<CLIMutable>]
type Settings = { Name: string; Retries: int }

[<JsonFSharpConverter(JsonUnionEncoding.InternalTag ||| JsonUnionEncoding.NamedFields, UnionTagName = "type")>]
type Tagged =
    | Text of body: string
    | Empty

type Tag(name: string, weight: int) =
    member _.Name = name
    member _.Weight = weight
    member _.Display = $"{name}:{weight}"

let plain = JsonSerializerOptions()
let fsharp = JsonFSharpOptions.Default().ToJsonSerializerOptions()
let read<'T> (options: JsonSerializerOptions) (json: string) = outcome (fun () -> JsonSerializer.Deserialize<'T>(json, options))
let write (options: JsonSerializerOptions) value = JsonSerializer.Serialize(value, options)

check "System.Text.Json throws on an F# union" (Error "NotSupportedException") (outcome (fun () -> write plain Point))
check "The union exception says that F# unions are not supported" true ((messageOf (fun () -> write plain Point)).StartsWith "F# discriminated union serialization is not supported.")
check "System.Text.Json writes Some 3 as 3 and None as null" ("3", "null") (write plain (Some 3), write plain (None: int option))
check "System.Text.Json fills missing record fields with null and 0" (Ok { Sensor = null; Value = 0; Unit = None }) (read<Reading> plain "{}")
check "RespectRequiredConstructorParameters rejects missing record fields" (Error "JsonException") (read<Reading> (JsonSerializerOptions(RespectRequiredConstructorParameters = true)) "{}")
check "System.Text.Json fills missing CLIMutable fields with null and 0" (Ok { Name = null; Retries = 0 }) (read<Settings> plain "{}")
check "System.Text.Json reads the JSON null as a null record" true (match read<Reading> plain "null" with Ok r -> isNull (box r) | _ -> false)
check "System.Text.Json fills read-only class properties through the constructor" ("a", 2) (match read<Tag> plain """{"Name":"a","Weight":2}""" with Ok t -> (t.Name, t.Weight) | Error e -> (e, 0))
check "System.Text.Json writes a read-only property and ignores it on read" ("""{"Name":"a","Weight":2,"Display":"a:2"}""", "a:2") (write plain (Tag("a", 2)), match read<Tag> plain """{"Name":"a","Weight":2,"Display":"x"}""" with Ok t -> t.Display | Error e -> e)
check "System.Text.Json writes Map<int, _> as an object" """{"1":"a"}""" (write plain (Map [ 1, "a" ]))

let added = JsonSerializerOptions()
added.Converters.Add(JsonFSharpConverter())
check "Converters.Add(JsonFSharpConverter()) gives the Default() output" (write fsharp (Circle 2.0)) (write added (Circle 2.0))
check "FSharp.SystemTextJson writes Case and Fields by default" """{"Case":"Circle","Fields":[2]}""" (write fsharp (Circle 2.0))
check "FSharp.SystemTextJson unwraps a single-case union" "\"x\"" (write fsharp (Box(Some "x")))
check "FSharp.SystemTextJson rejects a missing option field by default" (Error "JsonException") (read<Reading> fsharp """{"Sensor":"t1","Value":3}""")
check "FSharp.SystemTextJson rejects a missing required field" (Error "JsonException") (read<Reading> fsharp """{"Value":3,"Unit":null}""")
check "FSharp.SystemTextJson rejects the JSON null for a record" (Error "JsonException") (read<Reading> fsharp "null")
check "FSharp.SystemTextJson rejects the JSON null for a union" (Error "JsonException") (read<Shape> fsharp "null")
check "The missing-field exception names the field" true ((messageOf (fun () -> JsonSerializer.Deserialize<Reading>("""{"Value":3,"Unit":null}""", fsharp))).EndsWith ": Sensor")
check "FSharp.SystemTextJson rejects an unknown union case" (Error "JsonException") (read<Shape> fsharp """{"Case":"Hexagon"}""")
check "FSharp.SystemTextJson ignores an unknown property" (Ok { Sensor = "t1"; Value = 3; Unit = None }) (read<Reading> fsharp """{"Sensor":"t1","Value":3,"Unit":null,"Extra":1}""")
check "FSharp.SystemTextJson writes None as null by default" """{"Sensor":"t1","Value":3,"Unit":null}""" (write fsharp { Sensor = "t1"; Value = 3; Unit = None })
check "FSharp.SystemTextJson writes Map<int, _> as an array of pairs" "[[1,\"a\"]]" (write fsharp (Map [ 1, "a" ]))
let objectMaps = JsonFSharpOptions.Default().WithMapFormat(MapFormat.Object).ToJsonSerializerOptions()
check "MapFormat.Object writes Map<int, _> as an object" """{"1":"a"}""" (write objectMaps (Map [ 1, "a" ]))

let skippable = JsonFSharpOptions.Default().WithSkippableOptionFields().ToJsonSerializerOptions()
check "WithSkippableOptionFields leaves out None" """{"Sensor":"t1","Value":3}""" (write skippable { Sensor = "t1"; Value = 3; Unit = None })
check "WithSkippableOptionFields reads a missing option field as None" (Ok { Sensor = "t1"; Value = 3; Unit = None }) (read<Reading> skippable """{"Sensor":"t1","Value":3}""")
check "WithSkippableOptionFields reads a null string option as Some null" (Ok { Sensor = "t1"; Value = 3; Unit = Some null }) (read<Reading> skippable """{"Sensor":"t1","Value":3,"Unit":null}""")
check "WithSkippableOptionFields rejects a null value-type option field" (Error "JsonException") (read<Price> skippable """{"Amount":null}""")
let skippableNull = JsonFSharpOptions.Default().WithSkippableOptionFields(SkippableOptionFields.Always, deserializeNullAsNone = true).ToJsonSerializerOptions()
check "deserializeNullAsNone leaves out None" """{"Sensor":"t1","Value":3}""" (write skippableNull { Sensor = "t1"; Value = 3; Unit = None })
check "deserializeNullAsNone reads a null option field as None" (Ok { Sensor = "t1"; Value = 3; Unit = None }) (read<Reading> skippableNull """{"Sensor":"t1","Value":3,"Unit":null}""")

let ignoreNull = JsonFSharpOptions.Default().ToJsonSerializerOptions(DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull)
check "WhenWritingNull leaves out None" """{"Sensor":"t1","Value":3}""" (write ignoreNull { Sensor = "t1"; Value = 3; Unit = None })
check "WhenWritingNull reads a null option field as None" (Ok { Sensor = "t1"; Value = 3; Unit = None }) (read<Reading> ignoreNull """{"Sensor":"t1","Value":3,"Unit":null}""")
check "WhenWritingNull reads a missing required string as null" (Ok { Sensor = null; Value = 3; Unit = None }) (read<Reading> ignoreNull """{"Value":3}""")
check "WhenWritingNull reads a missing union case field as null" (Ok(Text null)) (read<Tagged> (JsonFSharpOptions.Default().WithUnionInternalTag().WithUnionNamedFields().WithUnionTagName("type").ToJsonSerializerOptions(DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull)) """{"type":"Text"}""")
check "WhenWritingNull reads a missing required map as null" true (match read<{| Name: string; Counts: Map<string, int> |}> ignoreNull """{"Name":"a"}""" with Ok r -> isNull (box r.Counts) | _ -> false)
check "WhenWritingNull throws NullReferenceException for a missing int" (Error "NullReferenceException") (read<Reading> ignoreNull """{"Sensor":"t1"}""")

let camel = JsonFSharpOptions.Default().WithUnionInternalTag().WithUnionNamedFields().ToJsonSerializerOptions(PropertyNamingPolicy = JsonNamingPolicy.CamelCase)
check "PropertyNamingPolicy does not rename union tags" """{"Case":"Circle","radius":2}""" (write camel (Circle 2.0))
let kebabTags = JsonFSharpOptions.Default().WithUnionInternalTag().WithUnionNamedFields().WithUnionTagName("type").WithUnionTagNamingPolicy(JsonNamingPolicy.KebabCaseLower).ToJsonSerializerOptions()
check "WithUnionTagNamingPolicy renames union tags" """{"type":"very-high"}""" (write kebabTags VeryHigh)
check "Union tags are case-sensitive on read" (Error "JsonException") (read<Level> kebabTags """{"type":"Very-High"}""")
check "An internal tag can come after the fields" (Ok(Circle 2.0)) (read<Shape> kebabTags """{"radius":2,"type":"circle"}""")

let encodings =
    [ "Default()", JsonFSharpOptions.Default(), """{"Case":"Circle","Fields":[2]}""", """{"Case":"Point"}"""
      "WithUnionAdjacentTag().WithUnionNamedFields()", JsonFSharpOptions.Default().WithUnionAdjacentTag().WithUnionNamedFields(), """{"Case":"Circle","Fields":{"radius":2}}""", """{"Case":"Point"}"""
      "WithUnionExternalTag()", JsonFSharpOptions.Default().WithUnionExternalTag(), """{"Circle":[2]}""", """{"Point":[]}"""
      "WithUnionExternalTag().WithUnionNamedFields()", JsonFSharpOptions.Default().WithUnionExternalTag().WithUnionNamedFields(), """{"Circle":{"radius":2}}""", """{"Point":{}}"""
      "WithUnionInternalTag()", JsonFSharpOptions.Default().WithUnionInternalTag(), """["Circle",2]""", """["Point"]"""
      "WithUnionInternalTag().WithUnionNamedFields()", JsonFSharpOptions.Default().WithUnionInternalTag().WithUnionNamedFields(), """{"Case":"Circle","radius":2}""", """{"Case":"Point"}"""
      "WithUnionUntagged()", JsonFSharpOptions.Default().WithUnionUntagged(), """{"radius":2}""", "{}"
      "WithUnionInternalTag().WithUnionNamedFields().WithUnionUnwrapFieldlessTags()", JsonFSharpOptions.Default().WithUnionInternalTag().WithUnionNamedFields().WithUnionUnwrapFieldlessTags(), """{"Case":"Circle","radius":2}""", "\"Point\""
      "NewtonsoftLike()", JsonFSharpOptions.NewtonsoftLike(), """{"Case":"Circle","Fields":[2]}""", """{"Case":"Point"}"""
      "ThothLike()", JsonFSharpOptions.ThothLike(), """["Circle",2]""", "\"Point\""
      "FSharpLuLike()", JsonFSharpOptions.FSharpLuLike(), """{"Circle":2}""", "\"Point\"" ]

for (name, settings, circle, point) in encodings do
    let options = settings.ToJsonSerializerOptions()
    check $"{name} writes Circle 2.0 and Point" (circle, point) (write options (Circle 2.0), write options Point)

let fieldless = JsonFSharpOptions.Default().WithUnionInternalTag().WithUnionNamedFields().WithUnionTagName("type").WithUnionUnwrapFieldlessTags()
check "WithUnionUnwrapFieldlessTags writes every field-less case as a string" """["High",{"type":"Circle","radius":2},"Point"]""" (write (fieldless.ToJsonSerializerOptions()) (High, Circle 2.0, Point))
let overridden = fieldless.WithOverrides(fun o -> dict [ typeof<Shape>, o.WithUnionUnwrapFieldlessTags(false) ]).ToJsonSerializerOptions()
check "WithOverrides changes the encoding of one type" """["High",{"type":"Point"}]""" (write overridden (High, Point))
check "A value boxed as obj does not get its override" "\"Point\"" (write overridden (box Point))

check "A type attribute works without global options" """{"type":"Empty"}""" (JsonSerializer.Serialize Empty)
check "Global options ignore a type attribute" """{"Case":"Empty"}""" (write fsharp Empty)
let allowOverride = JsonFSharpOptions.Default().WithAllowOverride().ToJsonSerializerOptions()
check "WithAllowOverride lets a type attribute win" """{"type":"Empty"}""" (write allowOverride Empty)

check "A single-case union of None writes null" "null" (write fsharp (Box(None: int option)))
check "A single-case union of None in a list reads back as a null element" true (match read<Box<int> list> fsharp "[null]" with Ok [ b ] -> isNull (box b) | _ -> false)
check "A single-case union of None reads back as a null union at the top level" true (match read<Box<int>> fsharp "null" with Ok b -> isNull (box b) | _ -> false)
check "An option of an option loses Some None" "[1,null,null]" (write fsharp [ Some(Some 1); Some None; None ])

check "Untagged rejects two cases with the same field name" (Error "JsonException") (read<Pick> (JsonFSharpOptions.Default().WithUnionUntagged().WithUnionNamedFields().ToJsonSerializerOptions()) """{"id":1}""")
check "FSharp.SystemTextJson ignores UnmappedMemberHandling.Disallow for records" (Ok { Sensor = "t1"; Value = 3; Unit = None }) (read<Reading> (JsonFSharpOptions.Default().ToJsonSerializerOptions(UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow)) """{"Sensor":"t1","Value":3,"Unit":null,"Extra":1}""")
check "ValueNone writes null by default and is left out with skippable option fields" ("""{"A":1,"B":null}""", """{"A":1}""") (write fsharp {| A = ValueSome 1; B = (ValueNone: int voption) |}, write skippable {| A = ValueSome 1; B = (ValueNone: int voption) |})

type Sku = Sku of string
type Shelf = { Items: Reading list; Label: string }

check "FSharp.SystemTextJson writes Map<string, _> as an object" ("""{"a":1}""", """{"a":1}""") (write fsharp (Map [ "a", 1 ]), write objectMaps (Map [ "a", 1 ]))
check "FSharp.SystemTextJson writes Map<Sku, _> as an object" ("""{"A-1":1}""", """{"A-1":1}""") (write fsharp (Map [ Sku "A-1", 1 ]), write objectMaps (Map [ Sku "A-1", 1 ]))
check "FSharp.SystemTextJson writes Set<string> and a tuple as arrays" ("""["a","b"]""", """[1,"x"]""") (write fsharp (set [ "b"; "a" ]), write fsharp (1, "x"))
check "FSharp.SystemTextJson rejects null for a string field" (Error "JsonException") (read<Shelf> fsharp """{"Items":[],"Label":null}""")
check "FSharp.SystemTextJson rejects null for a list field" (Error "JsonException") (read<Shelf> fsharp """{"Items":null,"Label":"a"}""")
check "FSharp.SystemTextJson rejects a null list item of records" (Error "JsonException") (read<Shelf> fsharp """{"Items":[null],"Label":"a"}""")
check "RespectNullableAnnotations does not reject null for an F# string field in a script" (Ok { Sensor = null; Value = 3; Unit = None }) (read<Reading> (JsonSerializerOptions(RespectNullableAnnotations = true)) """{"Sensor":null,"Value":3}""")

type LevelReordered =
    | High
    | Low

type ReadingV2 =
    { Sensor: string
      Value: int
      Unit: string option
      Site: string }

check "A new required field rejects JSON saved before the change" (Error "JsonException") (read<ReadingV2> skippableNull """{"Sensor":"t1","Value":3}""")
check "A new union case reads JSON saved before the change" (Ok Level.Low) (read<Level> fsharp """{"Case":"Low"}""")
check "Reordered record fields read JSON saved before the change" (Ok { Sensor = "t1"; Value = 3; Unit = None }) (read<Reading> skippableNull """{"Unit":null,"Value":3,"Sensor":"t1"}""")
check "Reordered union cases read JSON saved before the change" (Ok LevelReordered.Low) (read<LevelReordered> fsharp """{"Case":"Low"}""")
check "A changed field type rejects JSON saved before the change" (Error "JsonException") (read<Reading> skippableNull """{"Sensor":"t1","Value":"3"}""")
check "A renamed union case rejects JSON saved before the change" (Error "JsonException") (read<Level> fsharp """{"Case":"Medium"}""")

type LevelV2 =
    | Low
    | [<JsonName "High">] Top

type ReadingV3 =
    { [<JsonPropertyName "Sensor">] Probe: string
      Value: int
      Unit: string option }

check "JsonName keeps the old wire name of a renamed union case" (Ok Top) (read<LevelV2> fsharp """{"Case":"High"}""")
check "JsonPropertyName keeps the old wire name of a renamed field" (Ok { Probe = "t1"; Value = 3; Unit = None }) (read<ReadingV3> skippableNull """{"Sensor":"t1","Value":3}""")
type ReadingV4 =
    { Sensor: string
      Value: int
      Units: string option }

type Move = Move of source: string * target: string
type MoveV2 = Move2 of target: string * source: string

check "A renamed option field reads JSON saved before the change as None" (Ok { Sensor = "t1"; Value = 3; Units = None }) (read<ReadingV4> skippableNull """{"Sensor":"t1","Value":3,"Unit":"C"}""")
check "Reordered fields of a union case swap values in a positional Fields array" (Ok(Move2("a", "b"))) (read<MoveV2> fsharp ((write fsharp (Move("a", "b"))).Replace("\"Move\"", "\"Move2\"")))
check "A new option field reads JSON saved before the change as None" (Ok { Sensor = "t1"; Value = 3; Unit = None }) (read<Reading> skippableNull """{"Sensor":"t1","Value":3}""")

open System.Text.Json.Nodes

check "JsonNode.DeepEquals ignores property order and compares numbers by value" true (JsonNode.DeepEquals(JsonNode.Parse """{"a":2.50,"b":1}""", JsonNode.Parse """{"b":1,"a":2.5}"""))

open Thoth.Json.Core
open Thoth.Json.System.Text.Json

let shapeDecoder: Decoder<Shape> =
    Decode.field "shape" Decode.string
    |> Decode.andThen (function
        | "circle" -> Decode.field "radius" Decode.float |> Decode.map Circle
        | "square" -> Decode.field "side" Decode.float |> Decode.map Square
        | "point" -> Decode.succeed Point
        | other -> Decode.fail $"unknown shape {other}")

let encodeShape shape =
    match shape with
    | Circle r -> Encode.object [ "shape", Encode.string "circle"; "radius", Encode.float r ]
    | Square s -> Encode.object [ "shape", Encode.string "square"; "side", Encode.float s ]
    | Point -> Encode.object [ "shape", Encode.string "point" ]

check "A Thoth.Json decoder reads its wire shape" (Ok(Circle 2.0)) (Decode.fromString shapeDecoder """{"shape":"circle","radius":2}""")
check "A Thoth.Json decoder returns Error for an unknown shape" true (Decode.fromString shapeDecoder """{"shape":"hexagon"}""" |> Result.isError)
check "A Thoth.Json decoder returns Error for malformed JSON" true (Decode.fromString shapeDecoder """{"shape":""" |> Result.isError)
check "A Thoth.Json decoder reads each shape that the encoder writes" (Ok [ Circle 2.0; Square 3.0; Point ]) ([ Circle 2.0; Square 3.0; Point ] |> List.map (encodeShape >> Encode.toString 0 >> Decode.fromString shapeDecoder) |> List.fold (fun acc r -> match acc, r with Ok xs, Ok x -> Ok(xs @ [ x ]) | Error e, _ | _, Error e -> Error e) (Ok []))
check "A Thoth.Json encoder writes the same wire shape" """{"shape":"point"}""" (Encode.toString 0 (encodeShape Point))

if failures > 0 then exit 1
