# F# skills

Reusable instructions for AI agents working on F# code, packaged in the [Agent Skills format](https://agentskills.io/home).
The skills cover domain design, dependency management, error composition, and compiler performance.

## Skills

| Skill | What it does | Why it exists |
| --- | --- | --- |
| [parse-dont-validate](skills/parse-dont-validate/SKILL.md) | Parses raw input into domain types and preserves their invariants through updates and conversions. | Makes invalid states harder to construct and reduces repeated checks on primitive values. |
| [optimize-fsharp-typecheck-graph](skills/optimize-fsharp-typecheck-graph/SKILL.md) | Uses compiler dependency graphs and timing reports to investigate F# build performance. | Separates measured build improvements from graph changes and checks source and binary compatibility. |
| [fsharp-iwsam-errors](skills/fsharp-iwsam-errors/SKILL.md) | Composes `Result` errors through interfaces with static abstract members (IWSAM). The caller selects a concrete error type. | Reduces repeated `Result.mapError` conversions and uses compiler constraints to require the error cases needed by a call tree. |
| [fsharp-env-capabilities](skills/fsharp-env-capabilities/SKILL.md) | Passes dependencies through a generic environment with small `IProvideX` capability interfaces. | Lets the compiler infer dependency requirements and lets tests supply only the dependencies a function needs. |

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
Use parse-dont-validate to model this input with private constructors and explicit parse errors.
```

```text
Use optimize-fsharp-typecheck-graph to measure this project's type-checking bottleneck and evaluate a compatible improvement.
```

Skill discovery and explicit invocation syntax depend on the agent. You can also direct the agent to the linked `SKILL.md` file.
Keep the skill's scripts and references with its entry point so relative links remain valid.

## Run the examples

The IWSAM and environment skills include F# scripts that require the .NET 10 SDK and NuGet access. Their runners require PowerShell 7.2 or later (`pwsh`).
Each `scripts/global.json` selects .NET 10. Run the supplied runner so SDK selection starts in that directory.
The F# 8 compiler can report `FS0192` for the IWSAM examples.
Read the selected skill's **Verify** section for its runner and expected compiler diagnostics.
Compile-time break tests intentionally fail compilation. Their runners check for the expected diagnostics.
Compare printed example outcomes with the findings documents. The runners do not assert these runtime outcomes.

The parsing and compiler-performance skills provide guidance. Apply their verification steps to the target project.

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
