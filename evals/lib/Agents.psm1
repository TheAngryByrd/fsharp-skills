Set-StrictMode -Version Latest

$AgentMessage = 'Read TASK.md in the current directory and complete the task it describes. Work only inside the current directory.'

function ConvertTo-AgentTarget {
    param([Parameter(Mandatory)][string]$Spec)
    $agent, $model = $Spec -split ':', 2
    $agent = $agent.Trim().ToLowerInvariant()
    if ($agent -notin 'claude', 'codex', 'opencode') { throw "Unknown agent '$agent'. Use claude, codex, or opencode." }
    [pscustomobject]@{ Agent = $agent; Model = $(if ($model) { $model.Trim() } else { '' }); Label = $Spec.Trim() }
}

function Resolve-AgentCommand {
    param([Parameter(Mandatory)][string]$Agent)
    $cmd = Get-Command $Agent -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $cmd) { throw "Command '$Agent' was not found on PATH." }
    $cmd.Source
}

function Get-UserHome { [Environment]::GetFolderPath('UserProfile') }

function Find-ConflictingSkills {
    param([Parameter(Mandatory)][string]$Skill, [string[]]$Keywords = @())
    $userHome = Get-UserHome
    $dirs = @('.claude/skills', '.agents/skills', '.codex/skills', '.config/opencode/skills') | ForEach-Object { Join-Path $userHome $_ }
    foreach ($dir in $dirs | Where-Object { Test-Path $_ }) {
        foreach ($file in Get-ChildItem -Path $dir -Filter 'SKILL.md' -Recurse -Depth 2 -File -ErrorAction SilentlyContinue) {
            $description = (Get-Content $file.FullName -TotalCount 40 -ErrorAction SilentlyContinue | Where-Object { $_ -match '^description\s*:' } | Select-Object -First 1) -as [string]
            $name = $file.Directory.Name
            $hit = $name -eq $Skill -or @($Keywords | Where-Object { $description -match [regex]::Escape($_) }).Count -gt 0
            if ($hit) { [pscustomobject]@{ Name = $name; Path = $file.Directory.FullName; SkillFile = $file.FullName } }
        }
    }
}

function Get-InstallName {
    # A distinct name keeps global copies of the same skill, which can be older, from standing in for the version under test.
    param([Parameter(Mandatory)][string]$Skill)
    "$Skill-eval"
}

