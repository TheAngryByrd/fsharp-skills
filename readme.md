# F# skills

Reusable instructions for AI agents working on F# code, packaged in the [Agent Skills format](https://agentskills.io/home).
The skills cover domain design, dependency management, error composition, failure paths, idiomatic shape, async composition, API verification, compiler performance, Native AOT, .NET nullness interop, signature files, performance types, JSON serialization, binary compatibility, and library API design.

## Skills

| Skill | What it does | Why it exists |
| --- | --- | --- |
| [parse-dont-validate](skills/parse-dont-validate/SKILL.md) | Parses raw input into domain types and preserves their invariants through updates and conversions. | Makes invalid states harder to construct and reduces repeated checks on primitive values. |
| [optimize-fsharp-typecheck-graph](skills/optimize-fsharp-typecheck-graph/SKILL.md) | Uses compiler dependency graphs and timing reports to investigate F# build performance. | Separates measured build improvements from graph changes and checks source and binary compatibility. |
| [fsharp-iwsam-errors](skills/fsharp-iwsam-errors/SKILL.md) | Composes `Result` errors through interfaces with static abstract members (IWSAM). The caller selects a concrete error type. | Reduces repeated `Result.mapError` conversions and uses compiler constraints to require the error cases needed by a call tree. |
| [fsharp-env-capabilities](skills/fsharp-env-capabilities/SKILL.md) | Passes dependencies through a generic environment with small `IProvideX` capability interfaces. Binds settings to `[<CLIMutable>]` F# types, validates them with `Result` at startup, and exposes the validated type as a capability instead of `IOptions<T>`. | Lets the compiler infer dependency requirements and lets tests supply only the dependencies a function needs. The configuration binder gives no error for a missing key, binds an F# `option` as `None`, and throws on an F# `list` key that has a value. `ValidateOnStart` with no host does not stop the app. |
| [fsharp-async-composition](skills/fsharp-async-composition/SKILL.md) | Chooses between `task`, `async`, `valueTask`, `cancellableTask`, and `taskResult`, and converts between Task, Async, and ValueTask at boundaries with correct cancellation and exceptions. | Agents mix these types and write code that compiles but loses cancellation, never starts an `Async`, or awaits a `ValueTask` twice. FS0193 between these types appeared in 93 agent sessions. |
| [fsharp-native-aot](skills/fsharp-native-aot/SKILL.md) | Makes F# formatting, logging, JSON, and configuration work under Native AOT, and compares JIT output with native exe output. | F# formatting can throw or silently lose union and tuple data in a native exe, and publish warnings do not point at that code. |
| [fsharp-failure-paths](skills/fsharp-failure-paths/SKILL.md) | Replaces partial functions, `failwith`, hidden defaults, swallowed exceptions, and first-error-only validation with explicit `Error` results. | The compiler accepts these defects, so they reach human review. Review evidence ranks failure-path handling as a top category of comments on agent F# code. |
| [fsharp-idiom-review](skills/fsharp-idiom-review/SKILL.md) | Gives a checklist with before/after examples that the agent applies to its own F# diff: records instead of tuples, options instead of out parameters, `match` instead of `if`/`elif` chains or `let mutable`, no list indexing, single-pass collection code, `match!`, `static member val`, and syntax APIs instead of string concatenation. It links to `parse-dont-validate` for modeling. | Agents write C#-shaped F#, most of all when they port C#. The compiler accepts it. Review evidence ranks idiomatic shape and collection efficiency among the strongest categories of human comments on agent F# code. Codex and opencode sessions hold 5 user corrections on this subject. |
| [fsharp-verify-api](skills/fsharp-verify-api/SKILL.md) | Lists the real signatures of a package version before F# code uses them, and checks opens, references, existing helpers, and `.fsx` `#r` lines. | Agents write the API that they remember. FS0039 is the top compiler error in agent sessions, and each wrong guess costs a failed build. |
| [fsharp-nullness-interop](skills/fsharp-nullness-interop/SKILL.md) | Turns on F# nullness checks, converts `T \| null` results from .NET APIs to F# types at the boundary, and fixes FS0041 errors from new BCL overloads such as `TimeSpan.FromSeconds(int64)`. | Codex and opencode sessions show 435 FS3261 warnings in 37 sessions (61% from 3 sessions) and FS0041 errors in 91 sessions. Claude sessions show 20 FS3261 hits and `TimeSpan.FromSeconds` overload errors. Some fixes compile but hide a real null, for example `Some (call ())`, `string x`, or `Unchecked.nonNull`. |
| [fsharp-signature-files](skills/fsharp-signature-files/SKILL.md) | Adds `.fsi` files that expose only the API that other projects use, hides type representations behind constructor functions, fixes signature mismatches, and compares the public surface of the built assembly before and after. | Without guidance, an agent can keep the compiler's `--sig` output, which repeats every public member and hides nothing. A missing `RequireQualifiedAccess` in a `.fsi` is only a warning, and a doc comment that is only in the `.fs` leaves the XML file. The skill comes from a maintainer request, not from failure data. |
| [fsharp-performance-types](skills/fsharp-performance-types/SKILL.md) | Chooses F# collections and types for run time and allocation: `list`, `array`, `ResizeArray`, `seq`, `Map` against `Dictionary`, single-pass loops, `voption`, struct tuples and records, and `StringBuilder` instead of `sprintf`. It measures allocated bytes and run time before and after with `GC.GetAllocatedBytesForCurrentThread` or BenchmarkDotNet. It links to `fsharp-idiom-review` for readable shape. | Agents write collection code that makes several passes, allocates on each element, or updates a `Map` in a loop. The compiler accepts it, and review evidence ranks collection efficiency among the strongest categories of human comments on agent F# code. A rewrite can also change the output: `ToString("F3")` follows the current culture and `sprintf` does not. |
| [fsharp-serialization](skills/fsharp-serialization/SKILL.md) | Serializes F# records, unions, options, and maps to JSON that matches a wire contract. It covers System.Text.Json defaults, FSharp.SystemTextJson union encodings and option settings, Thoth.Json and DTO layers, and tests that round-trip saved JSON samples. | System.Text.Json throws on F# unions and reads missing fields as `null` or `0`. FSharp.SystemTextJson defaults write `Case` and `Fields`, and some option settings read `null` as `Some null` or a missing required field as `null`. These defects compile and can pass a round trip of the code's own output. |
| [fsharp-binary-compatibility](skills/fsharp-binary-compatibility/SKILL.md) | Changes a published F# library so that apps compiled against the old version still run against the new DLL with no rebuild. It gives safe patterns for module functions, members, unions, records, interfaces, `inline`, literals, renames, and FSharp.Core, and runs package validation, `apicompat`, and an F# signature diff (`scripts/sig-diff.ps1`). | Agents check only that the solution builds, which proves source compatibility. F# `let` functions cannot have overloads, a union case in the middle silently changes old matches, and Release consumers copy small function bodies. The IL tools do not report several of these changes. The skill comes from a maintainer request, not from failure data. |
| [fsharp-library-api-design](skills/fsharp-library-api-design/SKILL.md) | Classifies each public API change of an F# library as a source break, a binary break, or a safe change. It gives safe extension patterns, rules for a C#-friendly surface, the SemVer version for each change, and the lowest FSharp.Core version. It checks compatibility with package validation and with consumers that were compiled against the old version. | Many F# breaking changes do not look like breaking changes. A new optional parameter or a wider parameter type compiles for every consumer, but compiled consumers then throw `MissingMethodException`. A new union case or a curried-to-tupled change breaks F# callers, and package validation does not report it. A Release F# consumer keeps the old body of a small function after a patch fix, unless the library uses `--nooptimizationdata`. |

