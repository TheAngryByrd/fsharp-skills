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
- The prerequisites of the skill's graders. The `fsharp-native-aot` graders need the .NET 10 SDK, NuGet access, and the Native AOT toolchain. Use `-SkipNative` without the toolchain. The `fsharp-nullness-interop` graders need the .NET 10 SDK and NuGet access. The `fsharp-env-capabilities` `startup-settings` grader needs the .NET 10 SDK and NuGet access for the `Microsoft.Extensions` 10.0.0 packages. The `fsharp-library-api-design` graders need the .NET 10 SDK, and the `minor-release` grader runs `public-surface.ps1` from `skills/fsharp-signature-files`. Its grader tests need NuGet access.

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
- `run.json`: the run's settings, metrics, checks, skill name, start time, skill commit, and exact model. [Dashboard](#dashboard) describes the last four.

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

## Dashboard

The dashboard is a static page that compares runs with a skill and runs without it. It has one row for each skill, task, and target. It is published at https://theangrybyrd.github.io/fsharp-skills/.

The page reads result sets that are committed in `evals/results/`. A result set is the path-free copy of one result folder.

### Export a result set

Run this command after a run, or after you grade a result folder again:

```powershell
pwsh ./evals/export-results.ps1 -ResultDir <OutputRoot>/<run-id>
```

The script writes `evals/results/<skill>/<run-id>.json`. Commit this file in the same pull request as the skill or eval change that the runs measure.

| Parameter | Default | Meaning |
|---|---|---|
| `-ResultDir` | required | A result folder that holds `r*/run.json` files. The script does not read `results.json`, so a partial folder also exports. |
| `-ResolvedModel` | none | A hashtable from target label to exact model, for example `@{ 'claude:sonnet' = 'claude-sonnet-5-5' }`. The script uses an entry only for a run that has no `resolvedModel`. |
| `-ResultsRoot` | `evals/results` | Parent folder of the result sets. |
| `-UserName` | your account name | The user name that the script refuses in retained text. If your user name is also a word in check text or an agent name, such as `claude`, pass `''` to turn off this check. |
| `-Force` | off | Replaces an existing result set that has different content. |

- The script keeps only these fields of each run: `target`, `agent`, `model`, `resolvedModel`, `task`, `mode`, `run`, `invocation`, `isolated`, `startedAt`, `skillCommit`, `skillDirty`, `exitCode`, `timedOut`, `seconds`, `inputTokens`, `outputTokens`, `costUsd`, `turns`, `failedBuilds`, `skillUsed`, `globalSkillUsed`, and the `text` and `passed` values of each check. It drops `workspace`, `command`, and the check evidence, because they hold local paths and user names.
- The script does not rewrite text. It refuses the result set when a retained text field (`target`, `agent`, `model`, `resolvedModel`, `task`, `invocation`, `skillCommit`, or the `text` of a check) holds a backslash, a `~/` path, a drive path such as `C:/x`, a word that starts with one or more `/` (`/opt/data/x.fs`, `//server/x`), or your user name as a whole word (3 or more characters, any case). The error names the run and the field, and no file is written. The error does not repeat the text. Change the grader so that its check text and target labels hold no local paths and no user name. A URL (`https://a/b`), a relative path (`a/b`), and a number such as `12:30/24` pass. A private word with no path syntax, for example a client name that a check prints alone, is not detected. Read `git diff` of a new result set before you commit it.
- The script finds the skill from `skill` in `run.json`. A run from an older runner has no `skill`, so the script reads it from the `evals.json` that defines the task.
- The script fails when a run has no exact model and `-ResolvedModel` has no entry for its target. Every dashboard row names the exact model of its target. The page build also rejects a committed run with an empty `resolvedModel`.
- The result folder name must be the run id (`yyyyMMdd-HHmmss`). The script and the page build reject any other name.
- The script writes the file to a temporary file in the same folder and then moves it over the target, so an interrupted export keeps the previous file.
- A second export of the same folder writes the same file. When the file exists with different content, the script stops unless you use `-Force`.

The runner records the exact model in `resolvedModel`:

- Claude Code: the model name that most assistant messages in `transcript.jsonl` carry. It falls back to the `init` event. When the transcript has no model, the model is unknown, and the export needs `-ResolvedModel`. The runner never records the target alias (`sonnet`) as an exact model.
- Codex: the `-m` value, or `model` from `~/.codex/config.toml` (`$CODEX_HOME/config.toml` when `CODEX_HOME` is set). It adds `model_reasoning_effort` from the same file. With `-Isolate` and no `-m` value, the model is unknown, and the export needs `-ResolvedModel`. The model is also unknown when `config.toml` has a top-level `profile` key of any value form and there is no `-m` value, because the profile can change the model. The runner reads `model` and `model_reasoning_effort` as basic strings (`"..."`) or literal strings (`'...'`). The runner reads the Codex and opencode model before it starts the agent, so a change of `config.toml` during the run does not change the label.
- opencode: the target model text. The transcript does not record the model.