function Install-Skill {
    param([Parameter(Mandatory)][string]$SkillDir, [Parameter(Mandatory)][string]$Workspace)
    $name = Get-InstallName (Split-Path $SkillDir -Leaf)
    foreach ($base in '.claude/skills', '.agents/skills') {
        $dest = Join-Path $Workspace "$base/$name"
        New-Item -ItemType Directory -Force -Path $dest | Out-Null
        $root = (Resolve-Path $SkillDir).Path
        Get-ChildItem -Path $root -Recurse -File -Force |
            Where-Object { $_.FullName.Substring($root.Length) -notmatch '[\\/](bin|obj)[\\/]' } |
            ForEach-Object {
                $target = Join-Path $dest $_.FullName.Substring($root.Length).TrimStart('\', '/')
                New-Item -ItemType Directory -Force -Path (Split-Path $target) | Out-Null
                Copy-Item $_.FullName $target
            }
        $entry = Join-Path $dest 'SKILL.md'
        $text = [IO.File]::ReadAllText($entry)
        [IO.File]::WriteAllText($entry, ([regex]'(?m)^name:\s*\S+').Replace($text, "name: $name", 1))
    }
}

function Initialize-WorkspaceRepo {
    # Codex and opencode search for project skills up to the repository root. A repository here stops that search.
    param([Parameter(Mandatory)][string]$Workspace)
    if (Get-Command git -CommandType Application -ErrorAction SilentlyContinue) {
        git -C $Workspace init --quiet 2>&1 | Out-Null
    }
}

function Get-IsolatedEnvironment {
    param([Parameter(Mandatory)][string]$RunDir)
    $isoHome = Join-Path $RunDir 'home'
    foreach ($d in '.claude', '.codex', '.config', '.local/share') { New-Item -ItemType Directory -Force -Path (Join-Path $isoHome $d) | Out-Null }
    $nuget = if ($env:NUGET_PACKAGES) { $env:NUGET_PACKAGES } else { Join-Path (Get-UserHome) '.nuget/packages' }
    @{
        HOME                              = $isoHome
        USERPROFILE                       = $isoHome
        XDG_CONFIG_HOME                   = Join-Path $isoHome '.config'
        XDG_DATA_HOME                     = Join-Path $isoHome '.local/share'
        CLAUDE_CONFIG_DIR                 = Join-Path $isoHome '.claude'
        CODEX_HOME                        = Join-Path $isoHome '.codex'
        NUGET_PACKAGES                    = $nuget
        DOTNET_NOLOGO                     = '1'
        DOTNET_SKIP_FIRST_TIME_EXPERIENCE = '1'
        DOTNET_CLI_TELEMETRY_OPTOUT       = '1'
    }
}

function Get-AgentMessage {
    param([string]$Skill, [switch]$WithSkill, [ValidateSet('explicit', 'implicit')][string]$Invocation = 'explicit')
    if ($WithSkill -and $Invocation -eq 'explicit') { "Use the $(Get-InstallName $Skill) skill for this task. $AgentMessage" } else { $AgentMessage }
}

function Get-AgentArguments {
    param([Parameter(Mandatory)]$Target, [Parameter(Mandatory)][string]$Workspace, [Parameter(Mandatory)][string]$Message,
        [switch]$WithSkill, [object[]]$HiddenSkills = @())
    switch ($Target.Agent) {
        'claude' {
            $a = @('-p', '--output-format', 'stream-json', '--verbose', '--dangerously-skip-permissions', '--no-session-persistence')
            if ($Target.Model) { $a += @('--model', $Target.Model) }
            if (-not $WithSkill) { $a += '--disable-slash-commands' }
            @{ Args = $a; Stdin = $Message }
        }
        'codex' {
            $a = @('exec', '--json', '--skip-git-repo-check', '--sandbox', 'danger-full-access', '--ephemeral')
            if ($Target.Model) { $a += @('-m', $Target.Model) }
            $files = @($HiddenSkills | Where-Object { $_.SkillFile -notmatch '[\\/]\.claude[\\/]' } | ForEach-Object { $_.SkillFile.Replace('\', '/') })
            if ($files.Count) { $a += @('-c', ('skills.config=[' + (($files | ForEach-Object { "{path='$_',enabled=false}" }) -join ',') + ']')) }
            @{ Args = $a + '-'; Stdin = $Message }
        }
        'opencode' {
            $a = @('run', '--format', 'json', '--auto', '--pure', '--dir', $Workspace)
            if ($Target.Model) { $a += @('-m', $Target.Model) }
            @{ Args = $a + $Message; Stdin = '' }
        }
    }
}

function Join-Arguments {
    param([string[]]$Arguments)
    ($Arguments | ForEach-Object {
        if ($_ -match '[\s",;=&|<>^()]' -or $_ -eq '') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ }
    }) -join ' '
}

function Invoke-Agent {
    param(
        [Parameter(Mandatory)]$Target,
        [Parameter(Mandatory)][string]$Workspace,
        [Parameter(Mandatory)][string]$RunDir,
        [Parameter(Mandatory)][string]$Message,
        [switch]$WithSkill,
        [object[]]$HiddenSkills = @(),
        [switch]$Isolate,
        [int]$TimeoutMinutes = 30,
        [switch]$DryRun
    )
    $spec = Get-AgentArguments -Target $Target -Workspace $Workspace -Message $Message -WithSkill:$WithSkill -HiddenSkills $HiddenSkills
    $argLine = Join-Arguments $spec.Args
    $result = [ordered]@{
        Command = "$($Target.Agent) $argLine"; ExitCode = $null; TimedOut = $false; Seconds = 0
        Stdout = Join-Path $RunDir 'transcript.jsonl'; Stderr = Join-Path $RunDir 'stderr.txt'
    }
    if ($DryRun) { return [pscustomobject]$result }

    $stdin = Join-Path $RunDir 'stdin.txt'
    Set-Content -Path $stdin -Value $spec.Stdin -Encoding utf8NoBOM
    $startArgs = @{
        FilePath               = Resolve-AgentCommand $Target.Agent
        ArgumentList           = $argLine
        WorkingDirectory       = $Workspace
        RedirectStandardInput  = $stdin
        RedirectStandardOutput = $result.Stdout
        RedirectStandardError  = $result.Stderr
        NoNewWindow            = $true
        PassThru               = $true
    }
    $environment = if ($Isolate) { Get-IsolatedEnvironment -RunDir $RunDir } else { @{} }
    $names = @($HiddenSkills | ForEach-Object Name | Select-Object -Unique)
    if ($Target.Agent -eq 'opencode' -and $names.Count) {
        $deny = [ordered]@{}
        foreach ($n in $names) { $deny[$n] = 'deny' }
        $environment.OPENCODE_CONFIG_CONTENT = @{ permission = @{ skill = $deny } } | ConvertTo-Json -Depth 5 -Compress
    }
    if ($environment.Count) { $startArgs.Environment = $environment }
    $result.Environment = @($environment.Keys)

    $clock = [Diagnostics.Stopwatch]::StartNew()
    # Start-Process without -Wait: -Wait also waits for every descendant, and agent plugins can outlive the agent.
    $p = Start-Process @startArgs
    $null = $p.Handle
    if (-not $p.WaitForExit($TimeoutMinutes * 60000)) {
        $result.TimedOut = $true
        try { $p.Kill($true) } catch { }
        $null = $p.WaitForExit(10000)
    }
    $clock.Stop()
    $result.Seconds = $clock.Elapsed.TotalSeconds
    $result.ExitCode = if ($p.HasExited) { $p.ExitCode } else { $null }
    [pscustomobject]$result
}

function ConvertFrom-JsonLines {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return }
    foreach ($line in Get-Content $Path) {
        if ($line.TrimStart().StartsWith('{')) {
            try { $line | ConvertFrom-Json -Depth 64 } catch { }
        }
    }
}

function Get-Number($Object, [string]$Name) {
    if ($null -ne $Object -and $Object.PSObject.Properties[$Name] -and $null -ne $Object.$Name) { [double]$Object.$Name } else { 0 }
}

function Find-TokenObjects($Node) {
    if ($null -eq $Node -or $Node -is [string] -or $Node -is [ValueType]) { return }
    if ($Node -is [System.Collections.IEnumerable]) { foreach ($item in $Node) { Find-TokenObjects $item }; return }
    foreach ($prop in $Node.PSObject.Properties) {
        if ($prop.Name -eq 'tokens' -and $prop.Value -and $prop.Value.PSObject.Properties['input']) { $prop.Value }
        else { Find-TokenObjects $prop.Value }
    }
}

function Get-AgentMetrics {
    param([Parameter(Mandatory)][string]$Agent, [Parameter(Mandatory)][string]$TranscriptPath, [Parameter(Mandatory)][string]$Skill, [switch]$NoGlobalCheck)
    $m = [ordered]@{ InputTokens = $null; OutputTokens = $null; CostUsd = $null; SkillUsed = $false; GlobalSkillUsed = $false }
    if (-not $NoGlobalCheck -and (Test-Path $TranscriptPath)) {
        $installed = Get-InstallName $Skill
        if ($Skill -ne $installed) {
            $global = Get-AgentMetrics -Agent $Agent -TranscriptPath $TranscriptPath -Skill $Skill -NoGlobalCheck
            $m.GlobalSkillUsed = $global.SkillUsed
        }
    }
    if (-not (Test-Path $TranscriptPath)) { return [pscustomobject]$m }
    $events = @(ConvertFrom-JsonLines $TranscriptPath)
    # Only tool output with the skill's frontmatter name line, or a completed skill tool call, proves a load.
    $lookFor = if ($NoGlobalCheck) { $Skill } else { Get-InstallName $Skill }
    $frontmatter = 'name:\s*' + [regex]::Escape($lookFor) + '(?![\w-])'

    switch ($Agent) {
        'claude' {
            $final = $events | Where-Object { $_.PSObject.Properties['type'] -and $_.type -eq 'result' } | Select-Object -Last 1
            if ($final) {
                $u = $final.usage
                $m.InputTokens = (Get-Number $u 'input_tokens') + (Get-Number $u 'cache_creation_input_tokens') + (Get-Number $u 'cache_read_input_tokens')
                $m.OutputTokens = Get-Number $u 'output_tokens'
                $m.CostUsd = Get-Number $final 'total_cost_usd'
            }
            $skillCalls = @{}
            foreach ($e in $events | Where-Object { $_.PSObject.Properties['type'] -and $_.type -eq 'assistant' }) {
                foreach ($c in @($e.message.content)) {
                    if ($c.type -eq 'tool_use' -and $c.name -eq 'Skill' -and $c.input.PSObject.Properties['skill'] -and "$($c.input.skill)" -eq $lookFor) { $skillCalls[$c.id] = $true }
                }
            }
            foreach ($e in $events | Where-Object { $_.PSObject.Properties['type'] -and $_.type -eq 'user' }) {
                foreach ($c in @($e.message.content)) {
                    if ($c -isnot [psobject] -or -not $c.PSObject.Properties['type'] -or $c.type -ne 'tool_result') { continue }
                    $failed = $c.PSObject.Properties['is_error'] -and $c.is_error
                    $text = if ($c.PSObject.Properties['content']) { $c.content | ConvertTo-Json -Depth 10 } else { '' }
                    if (-not $failed -and ($skillCalls.ContainsKey($c.tool_use_id) -or $text -match $frontmatter)) { $m.SkillUsed = $true }
                }
            }
        }
        'codex' {
            $turns = @($events | Where-Object { $_.PSObject.Properties['type'] -and $_.type -eq 'turn.completed' })
            if ($turns.Count) {
                $m.InputTokens = ($turns | ForEach-Object { Get-Number $_.usage 'input_tokens' } | Measure-Object -Sum).Sum
                $m.OutputTokens = ($turns | ForEach-Object { Get-Number $_.usage 'output_tokens' } | Measure-Object -Sum).Sum
            }
            foreach ($e in $events | Where-Object { $_.PSObject.Properties['type'] -and $_.type -eq 'item.completed' }) {
                $item = $e.item
                if ($item.PSObject.Properties['aggregated_output'] -and "$($item.aggregated_output)" -match $frontmatter) { $m.SkillUsed = $true }
            }
        }
        'opencode' {
            $steps = @($events | Where-Object { $_.PSObject.Properties['type'] -and $_.type -eq 'step_finish' })
            $tokens = @($steps | ForEach-Object { Find-TokenObjects $_ })
            if ($tokens.Count) {
                $m.InputTokens = ($tokens | ForEach-Object { $cache = if ($_.PSObject.Properties['cache']) { $_.cache } else { $null }; (Get-Number $_ 'input') + (Get-Number $cache 'read') + (Get-Number $cache 'write') } | Measure-Object -Sum).Sum
                $m.OutputTokens = ($tokens | ForEach-Object { (Get-Number $_ 'output') + (Get-Number $_ 'reasoning') } | Measure-Object -Sum).Sum
            }
            $costs = @($steps | ForEach-Object { if ($_.PSObject.Properties['part'] -and $_.part.PSObject.Properties['cost']) { [double]$_.part.cost } })
            if ($costs.Count) { $m.CostUsd = ($costs | Measure-Object -Sum).Sum }
            foreach ($e in $events | Where-Object { $_.PSObject.Properties['type'] -and $_.type -eq 'tool_use' }) {
                $state = $e.part.state
                if ($state.status -ne 'completed') { continue }
                $isSkillTool = $e.part.tool -eq 'skill' -and $state.input.PSObject.Properties['name'] -and "$($state.input.name)" -eq $lookFor
                $output = if ($state.PSObject.Properties['output']) { "$($state.output)" } else { '' }
                if ($isSkillTool -or $output -match $frontmatter) { $m.SkillUsed = $true }
            }
        }
    }
    [pscustomobject]$m
}

function Get-Mean([object[]]$Values) {
    $v = @($Values | Where-Object { $null -ne $_ })
    if ($v.Count -eq 0) { return $null }
    ($v | Measure-Object -Average).Average
}

function Write-Summary {
    param([Parameter(Mandatory)][object[]]$Results, [Parameter(Mandatory)][string]$Root, [string]$Skill, [AllowNull()][object[]]$Contamination = @())
    $Contamination = @($Contamination | Where-Object { $_ })
    $lines = @("# Eval results: $Skill", '')
    $lines += 'A run with the skill counts only when its transcript shows that the agent loaded the skill. Other with-skill runs are listed as not loaded and do not count.'
    $lines += ''
    if ($Contamination.Count) {
        $lines += 'Global skills that runs without the skill can load (Claude baselines disable skills):'
        $lines += ($Contamination | ForEach-Object { "- $($_.Name): $($_.Path)" })
        $lines += ''
    }
    $lines += '| Target | Task | Skill | Counted runs | Pass rate | Skipped | Seconds | Tokens | Not loaded |'
    $lines += '|---|---|---|---|---|---|---|---|---|'
    foreach ($g in $Results | Group-Object target, task, mode) {
        $all = @($g.Group)
        $r = @($all | Where-Object { $_.mode -ne 'with' -or $_.skillUsed })
        $notLoaded = $all.Count - $r.Count
        if ($r.Count -eq 0) {
            $lines += '| {0} | {1} | {2} | 0 | - | - | - | - | {3} |' -f $all[0].target, $all[0].task, $all[0].mode, $notLoaded
            continue
        }
        $rate = Get-Mean ($r | ForEach-Object { if (($_.passed + $_.failed) -gt 0) { $_.passed / ($_.passed + $_.failed) } })
        $tok = Get-Mean ($r | ForEach-Object { if ($null -ne $_.inputTokens) { $_.inputTokens + $_.outputTokens } })
        $lines += '| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} | {8} |' -f $r[0].target, $r[0].task, $r[0].mode, $r.Count,
            $(if ($null -ne $rate) { '{0:p0}' -f $rate } else { '-' }),
            (($r | Measure-Object skipped -Sum).Sum),
            ('{0:n0}' -f (Get-Mean $r.seconds)),
            $(if ($null -ne $tok) { '{0:n0}' -f $tok } else { '-' }),
            $notLoaded
    }
    $lines += ''
    $lines += '## Checks'
    foreach ($g in $Results | Group-Object target, task) {
        $lines += ''
        $lines += "### $($g.Group[0].target) | $($g.Group[0].task)"
        $lines += ''
        $lines += '| Check | With skill | Without skill |'
        $lines += '|---|---|---|'
        $counted = @($g.Group | Where-Object { $_.mode -ne 'with' -or $_.skillUsed })
        $texts = @($g.Group | ForEach-Object { $_.checks } | ForEach-Object { $_.text } | Select-Object -Unique)
        foreach ($text in $texts) {
            $cells = foreach ($mode in 'with', 'without') {
                $hits = @($counted | Where-Object mode -eq $mode | ForEach-Object { $_.checks } | Where-Object text -eq $text)
                if ($hits.Count -eq 0) { '-' }
                else { '{0}/{1}' -f @($hits | Where-Object { $_.passed -eq $true }).Count, @($hits | Where-Object { $null -ne $_.passed }).Count }
            }
            $lines += "| $($text -replace '\|', '\|') | $($cells[0]) | $($cells[1]) |"
        }
    }
    $text = $lines -join "`n"
    Set-Content -Path (Join-Path $Root 'summary.md') -Value $text -Encoding utf8
    $text
}

Export-ModuleMember -Function ConvertTo-AgentTarget, Get-AgentMessage, Get-InstallName, Resolve-AgentCommand, Find-ConflictingSkills, Install-Skill,
    Initialize-WorkspaceRepo, Invoke-Agent, Get-AgentMetrics, Write-Summary
