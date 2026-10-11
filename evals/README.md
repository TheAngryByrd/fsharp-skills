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
- For rubric checks, Claude Code (`claude`) signed in, or another judge command. See [Rubric checks](#rubric-checks).
- The prerequisites of the skill's graders. The `fsharp-native-aot` graders need the .NET 10 SDK, NuGet access, and the Native AOT toolchain. Use `-SkipNative` without the toolchain. The `fsharp-nullness-interop` graders need the .NET 10 SDK and NuGet access.

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

Results go to `<run-id>/summary.md` and `<run-id>/results.json`. The summary shows the counted runs, pass rate, skipped checks, time, tokens, mean turns, and mean failed builds for each target, task, and mode. It also lists each check with its result in both modes.

## Effort metrics

Some skills do not change the pass rate. The agent finishes without the skill, but only after many failed builds. Each `run.json` records two values that show this effort:

- `turns`: the number of agent turns.
  - Claude Code: `num_turns` from the final `result` event. A stopped run has no `result` event. For that run, the runner uses the number of tool calls plus 1.
  - Codex: the number of completed tool items (commands, file changes, and other tools) plus 1. Codex does not report each model request.
  - opencode: the number of `step_finish` events.
- `failedBuilds`: the number of failed build calls. A failed build call is a shell command that runs `dotnet build`, `dotnet test`, `dotnet run`, or `dotnet fsi`. It also exits with a non-zero code or prints an `error FS<number>` line. The runner removes a `pwsh -Command` or `bash -lc` wrapper and ignores text in quotes. `dotnet` must then start a command, for example after `&&`, `;`, or `|`. So `rg 'dotnet build'` is not a build call, but `& "C:\Program Files\dotnet\dotnet.exe" build` is. The runner reads the exit code from the Claude Code `is_error` flag, the Codex `exit_code`, and the opencode `metadata.exit` or `error` status.

Each agent counts turns in a different way. Compare turns between modes of one target, not between agents. A value is `null` when the transcript is missing or empty.

A dry run (`-DryRun`) starts no agent and writes no transcript, so it does not parse metrics. To check the values, use a real run. For example, the opencode run of `fix-checkout` without the skill has 13 `step_finish` events and 3 `dotnet fsi` calls with exit code 1, and the runner records `turns` 13 and `failedBuilds` 3.

Test the metric parser and the summary with the transcript fixtures in `tests/fixtures/`:

```powershell
pwsh ./evals/tests/Metrics.Tests.ps1
```

The script exits with code 1 and lists each failed check.

## Grade again

After you change a grader, grade an existing result folder again. The agents do not run again.

```powershell
pwsh ./evals/grade-evals.ps1 -ResultDir <OutputRoot>/<run-id>
```

Use `-Task` to grade only some tasks. The script updates each `run.json`, `results.json`, and `summary.md`. It keeps the `turns` and `failedBuilds` values in each `run.json`. When a `run.json` does not have these values, the script reads them from `transcript.jsonl`.

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

[lib/Grading.psm1](lib/Grading.psm1) has helpers for JSON answers, workspace copies, .NET builds, and grader probes. `ConvertFrom-ProbeOutput` makes one check from each `PASS <name>` or `FAIL <name>` line of a grader probe. `Get-ProbeScript` reads a grader probe and adds `open X.X` after `open X` when the agent's script declares `module X =`. Test these two helpers with `pwsh ./evals/tests/Grading.Tests.ps1`. `Invoke-JitAndNative` builds a project and runs it. It then checks that `PublishAot` evaluates to `true`, publishes the project, and runs the native exe.

## Rubric checks

Some problems do not cause a compiler error or a test failure: non-idiomatic F# shape, speculative code, and missed reuse. A rubric check sends the agent's diff to a separate judge model with yes/no questions.

Add a `rubric` array to the task in `evals.json`:

```json
"rubric": [
  {
    "id": "direct-composition",
    "question": "Does placeOrder call each leaf function directly in the result computation expression, with no error conversion such as Result.mapError, a lambda, or a wrapper case on the call?"
  }
]
```

Then call the shared function from the task's grader:

```powershell
$checks += Invoke-Rubric -Workspace $Workspace -EvalDir (Split-Path $PSScriptRoot) -TaskId 'my-task'
```

`Invoke-Rubric` returns one check for each rubric item, in the normal grader contract. The check text is `Rubric <id>: <question>`. The summary pairs checks by text, so grade old results again after you change a question.

- The judge receives only the rubric questions and the diff. It does not see the mode or the skill text. The diff compares the task `files` (`before/`) with the workspace (`after/`). It does not contain `TASK.md`, `.claude/`, `.agents/`, `.opencode/`, `.git/`, `bin/`, or `obj/`. The function replaces the install name `<skill>-eval` with `<skill>` in the diff. Other text that the agent writes, such as a comment about a skill, can still get to the judge.
- The diff is `git diff --no-index --ignore-cr-at-eol --no-ext-diff --no-textconv`. `--ignore-cr-at-eol` keeps line-ending changes out of the diff. `--no-ext-diff` and `--no-textconv` are necessary because an external diff tool in your git config writes no hunks.
- The function decodes the output of `git` and of the judge as UTF-8. On Windows, the console code page otherwise changes non-ASCII code, and the quotes then do not match the diff.
- The judge must answer `yes` or `no` and give a quote from the diff. The check passes for `yes` and fails for `no`. The evidence is the answer and the quote.
- The quote must be part of one added (`+`) or removed (`-`) line in a diff hunk. An unchanged context line, a file header, an `@@` line, a quote on more than one line, and a quote shorter than 4 characters do not count. The function removes the `+` or `-` marker and collapses whitespace before it compares. A removed line counts, so that an item can ask about code that the agent removed.
- The function skips a check (`passed` is null) when the quote does not count, when the judge does not answer the item, when the judge fails, or when the judge output has no `items` array. It also skips all checks when `git` is missing, when `SKILL_EVAL_JUDGE` is not valid, or when a rubric item has no `id` or no `question`. A skipped check does not count as a pass or a failure, and the other checks of the grader stay.
- After the function reads `evals.json`, it does not throw. A malformed `evals.json` still throws.
- The function cuts the diff at 60,000 characters.

Write rubric items with these rules:

- Make `yes` the good answer, so that a pass means the result is good.
- Ask one question about one thing in the code. Name the function or type.
- Ask about something that a diff line can show. A question about an absence, such as "is every new type used", gets a weak quote: any added line.
- Give a concrete example of the good or bad shape in the question.
- Remove ambiguous words. A question that two readers can answer differently gives different answers on each grade. For example, "in one interface implementation" can mean one interface block in total or one block for each leaf. The `iwsam-refactor` `single-edge` question says that one interface block for each leaf counts as yes.
- Before you use a rubric, grade the same workspaces two or more times and compare the answers.

The judge command comes from the `SKILL_EVAL_JUDGE` environment variable, as a JSON array of the command and its arguments. The judge reads the prompt from stdin and must write JSON with the shape `{"items":[{"id":"...","answer":"yes","quote":"..."}]}`. Claude Code `--output-format json` output with `structured_output` also works. Set `SKILL_EVAL_JUDGE` to `off` to skip all rubric checks.

The default judge is Claude Code with the `haiku` model and a JSON schema for the answer (`--json-schema`). It runs in an empty temp directory with no tools, no skills, no setting sources, no MCP servers, and its own system prompt, so the judge does not load your `CLAUDE.md` or skills. To use a different model, set the full command. This example uses `sonnet` and no schema:

```powershell
$env:SKILL_EVAL_JUDGE = '["claude","-p","--model","sonnet","--tools","","--disable-slash-commands","--no-session-persistence","--strict-mcp-config","--setting-sources","","--system-prompt","You review code changes against a rubric.","--output-format","json"]'
```

Keep `--system-prompt` in a Claude Code judge command. Without it, the judge gets the normal Claude Code system prompt and the user's instructions.

### Agreement

The `iwsam-refactor` rubric (4 items) graded the 6 `iwsam-refactor` runs of one result folder (Claude Code, Codex, and opencode, with and without the skill) three times with the default judge. All 24 items gave the same answer in all three grades (24/24).

The `port-order-report` rubric (5 items) graded the 6 `port-order-report` runs of one result folder (Claude Code, Codex, and opencode, with and without the skill) three times with the default judge. All 30 items gave the same answer in all three grades (30/30), and no item was skipped. The `totals-record` item was `no` in all three grades for each of the 3 runs without the skill.

### Tests

The rubric function has tests with a fake judge. They do not call a model:

```powershell
pwsh ./evals/tests/Rubric.Tests.ps1
```

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
| `fsharp-iwsam-errors` | `iwsam-refactor` | A refactor from nested error unions with `Result.mapError` to IWSAM leaves. The demo output must not change. Four rubric checks review the composition, the edge type, kept validation logic, and speculative types. |
| `fsharp-env-capabilities` | `pinned-leaf` | A fix for a leaf whose `#IProvideX` env was pinned to the first caller (FS0064, then FS0193). |
| `fsharp-env-capabilities` | `deterministic-salt` | A test env with fixed salt bytes. The accessor must not expose `System.Random`, and the fake must not subclass it. |
| `parse-dont-validate` | `registration` | Parsed domain types with private representations. A grader probe calls the refactored functions, and two scripts must fail to compile. |
| `fsharp-async-composition` | `cancel-bridge` | A non-blocking `handle` over an Async library. A grader probe cancels the token and checks that the work stops. For a bad id, the task must fault with the original `ArgumentOutOfRangeException`. The grader probe also checks the fire-and-forget audit. |
| `fsharp-async-composition` | `dashboard-load` | Concurrent panel loads over a Task-based client. A grader probe checks that `PanelNotFound` becomes `Error`. `Async.AwaitTask` wraps `PanelNotFound` in `AggregateException`. The missing panel must cancel a slow sibling. Each retry must call the client again. |
| `fsharp-async-composition` | `valuetask-port` | A port of `IFrameSource.ReadAsync` to `ValueTask<int>`. A grader probe uses a pooled source that throws when one `ValueTask` is read twice. |
| `fsharp-nullness-interop` | `enable-nullness` | Nullness and warnings as errors turned on in the delivered project, a clean build after FS3261 and FS0041 fixes, no unexplained suppression, unchanged signatures, and documented results for null inputs. |
| `fsharp-nullness-interop` | `hidden-nulls` | Fixes for null leaks that build clean with nullness on (`string x`, `Some (call ())`, `nonNull`, `Unchecked.nonNull`). A driver runs each function with null inputs. |
| `optimize-fsharp-typecheck-graph` | `false-edges` | The global `AutoOpen` module that gates every file, a fix that removes the false edges, and no speed claim without three timed builds. |
| `fsharp-failure-paths` | `invoice` | `invoice` returns `Result`. A grader probe injects an empty order, a missing price, a failed price fetch, a missing currency setting, and two invalid lines. Each must return an `Error`. The errors for the missing price, the failed fetch, the missing setting, and the invalid lines must name their causes. A valid order must give the same summary. |
| `fsharp-idiom-review` | `port-order-report` | A port of a short C# class to an F# script. The class has a value tuple, an `out` parameter, an `if`/`else if` chain on strings, `foreach` accumulators, and an index loop. A grader probe checks the `render` text for seven orders under a culture with a comma decimal separator, including midpoint rounding, a zero discount for a known code, and both tier boundaries. Five rubric checks review the totals record, the option return, `match` on the code, no mutable accumulators, and no list index. |
| `fsharp-verify-api` | `cli-options` | Command-line parsing with `System.CommandLine` 2.0.0, whose API differs from the beta API that most models remember. The project must keep version 2.0.0 and build. The grader runs the app with valid options, a missing `--name`, `--count 0`, `--help`, and an unknown option. Models often know this API, so the task shows a small effect. |
| `fsharp-verify-api` | `order-props` | FsCheck 3.4.0 generators and a property check in an `.fsx` script. FsCheck 3 moved the F# API to `FsCheck.FSharp` and changed `Gen.sample` and `Config`. A grader probe samples the generators, checks the constraints, counts the property tests, and checks that a wrong total throws. The `#r` line must keep version 3.4.0. |

Test both `fsharp-verify-api` graders against a known good result, the stub, old API code, and a package downgrade:

```powershell
pwsh ./evals/fsharp-verify-api/tests/Grader.Tests.ps1
```