The runner also records `skill`, `startedAt` (UTC), `skillCommit` (`git rev-parse HEAD`), and `skillDirty` in each `run.json`. The runner reads `skillCommit` and `skillDirty` again for each run, just before the agent starts, so a change during a long batch shows in the runs that follow it. `skillDirty` is `true` when `git status --porcelain` prints a line for `skills/<skill>`, `evals/<skill>`, or `evals/lib`. These paths hold the skill, its tasks and graders, and the shared runner and grader code. `grade-evals.ps1` keeps these fields, so a result folder that you grade again keeps the commit of its runs.

### Build the page

```powershell
pwsh ./evals/dashboard/build-dashboard.ps1 -OutDir <dir>
```

Commit links on the page point to `$GITHUB_SERVER_URL/$GITHUB_REPOSITORY` when both variables are set (they are in GitHub Actions), and to https://github.com/TheAngryByrd/fsharp-skills otherwise. The build writes this address to `repoUrl` in `data.js`.

Open `<dir>/index.html` in a browser. The page also works from `file://`, because the data is in `data.js`. Use `-ResultsRoot` to read result sets from another folder. A folder with no result sets gives a page that lists each skill with "No results yet".

### Publish the page

The workflow `.github/workflows/eval-dashboard.yml` runs on manual dispatch and on a push to `master` that changes one of these paths:

- `evals/results/**`
- `evals/dashboard/**`
- `evals/lib/**`
- `evals/export-results.ps1`
- `evals/run-evals.ps1`
- `evals/tests/**`
- `evals/*/evals.json`
- `skills/*/SKILL.md`
- `.github/workflows/eval-dashboard.yml`

It runs `evals/tests/Dashboard.Tests.ps1` and `evals/tests/Metrics.Tests.ps1`, builds the page, and deploys it with GitHub Pages.

The repository maintainer must set **Settings > Pages > Source** to **GitHub Actions** one time. Until then, the deploy job fails.

### Verdicts

Each row compares the newest result set of one target, one exact model, and one task. When runs of one target used two models, the page shows one row for each model, and no comparison mixes models. A row whose newest result set is older than the newest result set of another model of the same target has the label "older model". A run with the skill counts only when the transcript shows skill use, the same rule as `summary.md`. The pass rate is the mean, over counted runs, of passed checks divided by graded checks. The first rule that matches gives the verdict. The thresholds are in one table at the top of `evals/dashboard/Dashboard.psm1`.

| Verdict | Rule |
|---|---|
| Not comparable | A mode has no counted run, or no counted run has a graded check. |
| Better | The pass rate with the skill is higher by 10 points or more. |
| Worse | The pass rate with the skill is lower by 10 points or more. |
| Less effort | The pass rate is within 10 points, and mean failed builds are lower by 1 or more, or mean turns are lower by 25% or more. |
| No change | All other cases. |

A row shows "too few runs" when a mode has fewer than 3 counted runs. These thresholds are heuristics, not statistical tests.

Test the export, the aggregation, and the build with the fixtures in `tests/fixtures/results/`:

```powershell
pwsh ./evals/tests/Dashboard.Tests.ps1
```

The script exits with code 1 and lists each failed check.

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

