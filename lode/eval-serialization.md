# Serialization eval

The `fsharp-serialization` eval has one task, `billing-codec`. General eval rules are in [eval design](eval-design.md). The proof runner contract is in [proof runners](proof-runners.md).

## Task

The workspace holds `Domain.fsx`, `Codec.fsx`, `CONTRACT.md`, three billing order samples, and two stored customer samples.
`Codec.fsx` uses one `JsonFSharpOptions.Default()` options value for customers and orders. The agent must change the order codec to follow `CONTRACT.md` and keep the customer JSON unchanged.

The contract needs these settings at the same time:

- An internal `kind` tag with snake_case tag names for `Payment`, and plain strings for `OrderStatus`. `Cash` must stay an object, so `WithUnionUnwrapFieldlessTags` needs a `WithOverrides` entry for `Payment`.
- camelCase property names for orders, and the default PascalCase `{"Case":...}` shape for customers. One global options value cannot give both.
- `Map<int, int>` as an object (`MapFormat.Object`).
- Optional values left out on write, and absent or `null` read as `None`. Of the settings that the proof script compares, only `WithSkippableOptionFields(SkippableOptionFields.Always, deserializeNullAsNone = true)` does this and keeps required fields required.

```fsharp
let orderOptions =
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
```

## Overlap with the skill

The skill teaches each setting that the task needs, because these settings are the subject of the skill. The skill does not contain the task's options value.
Its examples use the `type` tag name, the `CamelCase` and `KebabCaseLower` tag policies, and the `Shape`, `Level`, and `Reading` types. The task uses the `kind` tag name, the `SnakeCaseLower` tag policy, and the `Order` types.
The agent must still map each contract rule to a setting, keep the customer shape, and find the `null` option case.

## Why the prompt forbids a hand-written parser

The first version of the task asked for a new `Codec.fsx` with no starting code. Claude Sonnet and Codex wrote a `JsonElement` parser by hand without the skill and passed every check (7 and 10 turns). A hand-written parser avoids every converter setting, so the task measured nothing.
The current prompt says to use `JsonSerializer` with FSharp.SystemTextJson, and not to read or write JSON with `JsonDocument`, `JsonNode`, `JsonElement`, `Utf8JsonReader`, `Utf8JsonWriter`, or a custom `JsonConverter`.
The text check reads only `Codec.fsx` and the files that it loads with `#load`, except `Domain.fsx`. It removes `//` and `(* *)` comments first. A test file that uses `JsonNode.DeepEquals`, as the skill recommends, does not fail the check. A DTO with `JsonSerializer` passes.

## Grader

`graders/billing-codec.ps1` copies the workspace, restores the original `Domain.fsx` and samples, writes its own `global.json`, and runs `graders/CodecProbe.fsx` with `dotnet fsi`.
The probe opens `Codec` before `Domain` and gives each expected value a type annotation, so a DTO record with the domain labels cannot capture the probe's record literals.
The probe compares decoded values with F# values, and compares encoded JSON with each sample through `JsonNode.DeepEquals`. Property order is ignored, numbers compare by value, and a `null` property differs from an absent property.
The probe calls the agent's functions inside `try`, so a thrown exception fails the check and does not stop the probe. A `NullReferenceException` from `WhenWritingNull` with a missing `int` is one such case.

```mermaid
flowchart LR
    Ws[Agent workspace] --> Text[Text check on Codec.fsx and loaded files]
    Ws --> Copy[Copy and restore Domain.fsx and samples]
    Copy --> Probe[CodecProbe.fsx]
    Probe --> Orders[Order samples and contract cases]
    Probe --> Customers[Stored customer samples]
    Text --> Checks[grading.json]
    Orders --> Checks
    Customers --> Checks
```

`tests/Grader.Tests.ps1` grades these results and checks each check by name:

| Case | Failing checks |
| --- | --- |
| Known good, `module Codec =` copy, DTO layer, a test file and comments that name `JsonNode` | None |
| Original input | Every order sample check, `null` optional values, unknown nested properties, and `Case`/`Fields` |
| No `Codec.fsx` | The compile check |
| Edited `Domain.fsx` | `Domain.fsx is unchanged` |
| `JsonObject` in the codec, `JsonDocument` in a loaded file | The text check |
| One options value for customers and orders | The four customer checks |
| `WhenWritingNull` | Missing `id` (reads as `null`) and a line without `quantity` (throws `NullReferenceException`) |
| `WithSkippableOptionFields()` | `null` note (reads as `Some null`) and `null` discount (throws) |

The text check does not find a parser that reads JSON with string functions or regular expressions.
The comment removal does not nest `(* *)` comments, so a nested comment can hide a type name from the check or show one to it.
The prompt names `JsonNode` but not its subtypes `JsonObject`, `JsonArray`, and `JsonValue`. The text check rejects all four.
The `checkError` cases do not cover a missing `status`, `payment`, `reserved`, or `sku`.

## Eval results on issue 12

The run used 2 runs for each target and mode, explicit invocation, and the final grader (`grade-evals.ps1`). Each run with the skill loaded it. opencode used `github-copilot/gpt-6.1-sol`, because the default model failed with `Token refresh failed: 401` and `github-copilot/gpt-5.5` failed with "Unexpected server error".

| Target | Mode | Pass rate | Turns | Failed builds |
| --- | --- | --- | --- | --- |
| claude:sonnet | with | 100% | 8.5 | 0.0 |
| claude:sonnet | without | 92% | 18.5 | 2.0 |
| codex | with | 100% | 16.0 | 0.0 |
| codex | without | 100% | 20.5 | 1.5 |
| opencode:github-copilot/gpt-6.1-sol | with | 100% | 17.0 | 0.0 |
| opencode:github-copilot/gpt-6.1-sol | without | 100% | 19.0 | 0.0 |

- Claude Sonnet without the skill used `WhenWritingNull` in both runs. A missing `id` then decoded as `Ok` with `Id = null`, and a line without `quantity` threw. With the skill, both runs used `deserializeNullAsNone = true`.
- In one earlier baseline run, Claude Sonnet without the skill used `WithSkippableOptionFields(SkippableOptionFields.Always)` and failed both `null` option checks.
- Codex and opencode used `deserializeNullAsNone = true` and `WithOverrides` in both modes. The skill reduced turns and failed builds for these targets, but not the pass rate.
- After the run, the skill got five more proof checks and two wording changes: one options value for each wire contract, and the top-level `Box None` read. The rules did not change.

```powershell
pwsh ./evals/run-evals.ps1 -Skill fsharp-serialization -Target claude:sonnet,codex,opencode:github-copilot/gpt-6.1-sol -Runs 2
```
