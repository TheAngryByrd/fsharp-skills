# F# skills

Reusable instructions for AI agents working on F# code, packaged in the [Agent Skills format](https://agentskills.io/home).
Each skill explains a specific design pattern and includes references and runnable F# examples.

## Skills

The two skills below are being migrated. Their files must be published before the links and usage instructions are available from a fresh clone.

| Skill | What it does | Why it exists |
| --- | --- | --- |
| [fsharp-iwsam-errors](skills/fsharp-iwsam-errors/SKILL.md) | Composes `Result` errors through interfaces with static abstract members (IWSAM). The caller selects a concrete error type. | Reduces repeated `Result.mapError` conversions and uses compiler constraints to require the error cases needed by a call tree. |
| [fsharp-env-capabilities](skills/fsharp-env-capabilities/SKILL.md) | Passes dependencies through a generic environment with small `IProvideX` capability interfaces. | Lets the compiler infer dependency requirements and lets tests supply only the dependencies a function needs. |

The patterns can work together: the environment supplies capabilities, and IWSAM interfaces describe possible errors.

## Use a skill

1. Clone this repository:

   ```sh
   git clone https://github.com/TheAngryByrd/fsharp-skills.git
   ```

2. Follow your agent's skill installation instructions. Copy the complete selected skill directory into its configured skills directory.
3. Ask the agent to use the skill for a specific task.

Example requests:

```text
Use fsharp-iwsam-errors to compose these Result-returning functions and select an error type for the caller.
```

```text
Use fsharp-env-capabilities to replace these dependency parameters with a capability environment that supports test fakes.
```

Skill discovery and explicit invocation syntax depend on the agent. You can also direct the agent to the linked `SKILL.md` file.
Keep the skill's scripts and references with its entry point so relative links remain valid.

## Run the examples

The bundled F# scripts require the .NET 10 SDK and NuGet access. The verification runners require PowerShell.
Read the selected skill's **Verify** section for its runner and expected compiler diagnostics.
Compile-time break tests intentionally fail compilation. Their runners check for the expected diagnostics.

## Create or change a skill

Follow [skills/README.md](skills/README.md) and use [skills/SKILL.md.template](skills/SKILL.md.template).
The template is not an installable skill.

Keep the skill list, purpose, prerequisites, and usage instructions in this README aligned with the skill files.
For project knowledge and maintenance rules, start with the [Lode README](lode/readme.md).