[lib/Grading.psm1](lib/Grading.psm1) has helpers for JSON answers, workspace copies, .NET builds, and grader probes. `ConvertFrom-ProbeOutput` makes one check from each `PASS <name>` or `FAIL <name>` line of a grader probe. `Get-ProbeScript` reads a grader probe and adds `open X.X` after `open X` when the agent's script declares `module X =`. Test these two helpers with `pwsh ./evals/tests/Grading.Tests.ps1`. `Get-TranscriptCommands` returns each shell command in a `transcript.jsonl` from Claude Code, Codex, or opencode. A grader finds the transcript at `<OutDir>/../transcript.jsonl`. `Invoke-JitAndNative` builds a project and runs it. It then checks that `PublishAot` evaluates to `true`, publishes the project, and runs the native exe.

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
| `fsharp-env-capabilities` | `startup-settings` | Settings validation at startup for a shipping app with `appsettings.json`. The grader runs `App.fsx` with valid settings, with no `BlockedRegions` key, with `FreeShippingOver` set to `0`, which is valid, with bad values and missing keys, with out-of-range values (the same file also omits `Carrier` and has a three-letter region code), and with no `Shipping` section. Invalid settings must stop the app before it prints `ready`, and the error must name each bad key. `ShippingTests.fsx` must print the expected quotes with no `appsettings.json` and no configuration or Options types. Functions in `Shipping.fsx` must not take `IOptions` or `IConfiguration`. Two rubric checks ask whether the functions read a parsed type, not the bound DTO, and whether they get the settings from the env. |
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
| `fsharp-signature-files` | `minimal-surface` | Signature files for a three-file library. The prompt names each requirement. `Sku.fs`, `Stock.fs`, and `Pricing.fs` must each have their `.fsi` directly before them, with no FS3888 or FS0050 warning. The grader restores the original Shop and tests: Shop must print the same report, and the tests must pass. The normalized public surface must equal an expected list, so a test-only helper must be `internal` with `InternalsVisibleTo`. The XML file must keep each public doc comment. Probe consumers must fail to build a `Sku` record, a `Quantity` case, or an unqualified `StockLevel` case, and to call the test-only helper. |
| `fsharp-signature-files` | `add-signatures` | The same input and grader. The prompt asks only for signature files that encapsulate the library, so the hidden representations, the `internal` test-only helper, and the doc comments must come from the skill. |
| `fsharp-performance-types` | `sensor-report` | A rewrite of a slow F# summary over 200,000 readings, keyed by site and sensor, with a `Map` of offsets in the signature. The grader restores the original tests, builds a bench against the public signatures, and compares the output with the original code on generated inputs under `de-DE`. It also compares the output at production size. It then measures the allocated bytes and the median run time of one call of `summarize` and `render` against a reference solution in the same process. A crash, a timeout, or a missing result fails the check. |
| `fsharp-serialization` | `billing-codec` | A change to `Codec.fsx` so that orders follow a billing service JSON contract while stored customer JSON keeps its FSharp.SystemTextJson default shape. A grader probe decodes the three saved order samples and compares the parsed JSON that `encodeOrder` writes with each sample. It also checks `null` and absent optional values, unknown properties, missing or `null` required fields, unknown union tags, the JSON `null`, and malformed JSON. `decodeOrder` must return `Error` and not throw. The stored customer samples must decode and encode unchanged. A text check reads `Codec.fsx` and each file that it loads, without comments and string contents, and fails when the code names `JsonDocument`, `JsonNode`, `JsonObject`, `JsonArray`, `JsonValue`, `JsonElement`, `Utf8JsonReader`, `Utf8JsonWriter`, or `JsonConverter<`. |
| `fsharp-binary-compatibility` | `shipping-1-1` | Version 1.1.0 of a library with an express price, a declared value, and a new `Held` status that the prompt puts in the middle of the lifecycle. The grader builds the released 1.0.0 source and `LegacyApp` against it. It copies the new `Shipping.dll` next to that consumer with no rebuild and runs it. The output must not change, with no `MissingMethodException`, `TypeLoadException`, or `MissingFieldException`. `apicompat` must find no break from 1.0.0. A `NewApp` that is rebuilt against 1.1.0 must print the new features, with no result value written in its source. A reflection probe must find the express price, the insured price, and a function that reads `HD` as `Held` in the new `Shipping.dll`, and `statusOf "HD"` must return `Held`. The transcript must show a command that ran package validation, `apicompat` on two versions, `sig-diff.ps1`, or two `--sig` builds: one of `release-1.0.0` and one of another folder. A command counts only when its output holds the tool's result text. |
| `fsharp-binary-compatibility` | `feed-codes` | The same features and grader, with a hidden old consumer that the agent does not see. It also reads the code `HD`, which 1.0.0 reports as unknown. An existing function that starts to return `Held` changes that consumer's output. `Held` can be in any public union, in both tasks. `statusOf "HD"` does not have to return `Held`. |
| `fsharp-library-api-design` | `minor-release` | Two features in an F# library released as 1.1.0: an optional idempotency key on `PaymentClient.Charge`, and `ChargeAll` for any sequence. The grader restores the original `Checkout` (F#, `TreatWarningsAsErrors`) and `CheckoutCs` (C#). Both must build against the new library and print the same output. Both must also run unchanged with the new DLL after a build against 1.0.0. No 1.0.0 public surface line may be removed, and new members must not take F#-only parameter types or return an option, function, or `Async`. Two C# probes check the features. |
| `fsharp-library-api-design` | `classify-changes` | Ten proposed changes to the same library in `PROPOSED.md`. For each change, `answer.json` says whether `Checkout` and `CheckoutCs` (both with `TreatWarningsAsErrors`) fail to build or print a different output, whether their 1.0.0 builds fail with the changed DLL, and whether package validation reports an error. One check for each change compares the four answers with `classify-expected.json`. |

