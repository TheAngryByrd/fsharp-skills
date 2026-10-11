# F# skills

Reusable instructions for AI agents working on F# code, packaged in the [Agent Skills format](https://agentskills.io/home).
The skills cover domain design, dependency management, error composition, failure paths, idiomatic shape, async composition, API verification, compiler performance, and Native AOT.

## Skills

| Skill | What it does | Why it exists |
| --- | --- | --- |
| [parse-dont-validate](skills/parse-dont-validate/SKILL.md) | Parses raw input into domain types and preserves their invariants through updates and conversions. | Makes invalid states harder to construct and reduces repeated checks on primitive values. |
| [optimize-fsharp-typecheck-graph](skills/optimize-fsharp-typecheck-graph/SKILL.md) | Uses compiler dependency graphs and timing reports to investigate F# build performance. | Separates measured build improvements from graph changes and checks source and binary compatibility. |
| [fsharp-iwsam-errors](skills/fsharp-iwsam-errors/SKILL.md) | Composes `Result` errors through interfaces with static abstract members (IWSAM). The caller selects a concrete error type. | Reduces repeated `Result.mapError` conversions and uses compiler constraints to require the error cases needed by a call tree. |
| [fsharp-env-capabilities](skills/fsharp-env-capabilities/SKILL.md) | Passes dependencies through a generic environment with small `IProvideX` capability interfaces. | Lets the compiler infer dependency requirements and lets tests supply only the dependencies a function needs. |
| [fsharp-async-composition](skills/fsharp-async-composition/SKILL.md) | Chooses between `task`, `async`, `valueTask`, `cancellableTask`, and `taskResult`, and converts between Task, Async, and ValueTask at boundaries with correct cancellation and exceptions. | Agents mix these types and write code that compiles but loses cancellation, never starts an `Async`, or awaits a `ValueTask` twice. FS0193 between these types appeared in 93 agent sessions. |
| [fsharp-native-aot](skills/fsharp-native-aot/SKILL.md) | Makes F# formatting, logging, JSON, and configuration work under Native AOT, and compares JIT output with native exe output. | F# formatting can throw or silently lose union and tuple data in a native exe, and publish warnings do not point at that code. |
| [fsharp-failure-paths](skills/fsharp-failure-paths/SKILL.md) | Replaces partial functions, `failwith`, hidden defaults, swallowed exceptions, and first-error-only validation with explicit `Error` results. | The compiler accepts these defects, so they reach human review. Review evidence ranks failure-path handling as a top category of comments on agent F# code. |
| [fsharp-idiom-review](skills/fsharp-idiom-review/SKILL.md) | Gives a checklist with before/after examples that the agent applies to its own F# diff: records instead of tuples, options instead of out parameters, `match` instead of `if`/`elif` chains or `let mutable`, no list indexing, single-pass collection code, `match!`, `static member val`, and syntax APIs instead of string concatenation. It links to `parse-dont-validate` for modeling. | Agents write C#-shaped F#, most of all when they port C#. The compiler accepts it. Review evidence ranks idiomatic shape and collection efficiency among the strongest categories of human comments on agent F# code. Codex and opencode sessions hold 5 user corrections on this subject. |
| [fsharp-verify-api](skills/fsharp-verify-api/SKILL.md) | Lists the real signatures of a package version before F# code uses them, and checks opens, references, existing helpers, and `.fsx` `#r` lines. | Agents write the API that they remember. FS0039 is the top compiler error in agent sessions, and each wrong guess costs a failed build. |

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
Compare printed example outcomes with the findings documents. The IWSAM and environment runners do not assert these runtime outcomes.
The failure-path runner, `scripts/run.ps1`, asserts its outcomes. It fails when an unsafe form does not fail or a safe form does not report the failure.

The idiom review skill includes a runner, `scripts/run.ps1`. It requires the .NET 10 SDK and PowerShell 7.2 or later.
The runner runs `scripts/Idioms.fsx`. It fails when a before form and its after form give different results, or when `static member val` does not keep one instance.

The API verification skill includes `scripts/show-api.ps1`, which lists the public API of a NuGet package version. It requires the .NET 10 SDK, PowerShell 7.2 or later, and NuGet access.
Its runner, `scripts/run.ps1`, lists Expecto 10.2.3 and 11.1.1, an `FSharp.Core` module function, and an extension method. It fails when an expected member is missing or a removed member is present.

The Native AOT skill includes a project-based runner, `scripts/run.ps1`. It requires the .NET 10 SDK, PowerShell 7.2 or later, and NuGet access. It also requires the platform Native AOT toolchain: MSVC and the Windows SDK on Windows, or clang on Linux.
The runner builds and publishes a probe app and compares JIT output with native exe output. It fails when a probe result differs from the expected verdict or the expected native text. Compare the printed results with the skill's findings document.

The async composition skill includes a runner, `scripts/run.ps1`. It requires the .NET 10 SDK, PowerShell 7.2 or later, and NuGet access for IcedTasks.
The runner runs `scripts/Proofs.fsx` and fails when a cancellation, exception, start, or ValueTask fact differs. It also builds `scripts/StateMachine` in Release and checks that FS3511 is reported only for the `let rec` case.

The parsing and compiler-performance skills provide guidance. Apply their verification steps to the target project.

## Evaluate a skill

The [eval runner](evals/README.md) measures whether a skill changes an agent's results. It runs each task with and without the skill in Claude Code, Codex CLI, or opencode, and grades the output with scripts.
It requires PowerShell 7.4 or later, the agent CLIs you test, and the prerequisites of the skill's graders.

```powershell
pwsh ./evals/run-evals.ps1 -Skill fsharp-native-aot -Target claude:sonnet,codex
```

The runner starts agents without permission prompts. Read the caution in the eval README before you run it.
Eval tasks exist for each skill. See the [eval README](evals/README.md) for the task list.

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
