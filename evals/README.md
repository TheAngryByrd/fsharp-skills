# Skill evals

The eval runner measures whether a skill changes an agent's results. It runs each task twice for each agent: once with the skill installed and once without it. Then it grades both results with a script.

Supported agents:

- Claude Code (`claude`)
- Codex CLI (`codex`)
- opencode (`opencode`)

## Prerequisites

- PowerShell 7.4 or later (`pwsh`) on Windows, Linux, or macOS.
- Each agent CLI that you test, installed, on `PATH`, and signed in.
- `git`, to make each workspace a repository. Codex and opencode stop the project skill search at the repository root.
- The prerequisites of the skill's graders. The `fsharp-native-aot` graders need the .NET 10 SDK, NuGet access, and the Native AOT toolchain. Use `-SkipNative` without the toolchain.

> [!CAUTION]
> The runner starts agents without permission prompts: `--dangerously-skip-permissions`, `--sandbox danger-full-access`, and `--auto`. An agent can run any command as your user. Run evals only on a machine or container that you trust with that access.

## Run

```powershell
pwsh ./evals/run-evals.ps1 -Skill fsharp-native-aot -Target claude:sonnet,codex,opencode:github-copilot/gpt-5.5
```

Parameters:

| Parameter | Default | Meaning |
|---|---|---|
| `-Skill` | required | Skill name. The runner reads `skills/<skill>/` and `evals/<skill>/evals.json`. |
| `-Target` | `claude` | One or more `agent[:model]` values. The model text goes to the agent's model option unchanged. |
| `-Task` | all | Task IDs from `evals.json`. |
| `-Mode` | `both` | `with`, `without`, or `both`. |
| `-Invocation` | `explicit` | `explicit` tells the agent to use the `<skill>-eval` skill. `implicit` tests whether the agent finds the skill from its description. |
| `-Runs` | `1` | Runs for each target, task, and mode. Use 3 or more before you compare pass rates. |
| `-TimeoutMinutes` | `30` | Time limit for one agent run. The runner stops the process tree at the limit. |
| `-SkipNative` | off | Graders mark native-exe checks as skipped. |
| `-Isolate` | off | Each run gets an empty home directory. See [Isolation](#isolation). |
| `-OutputRoot` | `<temp>/skill-evals` | Parent directory for results. |
| `-DryRun` | off | Prints the agent commands and does not start agents. |

The runner runs agents one at a time.

## Workspaces

Each run has its own directory under `<OutputRoot>/<run-id>/rNNN/`:

- `ws/`: the agent's workspace. It holds `TASK.md`, the task input files, and the agent's output.
- `transcript.jsonl` and `stderr.txt`: the agent's JSON event stream and error output.
- `grade/grading.json`: the grader's checks.
- `run.json`: the run's settings, metrics, and checks.

For a run with the skill, the runner copies the skill to `ws/.claude/skills/<skill>-eval/` and `ws/.agents/skills/<skill>-eval/`. Claude Code reads the first folder, Codex reads the second, and opencode reads both. The runner also changes the `name:` line to `<skill>-eval`. A global copy of the same skill can be an older version, and the distinct name keeps it from standing in for the version under test.

The workspace is in the temp directory, not in the repository. MSBuild and `dotnet` read `Directory.*.props` and `global.json` files from parent directories. A workspace inside a checkout can inherit settings that change the result.

Results go to `<run-id>/summary.md` and `<run-id>/results.json`. The summary shows the counted runs, pass rate, skipped checks, time, and tokens for each target, task, and mode. It also lists each check with its result in both modes.

## Grade again

After you change a grader, grade an existing result folder again. The agents do not run again.

```powershell
pwsh ./evals/grade-evals.ps1 -ResultDir <OutputRoot>/<run-id>
```

Use `-Task` to grade only some tasks. The script updates each `run.json`, `results.json`, and `summary.md`.

## Isolation

By default, agents run with your normal configuration. Runs without the skill can then load global skills on the same subject. The runner reads the `description` of each global skill and warns when it matches the eval's `contaminationKeywords`.

- Claude Code runs without the skill use `--disable-slash-commands`, which disables all skills. Claude Code runs with the skill can still load the global copies.
- Codex runs disable each matching global skill outside `~/.claude/skills` with `-c skills.config=[{path='...',enabled=false}]`.
- opencode runs deny each matching global skill by name through `OPENCODE_CONFIG_CONTENT`.
- The runner records `globalSkillUsed` when a transcript shows that the agent loaded a global copy.

With `-Isolate`, each run uses an empty home directory. The runner sets `HOME`, `USERPROFILE`, `XDG_CONFIG_HOME`, `XDG_DATA_HOME`, `CLAUDE_CONFIG_DIR`, and `CODEX_HOME` to that directory. Agents then cannot read your saved logins. Supply credentials as environment variables. Claude Code reads `ANTHROPIC_API_KEY` or `CLAUDE_CODE_OAUTH_TOKEN`. Codex reads `CODEX_API_KEY`. opencode reads the key of its provider. Providers that need a saved login, such as `github-copilot` in opencode, do not work with `-Isolate`. `NUGET_PACKAGES` keeps pointing at your NuGet cache.

opencode runs use `--pure`, which disables external plugins. Plugins can start background processes that keep running after the agent exits.

## Skill use

The runner reads each transcript and records whether the agent loaded the skill:

- Claude Code: a successful `Skill` tool call with the skill name, or a successful tool result that contains the skill's `name:` frontmatter line.
- Codex: command output that contains the skill's `name:` frontmatter line.
- opencode: a completed `skill` tool call with the skill name, or completed tool output that contains the `name:` frontmatter line.

A message that only names the `SKILL.md` path is not evidence of a load.

A run with the skill that did not load it compares the agent with itself. The runner prints a warning for each such run. The summary does not count these runs. Its `Not loaded` column shows how many runs it left out.

## Add evals for a skill

Create `evals/<skill>/evals.json`:

```json
{
  "skill": "my-skill",
  "contaminationKeywords": ["Words that identify a global skill on the same subject"],
  "tasks": [
    {
      "id": "short-task-id",
      "files": ["inputs/Example.fs"],
      "grader": "graders/short-task-id.ps1",
      "prompt": "The task text. Ask for files in the current directory, for example answer.json with a fixed shape."
    }
  ]
}
```

Make each task depend on a skill fact. The agent must not be able to guess that fact or check it with a normal build. A task that a cautious agent passes without the skill does not measure the skill.

A grader is a PowerShell script with this contract:

```powershell
param(
    [Parameter(Mandatory)][string]$Workspace,  # the agent's ws/ directory
    [Parameter(Mandatory)][string]$OutDir,     # write grading.json here
    [switch]$SkipNative
)
Import-Module (Join-Path $PSScriptRoot '../../lib/Grading.psm1') -Force
$checks = @()
$checks += New-Check 'Check text' $true 'evidence'
$checks += New-Check 'Check that needs a tool' $null 'skipped: reason'
Write-Checks (Join-Path $OutDir 'grading.json') $checks
```

`passed` is `$true`, `$false`, or `$null` for a skipped check. Grade by running the agent's output when possible, not by matching text. Before you use a grader, run it against a known good and a known bad workspace.

[lib/Grading.psm1](lib/Grading.psm1) has helpers for JSON answers, workspace copies, and .NET builds. `Invoke-JitAndNative` builds a project and runs it. It then checks that `PublishAot` evaluates to `true`, publishes the project, and runs the native exe.

## fsharp-native-aot tasks

| Task | What it checks | Native toolchain |
|---|---|---|
| `classify-formatting` | Verdicts for 17 F# format calls, fixes for the lines that throw or lose data, and no change to lines that work. | no |
| `diagnose-symptoms` | Causes and fixes for three native-only bugs, and whether `ReflectionFree` fixes them. The bug 2 fix runs in a native exe. | for one check |
| `logging-rewrite` | A rewrite of `OrderLogging.fs` with no classic format string holes. It must build, and its JIT and native output must equal the original JIT output. | for one check |
| `json-at-scale` | JSON for many F# records without one converter per record, with camelCase names and null for `None`. The delivered project must publish with Native AOT. | for two checks |

## Other skill tasks

| Skill | Task | What it checks |
|---|---|---|
| `fsharp-iwsam-errors` | `fix-checkout` | Fixes for FS0072, FS0366, and FS0331 in an IWSAM error design. The demo output must not change. |
| `fsharp-iwsam-errors` | `iwsam-refactor` | A refactor from nested error unions with `Result.mapError` to IWSAM leaves. The demo output must not change. |
| `fsharp-env-capabilities` | `pinned-leaf` | A fix for a leaf whose `#IProvideX` env was pinned to the first caller (FS0064, then FS0193). |
| `fsharp-env-capabilities` | `deterministic-salt` | A test env with fixed salt bytes. The accessor must not expose `System.Random`, and the fake must not subclass it. |
| `parse-dont-validate` | `registration` | Parsed domain types with private representations. A probe calls the refactored functions, and two scripts must fail to compile. |
| `optimize-fsharp-typecheck-graph` | `false-edges` | The global `AutoOpen` module that gates every file, a fix that removes the false edges, and no speed claim without three timed builds. |
