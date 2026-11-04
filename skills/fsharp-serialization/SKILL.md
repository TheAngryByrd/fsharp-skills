---
name: fsharp-serialization
description: Serialize F# records, unions, options, and maps to JSON that matches a wire contract, and keep old JSON readable. Use when writing or reviewing F# code that calls System.Text.Json, configures FSharp.SystemTextJson (JsonFSharpConverter, JsonFSharpOptions), writes Thoth.Json encoders or decoders, adds a DTO layer, reads JSON from another service, or adds or renames a union case or record field that is stored or sent as JSON.
compatibility: The proof script requires the .NET 10 SDK, PowerShell 7.2 or later, and NuGet access. scripts/global.json selects .NET 10.
---

# F# serialization

System.Text.Json was made for C# classes. With F# types it throws, writes a shape that other services cannot read, or reads missing data as `null` or `0` with no error.
FSharp.SystemTextJson fixes the exceptions, but its defaults write a shape that other services do not use.
A serializer that round-trips its own output can still disagree with the other service on every message.

## Rules

- Write the wire contract before you choose settings. For each type, record the property names, the union shape, what an absent or `null` optional value means, the map key shape, the required fields, and what to do with unknown properties and unknown cases.
- Do not use System.Text.Json alone for F# domain types. It throws `NotSupportedException` on a union. It fills a missing record field with `null` or `0`, and it reads the JSON `null` as a `null` record.
- Do not keep the FSharp.SystemTextJson defaults for a contract that you do not own. The defaults write `{"Case":...,"Fields":[...]}`, reject a missing option field, and write `Map<int, _>` as an array of pairs.
- Set each union encoding, the union tag name, and the union tag naming policy. `PropertyNamingPolicy` does not change union tags.
- Encoding flags apply to every union. When one union needs a different shape, use `WithOverrides`. A `[<JsonFSharpConverter>]` attribute on a type has no effect when global options exist, unless you call `WithAllowOverride`.
- To leave out `None` and read an absent or `null` value as `None`, use `WithSkippableOptionFields(SkippableOptionFields.Always, deserializeNullAsNone = true)`.
  `WithSkippableOptionFields()` reads `null` in a `string option` as `Some null`.
  Do not use `DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull` for this. It reads a missing required `string`, `Map`, or union case field as `null` and throws `NullReferenceException` for a missing `int`.
- A single-case union around an option (`Box of int option`) writes `null` for `Box None` and reads it back as a `null` union. An option of an option writes `Some None` as `null`. Change the type or write a converter.
- At the decode boundary, return `Error` for a `JsonException`. When the code reads with System.Text.Json alone, into a DTO class, or into a single-case union around an option, also return `Error` for a `null` result. Run the cases that other exceptions can come from, and fix the settings that cause them.
- When the wire shape differs from the domain types, or the domain types have private constructors, decode into a DTO or with a Thoth.Json decoder, then parse into the domain type. See [parse-dont-validate](../parse-dont-validate/SKILL.md).
- For Native AOT and trimming, use [fsharp-native-aot](../fsharp-native-aot/SKILL.md). This skill does not cover source generation.

Read [references/SETTINGS.md](references/SETTINGS.md) for the System.Text.Json defaults, each FSharp.SystemTextJson union encoding with its output, and the option, map, and naming settings.
Read [references/WIRE-COMPATIBILITY.md](references/WIRE-COMPATIBILITY.md) before you add, rename, or remove a union case or record field that is stored or sent, and for the saved-sample tests, Thoth.Json, and DTO layers.

## Steps

1. Write the wire contract as a list or table. Done when each union, option, map, and required field has a rule.
2. Get JSON samples that the other side wrote, or that the current code wrote before the change. Save them as files next to the tests.
3. Choose FSharp.SystemTextJson settings, Thoth.Json coders, or a DTO layer. Make one options value for each wire contract, and use it for every call on that contract.
4. For each saved sample, check that it decodes to the expected F# value, and that the expected value encodes to the same JSON. Compare parsed JSON, not text, so that property order and white space do not count.
5. For each contract rule that no sample shows, add a case: an absent optional value, a `null` optional value, a missing required field, a `null` required field, an unknown property, an unknown union case, the JSON `null`, and malformed JSON.
6. Run the cases. Confirm that no output has a `Case` or `Fields` property unless the contract uses it, and that the decode function returns `Error` and does not throw.

## Verify

Run the proof script from the skill root:

```powershell
pwsh ./scripts/run.ps1
```

The script shows each default and setting in this skill with FSharp.SystemTextJson 1.4.36 and Thoth.Json.System.Text.Json 0.5.0 on .NET 10.
It fails when a result differs from the expected result.