The patterns can work together: the environment supplies capabilities, and IWSAM interfaces describe possible errors.

## Install with npx

Install Node.js with npm to make `npx` available. Run this command from your project directory:

```sh
npx skills add TheAngryByrd/fsharp-skills
```

The [skills CLI](https://github.com/vercel-labs/skills) installs skills for supported agents. Use its selection prompts when shown.
To install one skill for Codex:

```sh
npx skills add TheAngryByrd/fsharp-skills --skill fsharp-iwsam-errors --agent codex
```

Use `--skill fsharp-env-capabilities` to select the environment skill. Add `--global` to install for your user instead of the current project.
To list available skills without installing them:

```sh
npx skills add TheAngryByrd/fsharp-skills --list
```

For a local checkout, replace `TheAngryByrd/fsharp-skills` with its absolute path.

## Manual installation

1. Clone this repository:

   ```sh
   git clone https://github.com/TheAngryByrd/fsharp-skills.git
   ```

2. Follow your agent's skill installation instructions. Copy the complete selected skill directory into its configured skills directory.

## Use a skill

Ask the agent to use the installed skill for a specific task.

Example requests:

```text
Use fsharp-iwsam-errors to compose these Result-returning functions and select an error type for the caller.
```

```text
Use fsharp-env-capabilities to replace these dependency parameters with a capability environment that supports test fakes.
```

```text
Use fsharp-env-capabilities to validate the appsettings.json settings at startup and pass the validated settings to these functions as a capability.
```

```text
Use fsharp-failure-paths to find the partial functions, defaults, and caught exceptions in this change and report each failure as an Error.
```

```text
Use fsharp-verify-api to list the System.CommandLine 2.0.0 signatures before you add command-line parsing.
```

```text
Use fsharp-idiom-review to port this C# class to F#, then check the diff for tuples, mutable loops, and if/elif chains before you finish.
```

```text
Use parse-dont-validate to model this input with private constructors and explicit parse errors.
```

```text
Use fsharp-native-aot to make this F# service publish with PublishAot and keep its log and JSON output unchanged.
```

```text
Use fsharp-async-composition to make this handler call our Async library without blocking and honor its CancellationToken.
```

```text
Use fsharp-nullness-interop to turn on nullness checks with TreatWarningsAsErrors and fix the FS3261 and FS0041 errors without hiding nulls.
```

```text
Use fsharp-signature-files to add .fsi files to this library that expose only what the app uses, and compare the public surface before and after.
```

```text
Use fsharp-performance-types to make this summary fast for 200,000 rows, and report the allocated bytes and run time before and after.
```

```text
Use fsharp-serialization to make these F# event types match the JSON that the payments service sends, and add tests that round-trip its saved samples.
```

```text
Use fsharp-binary-compatibility to add a currency parameter to parsePrice in this library for a minor release, and check that apps built against 1.0.0 still run.
```

```text
Use fsharp-library-api-design to add this feature to our published library as a minor version without breaking compiled consumers.
```

```text
Use optimize-fsharp-typecheck-graph to measure this project's type-checking bottleneck and evaluate a compatible improvement.
```

Skill discovery and explicit invocation syntax depend on the agent. You can also direct the agent to the linked `SKILL.md` file.
Keep the skill's scripts and references with its entry point so relative links remain valid.

## Run the examples

The IWSAM, environment, and failure-path skills include F# scripts that require the .NET 10 SDK and NuGet access. Their runners require PowerShell 7.2 or later (`pwsh`).
Each `scripts/global.json` selects .NET 10. Run the supplied runner so SDK selection starts in that directory.
The F# 8 compiler can report `FS0192` for the IWSAM examples.
Read the selected skill's **Verify** section for its runner and expected compiler diagnostics.
Compile-time break tests intentionally fail compilation. Their runners check for the expected diagnostics.
Compare printed example outcomes with the findings documents. The IWSAM runner and the environment scripts `Environment.fsx` and `FlatEnv.fsx` do not assert these runtime outcomes.
The environment runner asserts one script, `scripts/Settings.fsx`. It fails when a configuration binder result or a startup validation result differs.
The failure-path runner, `scripts/run.ps1`, asserts its outcomes. It fails when an unsafe form does not fail or a safe form does not report the failure.

The idiom review skill includes a runner, `scripts/run.ps1`. It requires the .NET 10 SDK and PowerShell 7.2 or later.
The runner runs `scripts/Idioms.fsx`. It fails when a before form and its after form give different results, or when `static member val` does not keep one instance.

The API verification skill includes `scripts/show-api.ps1`, which lists the public API of a NuGet package version. It requires the .NET 10 SDK, PowerShell 7.2 or later, and NuGet access.
Its runner, `scripts/run.ps1`, lists Expecto 10.2.3 and 11.1.1, an `FSharp.Core` module function, and an extension method. It fails when an expected member is missing or a removed member is present.

The Native AOT skill includes a project-based runner, `scripts/run.ps1`. It requires the .NET 10 SDK, PowerShell 7.2 or later, and NuGet access. It also requires the platform Native AOT toolchain: MSVC and the Windows SDK on Windows, or clang on Linux.
The runner builds and publishes a probe app and compares JIT output with native exe output. It fails when a probe result differs from the expected verdict or the expected native text. Compare the printed results with the skill's findings document.

The async composition skill includes a runner, `scripts/run.ps1`. It requires the .NET 10 SDK, PowerShell 7.2 or later, and NuGet access for IcedTasks.
The runner runs `scripts/Proofs.fsx` and fails when a cancellation, exception, start, or ValueTask fact differs. It also builds `scripts/StateMachine` in Release and checks that FS3511 is reported only for the `let rec` case.

The nullness skill includes a project-based runner, `scripts/run.ps1`. It requires the .NET 10 SDK, NuGet access, and PowerShell 7.2 or later.
The runner builds and runs a project with nullness checks and warnings as errors, and compares its null-handling results with expected values. It then builds each compile-time break test and checks for its expected diagnostic codes and message text.

The signature file skill includes a project-based runner, `scripts/run.ps1`, and `scripts/public-surface.ps1`, which prints the public API of a built assembly. Both require the .NET 10 SDK and PowerShell 7.4 or later.
The runner checks the public surface, the XML documentation, and an `InternalsVisibleTo` test project of a sample library. It checks the `.fsi` output of `--allsigs`. It then builds each compile-time break test and checks for its expected diagnostic codes.

The performance types skill includes a runner, `scripts/run.ps1`. It requires the .NET 10 SDK and PowerShell 7.2 or later.
The runner runs `scripts/Perf.fsx` with `dotnet fsi --optimize+` and measures the allocation, culture, and sort claims of the skill. It fails when a measured result differs from the claim.
The serialization skill includes a runner, `scripts/run.ps1`. It requires the .NET 10 SDK, PowerShell 7.2 or later, and NuGet access for FSharp.SystemTextJson and Thoth.Json.
The runner runs `scripts/Serialization.fsx` and fails when a System.Text.Json default, a FSharp.SystemTextJson setting, a wire compatibility result, or a Thoth.Json result differs from the expected result.
The binary compatibility skill includes a project-based runner, `scripts/run.ps1`, and `scripts/sig-diff.ps1`, which diffs the F# signatures of two versions of a project. Both require the .NET 10 SDK, PowerShell 7.4 or later, and NuGet access.
The runner builds each case's library versions and runs a consumer that was compiled against the baseline with the new DLL. It also rebuilds the consumer and runs `apicompat`, the signature diff, and PublicApiGenerator. It fails when a result differs from the expected line in the case. It then checks package validation, the FSharp.Core package dependency, the Roslyn analyzer claim, and `sig-diff.ps1`.
The library API design skill includes a project-based runner, `scripts/run.ps1`. It requires the .NET 10 SDK, PowerShell 7.4 or later, and NuGet access.
For each change in `scripts/changes`, the runner packs the library with package validation against a 1.0.0 baseline. It builds an F# and a C# consumer against the change, and runs the 1.0.0 consumers with the new DLL. It fails when a result differs from the `// expect-` lines of the change. It also checks the FSharp.Core dependency of a packed library.

The parsing and compiler-performance skills provide guidance. Apply their verification steps to the target project.

## Evaluate a skill

The [eval runner](evals/README.md) measures whether a skill changes an agent's results. It runs each task with and without the skill in Claude Code, Codex CLI, or opencode, and grades the output with scripts.
It requires PowerShell 7.4 or later, the agent CLIs you test, and the prerequisites of the skill's graders.

```powershell
pwsh ./evals/run-evals.ps1 -Skill fsharp-native-aot -Target claude:sonnet,codex
```

The runner starts agents without permission prompts. Read the caution in the eval README before you run it.
Eval tasks exist for each skill. See the [eval README](evals/README.md) for the task list.

The [eval dashboard](https://theangrybyrd.github.io/fsharp-skills/) shows committed result sets: for each skill, task, and target, the pass rate, turns, failed builds, time, and tokens with and without the skill. [evals/README.md "Dashboard"](evals/README.md#dashboard) explains how to export and publish results.

The `fsharp-performance-types` eval ran with `claude:sonnet` (`claude-sonnet-5-5`), `codex` (gpt-6.1-sol, effort high; default from config, not recorded in run.json), and the free opencode models `opencode/flint-40b-free`, `opencode/nemotron-3.5-lightning-free`, and `opencode/deepseek-v4.1-flash-free`. Codex without the skill failed the `render` allocation limit in 2 of 2 runs and passed with the skill. Claude Sonnet passed every check without the skill and failed one output check in one run with the skill. The free models reached their usage limits, so the opencode comparison is partial. [lode/eval-design.md](lode/eval-design.md) and issue #13 have the results.

## Related skills

Use [dotnet-reliability-skills](https://github.com/TheAngryByrd/dotnet-reliability-skills/tree/main) for .NET testing and reliability work, including generator reviews and mutation testing.
These skills remain in that collection to avoid maintaining duplicate copies here.

```sh
npx skills add TheAngryByrd/dotnet-reliability-skills
```

## Create or change a skill

Follow [skills/README.md](skills/README.md) and use [skills/SKILL.md.template](skills/SKILL.md.template).
The template is not an installable skill.

Keep the skill list, purpose, prerequisites, and usage instructions in this README aligned with the skill files.
For project knowledge and maintenance rules, start with the [Lode README](lode/readme.md).