Test the `startup-settings` grader against a known good result, the input with an `Options.Create` test, `ValidateOnStart` with no startup validator call, an app that prints only the first error, a `decimal` `FreeShippingOver` field, a test that fails when `appsettings.json` exists, a parser that rejects `FreeShippingOver` `0`, a parser that accepts `MaxWeightKg` `0`, a region check with no length rule, a region check that requires only a non-empty code, a `Carrier` check that rejects only `""`, and a parser that skips the `RatePerKg` and `FreeShippingOver` range rules:

```powershell
pwsh ./evals/fsharp-env-capabilities/tests/Grader.Tests.ps1
```

Test the `fsharp-signature-files` grader against known good results and bad results:

```powershell
pwsh ./evals/fsharp-signature-files/tests/Grader.Tests.ps1
```

Test the `fsharp-serialization` grader against a known good result, a `module Codec =` copy, a DTO layer, a test file, comments, and strings that name `JsonNode` or `#load` it, a DTO that rejects unknown line properties, a DTO that reads a missing `reserved` as empty, a DTO without per-field `null` checks, a `decodeCustomer` with an `exn` error type, an `exit 0` in `decodeOrder`, the original input, a deleted `Codec.fsx`, an edited `Domain.fsx`, a `JsonObject` parser, a loaded helper that uses `JsonDocument` (normal and verbatim `#load` paths), one options value for customers and orders, `WhenWritingNull`, and `WithSkippableOptionFields()` without `deserializeNullAsNone`:

```powershell
pwsh ./evals/fsharp-serialization/tests/Grader.Tests.ps1
```

Test the `minor-release` grader against a known good result, the original input, five breaking changes, and seventeen cases for the C# surface, the probes, time limits, new dependencies, and FSharp.Core versions. It also checks the dependency version rule of the binary swap. Test the `classify-changes` grader against a correct answer, common mistakes, a string value, a missing change, and no answer:

```powershell
pwsh ./evals/fsharp-library-api-design/tests/Grader.Tests.ps1
pwsh ./evals/fsharp-library-api-design/tests/Classify.Tests.ps1
```

Measure each expected value in `classify-expected.json` on real builds. The script applies each change to the input library, runs the `minor-release` grader for the source and binary results, and packs with package validation:

```powershell
pwsh ./evals/fsharp-library-api-design/tests/Classify.Expected.Tests.ps1
```

Test both `fsharp-verify-api` graders against a known good result, the stub, old API code, and a package downgrade:

```powershell
pwsh ./evals/fsharp-verify-api/tests/Grader.Tests.ps1
```

Test the `fsharp-performance-types` grader against a known good result, the original input, an idiomatic pipeline, and one defect for each grader rule (culture format, culture sort, tuple key, `Map.tryFind` for each reading, wrong or failed output only at production size, a finite mean for an infinite sum, a stale or intermittent result during measurement, a crash or an exit during measurement, forged `PASS` lines with an exit code of 0 or 3, a hang on a test input, a child process that outlives the bench, more than 16 MB of output, a last-input cache around the original code, a negative zero mean, a struct tuple `sortBy` key, an output folder with `&` in its path, a changed signature, and a missing project):

```powershell
pwsh ./evals/fsharp-performance-types/tests/Grader.Tests.ps1
```

Test the `fsharp-binary-compatibility` graders against good results for both tasks, a naive result, each single break, a project with package validation, `statusOf` that returns `Held` in `feed-codes`, a `NewApp` that prints fixed text, features that only `NewApp` computes, features on `Parcel` members or on a class, a missing `NewApp`, a failed `dotnet pack`, a failed or break-reporting `apicompat`, two `--sig` builds with no `release-1.0.0` build, skipped `--sig` builds, a quoted path with a space, a class whose constructor blocks, and the original input. Test the tool check against real and read-only commands. Add `-Case <name>` to run only some grader cases:

```powershell
pwsh ./evals/fsharp-binary-compatibility/tests/Grader.Tests.ps1
pwsh ./evals/fsharp-binary-compatibility/tests/CompatibilityCommand.Tests.ps1
```
