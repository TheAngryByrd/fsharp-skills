Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'Grading.psm1') -Force

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
        [switch]$WithSkill, [object[]]$HiddenSkills = @(), [string[]]$McpServers = @())
    $mcpOff = @(Get-McpOffArguments -Agent $Target.Agent -McpServers $McpServers)
    switch ($Target.Agent) {
        'claude' {
            $a = @('-p', '--output-format', 'stream-json', '--verbose', '--dangerously-skip-permissions', '--no-session-persistence') + $mcpOff
            if ($Target.Model) { $a += @('--model', $Target.Model) }
            if (-not $WithSkill) { $a += '--disable-slash-commands' }
            @{ Args = $a; Stdin = $Message; Environment = @{} }
        }
        'codex' {
            $a = @('exec', '--json', '--skip-git-repo-check', '--sandbox', 'danger-full-access', '--ephemeral') + $mcpOff
            if ($Target.Model) { $a += @('-m', $Target.Model) }
            $files = @($HiddenSkills | Where-Object { $_.SkillFile -notmatch '[\\/]\.claude[\\/]' } | ForEach-Object { $_.SkillFile.Replace('\', '/') })
            if ($files.Count) { $a += @('-c', ('skills.config=[' + (($files | ForEach-Object { "{path='$_',enabled=false}" }) -join ',') + ']')) }
            @{ Args = $a + '-'; Stdin = $Message; Environment = @{} }
        }
        'opencode' {
            $a = @('run', '--format', 'json', '--auto', '--pure', '--dir', $Workspace)
            if ($Target.Model) { $a += @('-m', $Target.Model) }
            $config = [ordered]@{}
            $names = @($HiddenSkills | ForEach-Object Name | Select-Object -Unique)
            if ($names.Count) {
                $deny = [ordered]@{}
                foreach ($n in $names) { $deny[$n] = 'deny' }
                $config.permission = @{ skill = $deny }
            }
            if ($McpServers.Count) {
                $off = [ordered]@{}
                foreach ($n in $McpServers) { $off[$n] = @{ enabled = $false } }
                $config.mcp = $off
            }
            $environment = if ($config.Count) { @{ OPENCODE_CONFIG_CONTENT = $config | ConvertTo-Json -Depth 5 -Compress } } else { @{} }
            @{ Args = $a + $Message; Stdin = ''; Environment = $environment }
        }
    }
}

function Get-McpOffArguments {
    param([Parameter(Mandatory)][string]$Agent, [string[]]$McpServers = @())
    switch ($Agent) {
        'claude' { @('--strict-mcp-config') }
        'codex' {
            # Codex merges -c values into config.toml, so mcp_servers={} keeps every server. A plugin server is not in config.toml and fails with "invalid transport" when named.
            $a = @('-c', 'features.plugins=false')
            foreach ($n in $McpServers) {
                if ($n -cnotmatch '^[A-Za-z0-9_-]+$') { throw "Codex MCP server name '$n' cannot go in a -c key. Remove it from config.toml or run with -Isolate." }
                $a += @('-c', "mcp_servers.$n.enabled=false")
            }
            $a
        }
        default { @() }
    }
}

function Get-TextStart([AllowEmptyString()][string]$Text, [int]$Length = 200) {
    if ($Text.Length -le $Length) { $Text } else { $Text.Substring(0, $Length) + '...' }
}

function ConvertFrom-McpList {
    param([Parameter(Mandatory)][string]$Agent, [AllowEmptyString()][string]$Text)
    $data = $null
    try { $data = ConvertFrom-Json -InputObject $Text -Depth 32 -NoEnumerate } catch { }
    if ($null -eq $data) { throw "The $Agent MCP server list is not JSON. It starts with: $(Get-TextStart $Text)" }
    switch ($Agent) {
        'codex' {
            foreach ($s in @($data)) {
                if ($null -eq $s -or -not $s.PSObject.Properties['name'] -or -not "$($s.name)") { throw "A Codex MCP server entry has no name. The list starts with: $(Get-TextStart $Text)" }
                $enabled = -not ($s.PSObject.Properties['enabled'] -and $s.enabled -eq $false)
                [pscustomobject]@{ Name = "$($s.name)"; Enabled = $enabled }
            }
        }
        'opencode' {
            if ($data -isnot [System.Management.Automation.PSCustomObject]) { throw "The opencode configuration is not a JSON object. It starts with: $(Get-TextStart $Text)" }
            $mcp = if ($data.PSObject.Properties['mcp']) { $data.mcp } else { $null }
            if ($null -eq $mcp) { return }
            foreach ($p in $mcp.PSObject.Properties) {
                $enabled = -not ($null -ne $p.Value -and $p.Value.PSObject.Properties['enabled'] -and $p.Value.enabled -eq $false)
                [pscustomobject]@{ Name = $p.Name; Enabled = $enabled }
            }
        }
        default { throw "No MCP server list for agent '$Agent'." }
    }
}

function Invoke-AgentCli {
    param([Parameter(Mandatory)][string]$Agent, [Parameter(Mandatory)][string[]]$Arguments, [Parameter(Mandatory)][string]$Workspace,
        [hashtable]$Environment = @{}, [int]$TimeoutSeconds = 120)
    $r = Invoke-Capture -FilePath (Resolve-AgentCommand $Agent) -Arguments $Arguments -WorkingDirectory $Workspace -TimeoutSeconds $TimeoutSeconds -Environment $Environment
    if ($r.TimedOut) { throw "'$Agent $($Arguments -join ' ')' did not exit in $TimeoutSeconds seconds." }
    if ($r.ExitCode -ne 0) { throw "'$Agent $($Arguments -join ' ')' exited with code $($r.ExitCode). Its error output starts with: $(Get-TextStart $r.Stderr)" }
    $r.Stdout
}

function Get-McpServerList {
    param([Parameter(Mandatory)][string]$Agent, [Parameter(Mandatory)][string]$Workspace, [hashtable]$Environment = @{}, [string[]]$McpServers = @())
    switch ($Agent) {
        'codex' {
            $a = @(Get-McpOffArguments -Agent codex -McpServers $McpServers) + @('mcp', 'list', '--json')
            ConvertFrom-McpList -Agent codex -Text (Invoke-AgentCli -Agent codex -Arguments $a -Workspace $Workspace -Environment $Environment)
        }
        'opencode' {
            ConvertFrom-McpList -Agent opencode -Text (Invoke-AgentCli -Agent opencode -Arguments @('--pure', 'debug', 'config') -Workspace $Workspace -Environment $Environment)
        }
        default { @() }
    }
}

function Get-McpServersOff {
    param([Parameter(Mandatory)]$Target, [Parameter(Mandatory)][string]$Workspace, [hashtable]$Environment = @{}, [object[]]$HiddenSkills = @())
    if ($Target.Agent -eq 'claude') { return @() }
    $names = @(Get-McpServerList -Agent $Target.Agent -Workspace $Workspace -Environment $Environment | ForEach-Object Name | Select-Object -Unique)
    $spec = Get-AgentArguments -Target $Target -Workspace $Workspace -Message '-' -HiddenSkills $HiddenSkills -McpServers $names
    $checkEnvironment = @{} + $Environment
    foreach ($key in $spec.Environment.Keys) { $checkEnvironment[$key] = $spec.Environment[$key] }
    $left = @(Get-McpServerList -Agent $Target.Agent -Workspace $Workspace -Environment $checkEnvironment -McpServers $names | Where-Object Enabled | ForEach-Object Name)
    if ($left.Count) { throw "$($Target.Agent) still starts these MCP servers: $($left -join ', '). A target agent must run with no MCP servers." }
    $names
}

function Get-ClaudeMcpServers {
    param([Parameter(Mandatory)][string]$TranscriptPath)
    $init = ConvertFrom-JsonLines $TranscriptPath | Where-Object { $_.PSObject.Properties['subtype'] -and $_.subtype -eq 'init' } | Select-Object -First 1
    if ($init -and $init.PSObject.Properties['mcp_servers']) { @($init.mcp_servers | ForEach-Object { "$($_.name)" }) }
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
    $environment = @{}
    $servers = @()
    if (-not $DryRun) {
        if ($Isolate) { $environment = Get-IsolatedEnvironment -RunDir $RunDir }
        $servers = @(Get-McpServersOff -Target $Target -Workspace $Workspace -Environment $environment -HiddenSkills $HiddenSkills)
    }
    $spec = Get-AgentArguments -Target $Target -Workspace $Workspace -Message $Message -WithSkill:$WithSkill -HiddenSkills $HiddenSkills -McpServers $servers
    foreach ($key in $spec.Environment.Keys) { $environment[$key] = $spec.Environment[$key] }
    $argLine = Join-Arguments $spec.Args
    $result = [ordered]@{
        Command = "$($Target.Agent) $argLine"; ExitCode = $null; TimedOut = $false; Seconds = 0
        Stdout = Join-Path $RunDir 'transcript.jsonl'; Stderr = Join-Path $RunDir 'stderr.txt'; McpServers = @()
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
    if ($Target.Agent -eq 'claude') { $result.McpServers = @(Get-ClaudeMcpServers -TranscriptPath $result.Stdout) }
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

$ShellWrapperPattern = '(?s)^\s*(?:"[^"]*|[^\s"]*)(?<![\w-])(?:pwsh|powershell|bash|sh|zsh)(?:\.exe)?"?(?:\s+-\w+)*?\s+-(?:Command|c|lc)\s+(?<script>.+)$'
$BuildCommandPattern = '(?:^|[;&|({\r\n])\s*(?:[^\s;&|]*[\\/])?dotnet(?:\.exe)?\s+(?:build|test|run|fsi)(?![\w-])'

function Test-BuildCommand {
    param([string]$Command)
    $script = $Command
    if ($script -match $ShellWrapperPattern) {
        $script = [regex]::Replace($Matches.script.Trim(), '"((?:\\.|[^"\\])*)"|''([^'']*)''', {
                param($q) if ($q.Groups[1].Success) { $q.Groups[1].Value -replace '\\(["\\$`])', '$1' } else { $q.Groups[2].Value } })
    }
    $script = $script -replace '["'']([^"'']*[\\/])?dotnet(\.exe)?["'']', 'dotnet'
    $script = $script -replace "'[^']*'", "''" -replace '"[^"]*"', '""'
    $script -match $BuildCommandPattern
}
$CompilerErrorPattern = '(?m)\berror FS\d+'

function Get-ContentText($Content) {
    if ($null -eq $Content) { return '' }
    if ($Content -is [string]) { return $Content }
    (@($Content) | ForEach-Object { if ($_ -is [string]) { $_ } elseif ($_.PSObject.Properties['text']) { "$($_.text)" } }) -join "`n"
}

function Test-FailedBuild {
    param([string]$Command, [bool]$Failed, [string]$Output)
    (Test-BuildCommand $Command) -and ($Failed -or $Output -match $CompilerErrorPattern)
}

function Get-AgentMetrics {
    param([Parameter(Mandatory)][string]$Agent, [Parameter(Mandatory)][string]$TranscriptPath, [Parameter(Mandatory)][string]$Skill, [switch]$NoGlobalCheck)
    $m = [ordered]@{ InputTokens = $null; OutputTokens = $null; CostUsd = $null; Turns = $null; FailedBuilds = $null; SkillUsed = $false; GlobalSkillUsed = $false }
    if (-not $NoGlobalCheck -and (Test-Path $TranscriptPath)) {
        $installed = Get-InstallName $Skill
        if ($Skill -ne $installed) {
            $global = Get-AgentMetrics -Agent $Agent -TranscriptPath $TranscriptPath -Skill $Skill -NoGlobalCheck
            $m.GlobalSkillUsed = $global.SkillUsed
        }
    }
    if (-not (Test-Path $TranscriptPath)) { return [pscustomobject]$m }
    $events = @(ConvertFrom-JsonLines $TranscriptPath)
    if ($events.Count -eq 0) { return [pscustomobject]$m }
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
                if ($final.PSObject.Properties['num_turns']) { $m.Turns = [int]$final.num_turns }
            }
            $skillCalls = @{}
            $commands = @{}
            $toolCalls = 0
            foreach ($e in $events | Where-Object { $_.PSObject.Properties['type'] -and $_.type -eq 'assistant' }) {
                foreach ($c in @($e.message.content)) {
                    if ($c.type -ne 'tool_use') { continue }
                    if ($c.name -eq 'Skill' -and $c.input.PSObject.Properties['skill'] -and "$($c.input.skill)" -eq $lookFor) { $skillCalls[$c.id] = $true }
                    $toolCalls++
                    if ($c.input.PSObject.Properties['command']) { $commands[$c.id] = "$($c.input.command)" }
                }
            }
            $m.FailedBuilds = 0
            foreach ($e in $events | Where-Object { $_.PSObject.Properties['type'] -and $_.type -eq 'user' }) {
                foreach ($c in @($e.message.content)) {
                    if ($c -isnot [psobject] -or -not $c.PSObject.Properties['type'] -or $c.type -ne 'tool_result') { continue }
                    $failed = [bool]($c.PSObject.Properties['is_error'] -and $c.is_error)
                    $text = if ($c.PSObject.Properties['content']) { $c.content | ConvertTo-Json -Depth 10 } else { '' }
                    if (-not $failed -and ($skillCalls.ContainsKey($c.tool_use_id) -or $text -match $frontmatter)) { $m.SkillUsed = $true }
                    if ($commands.ContainsKey($c.tool_use_id) -and (Test-FailedBuild $commands[$c.tool_use_id] $failed (Get-ContentText $c.content))) { $m.FailedBuilds++ }
                }
            }
            # A stopped Claude run has no result event.
            if ($null -eq $m.Turns) { $m.Turns = $toolCalls + 1 }
        }
        'codex' {
            $turns = @($events | Where-Object { $_.PSObject.Properties['type'] -and $_.type -eq 'turn.completed' })
            if ($turns.Count) {
                $m.InputTokens = ($turns | ForEach-Object { Get-Number $_.usage 'input_tokens' } | Measure-Object -Sum).Sum
                $m.OutputTokens = ($turns | ForEach-Object { Get-Number $_.usage 'output_tokens' } | Measure-Object -Sum).Sum
            }
            $completed = @($events | Where-Object { $_.PSObject.Properties['type'] -and $_.type -eq 'item.completed' })
            # Codex exec emits no event for each model request.
            $m.Turns = @($completed | Where-Object { $_.item.type -notin 'agent_message', 'reasoning', 'error' }).Count + 1
            $m.FailedBuilds = 0
            foreach ($e in $completed) {
                $item = $e.item
                $output = if ($item.PSObject.Properties['aggregated_output']) { "$($item.aggregated_output)" } else { '' }
                if ($output -match $frontmatter) { $m.SkillUsed = $true }
                if ($item.type -eq 'command_execution') {
                    $failed = ($item.PSObject.Properties['exit_code'] -and $null -ne $item.exit_code -and $item.exit_code -ne 0) -or
                        ($item.PSObject.Properties['status'] -and $item.status -eq 'failed')
                    if (Test-FailedBuild "$($item.command)" $failed $output) { $m.FailedBuilds++ }
                }
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
            $m.Turns = $steps.Count
            $m.FailedBuilds = 0
            foreach ($e in $events | Where-Object { $_.PSObject.Properties['type'] -and $_.type -eq 'tool_use' }) {
                $state = $e.part.state
                $output = if ($state.PSObject.Properties['output']) { "$($state.output)" } else { '' }
                if ($state.PSObject.Properties['input'] -and $state.input.PSObject.Properties['command']) {
                    $meta = if ($state.PSObject.Properties['metadata']) { $state.metadata } else { $null }
                    $exit = if ($meta -and $meta.PSObject.Properties['exit']) { $meta.exit } else { $null }
                    $failed = $state.status -eq 'error' -or ($null -ne $exit -and $exit -ne 0)
                    if (Test-FailedBuild "$($state.input.command)" $failed $output) { $m.FailedBuilds++ }
                }
                if ($state.status -ne 'completed') { continue }
                $isSkillTool = $e.part.tool -eq 'skill' -and $state.input.PSObject.Properties['name'] -and "$($state.input.name)" -eq $lookFor
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

function Get-RunValue($Run, [string]$Name) {
    if ($Run.PSObject.Properties[$Name]) { $Run.$Name } else { $null }
}

function Format-Mean([object[]]$Values) {
    $mean = Get-Mean $Values
    if ($null -ne $mean) { Format-Invariant '{0:n1}' $mean } else { '-' }
}

function Format-Invariant([string]$Format, $Value) { [string]::Format([Globalization.CultureInfo]::InvariantCulture, $Format, $Value) }

function Format-TargetLabel([object[]]$Runs) {
    $models = @($Runs | ForEach-Object { Get-RunValue $_ 'resolvedModel' } | Where-Object { $_ } | Sort-Object -Unique)
    "$($Runs[0].target) ($(if ($models.Count) { $models -join ', ' } else { 'model unknown' }))"
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
    $lines += '| Target | Task | Skill | Counted runs | Pass rate | Skipped | Seconds | Tokens | Turns | Failed builds | Not loaded |'
    $lines += '|---|---|---|---|---|---|---|---|---|---|---|'
    foreach ($g in $Results | Group-Object target, task, mode) {
        $all = @($g.Group)
        $r = @($all | Where-Object { $_.mode -ne 'with' -or $_.skillUsed })
        $notLoaded = $all.Count - $r.Count
        if ($r.Count -eq 0) {
            $lines += '| {0} | {1} | {2} | 0 | - | - | - | - | - | - | {3} |' -f (Format-TargetLabel $all), $all[0].task, $all[0].mode, $notLoaded
            continue
        }
        $rate = Get-Mean ($r | ForEach-Object { if (($_.passed + $_.failed) -gt 0) { $_.passed / ($_.passed + $_.failed) } })
        $tok = Get-Mean ($r | ForEach-Object { if ($null -ne $_.inputTokens) { $_.inputTokens + $_.outputTokens } })
        $lines += '| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} | {8} | {9} | {10} |' -f (Format-TargetLabel $all), $r[0].task, $r[0].mode, $r.Count,
            $(if ($null -ne $rate) { Format-Invariant '{0:0}%' ($rate * 100) } else { '-' }),
            (($r | Measure-Object skipped -Sum).Sum),
            $(if ($null -ne ($sec = Get-Mean $r.seconds)) { Format-Invariant '{0:n0}' $sec } else { '-' }),
            $(if ($null -ne $tok) { Format-Invariant '{0:n0}' $tok } else { '-' }),
            (Format-Mean ($r | ForEach-Object { Get-RunValue $_ 'turns' })),
            (Format-Mean ($r | ForEach-Object { Get-RunValue $_ 'failedBuilds' })),
            $notLoaded
    }
    $lines += ''
    $lines += '## Checks'
    foreach ($g in $Results | Group-Object target, task) {
        $lines += ''
        $lines += "### $(Format-TargetLabel @($g.Group)) | $($g.Group[0].task)"
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

function Get-CodexConfigLine {
    param([Parameter(Mandatory)][string]$ConfigPath, [Parameter(Mandatory)][string]$Key)
    if (-not (Test-Path $ConfigPath)) { return $null }
    foreach ($line in Get-Content $ConfigPath) {
        if ($line -match '^\s*\[') { return $null }
        if ($line -match ('^\s*' + [regex]::Escape($Key) + '\s*=')) { return $line }
    }
    $null
}

function Get-CodexConfigValue {
    param([Parameter(Mandatory)][string]$ConfigPath, [Parameter(Mandatory)][string]$Key)
    $line = Get-CodexConfigLine $ConfigPath $Key
    if ($line -and $line -match ('^\s*' + [regex]::Escape($Key) + '\s*=\s*(?:"(?<basic>[^"]*)"|''(?<literal>[^'']*)'')')) {
        return "$($Matches['basic'])$($Matches['literal'])"
    }
    $null
}

function Get-ResolvedModel {
    # An empty result means the exact model is unknown. The export refuses a run with an empty result.
    param([Parameter(Mandatory)][string]$Agent, [string]$Model = '', [string]$TranscriptPath = '', [string]$CodexConfigPath = '', [switch]$Isolated)
    switch ($Agent) {
        'claude' {
            if (-not $TranscriptPath) { return '' }
            $models = @(ConvertFrom-JsonLines $TranscriptPath | Where-Object { $_.PSObject.Properties['type'] -and $_.type -eq 'assistant' } |
                    ForEach-Object { if ($_.message.PSObject.Properties['model']) { "$($_.message.model)" } } | Where-Object { $_ -and $_ -notlike '<*' })
            if ($models.Count) { return ($models | Group-Object | Sort-Object Count -Descending | Select-Object -First 1).Name }
            $init = ConvertFrom-JsonLines $TranscriptPath | Where-Object { $_.PSObject.Properties['subtype'] -and $_.subtype -eq 'init' -and $_.PSObject.Properties['model'] } | Select-Object -First 1
            if ($init) { return "$($init.model)" }
            ''
        }
        'codex' {
            $effort = $null
            $configured = $null
            $configProfile = $null
            if (-not $Isolated) {
                if (-not $CodexConfigPath) {
                    $codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path (Get-UserHome) '.codex' }
                    $CodexConfigPath = Join-Path $codexHome 'config.toml'
                }
                $configured = Get-CodexConfigValue $CodexConfigPath 'model'
                $effort = Get-CodexConfigValue $CodexConfigPath 'model_reasoning_effort'
                $configProfile = Get-CodexConfigLine $CodexConfigPath 'profile'
            }
            if ($configProfile -and -not $Model) { return '' }
            $name = if ($Model) { $Model } else { $configured }
            if (-not $name) { return '' }
            if ($effort) { "$name (reasoning effort $effort)" } else { $name }
        }
        default { $Model }
    }
}

function Get-SkillProvenance {
    param([Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory)][string]$Skill)
    $commit = $null
    $dirty = $false
    if (Get-Command git -CommandType Application -ErrorAction SilentlyContinue) {
        $head = git -C $Repo rev-parse HEAD 2>$null
        if ($LASTEXITCODE -eq 0) { $commit = "$head".Trim() }
        $dirty = [bool](git -C $Repo status --porcelain -- "skills/$Skill" "evals/$Skill" 'evals/lib' 2>$null)
    }
    [pscustomobject]@{ SkillCommit = $commit; SkillDirty = $dirty }
}

function Find-EvalSpec {
    param([Parameter(Mandatory)][string]$EvalsRoot, [Parameter(Mandatory)][string]$TaskId)
    foreach ($file in Get-ChildItem -Path $EvalsRoot -Filter 'evals.json' -Recurse -Depth 1) {
        $spec = Get-Content -Raw $file.FullName | ConvertFrom-Json
        if ($spec.tasks.id -contains $TaskId) { return [pscustomobject]@{ Spec = $spec; Dir = $file.DirectoryName } }
    }
}

Export-ModuleMember -Function ConvertTo-AgentTarget, Get-AgentMessage, Get-InstallName, Resolve-AgentCommand, Find-ConflictingSkills, Install-Skill,
    Initialize-WorkspaceRepo, Invoke-Agent, Get-AgentMetrics, Get-ResolvedModel, Get-SkillProvenance, Find-EvalSpec, Write-Summary,
    Get-AgentArguments, Get-McpOffArguments, ConvertFrom-McpList, Get-ClaudeMcpServers, Get-McpServersOff, Get-IsolatedEnvironment
