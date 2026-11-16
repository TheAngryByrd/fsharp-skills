#!/usr/bin/env pwsh
#Requires -Version 7.4
param()
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../lib/Agents.psm1') -Force
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-True([bool]$Condition, [string]$Name, [string]$Detail = '') {
    if (-not $Condition) { $failures.Add("${Name}: $Detail") }
}

function Get-Pairs([string[]]$Arguments) {
    @(for ($i = 0; $i -lt $Arguments.Count - 1; $i++) { if ($Arguments[$i] -eq '-c') { $Arguments[$i + 1] } })
}

$ws = Join-Path ([IO.Path]::GetTempPath()) "agents-tests-$PID"
$hidden = @([pscustomobject]@{ Name = 'fsharp-demo'; Path = 'x'; SkillFile = '/home/u/.agents/skills/fsharp-demo/SKILL.md' })

foreach ($withSkill in $true, $false) {
    $claude = Get-AgentArguments -Target (ConvertTo-AgentTarget 'claude:sonnet') -Workspace $ws -Message 'm' -WithSkill:$withSkill
    Assert-True ($claude.Args -contains '--strict-mcp-config') "a Claude run with skill=$withSkill uses only MCP servers from --mcp-config" ($claude.Args -join ' ')
    Assert-True ($claude.Args -notcontains '--mcp-config') "a Claude run with skill=$withSkill names no MCP config" ($claude.Args -join ' ')
}

$codex = Get-AgentArguments -Target (ConvertTo-AgentTarget 'codex') -Workspace $ws -Message 'm' -McpServers @('memorizer', 'node_repl') -HiddenSkills $hidden
$pairs = Get-Pairs $codex.Args
Assert-True ($pairs -contains 'features.plugins=false') 'a Codex run turns off plugins, which bring their own MCP servers' ($pairs -join ' ')
Assert-True ($pairs -contains 'mcp_servers.memorizer.enabled=false' -and $pairs -contains 'mcp_servers.node_repl.enabled=false') 'a Codex run turns off each configured MCP server by name' ($pairs -join ' ')
Assert-True (@($pairs | Where-Object { $_ -like 'skills.config=*' }).Count -eq 1) 'a Codex run still hides global skills' ($pairs -join ' ')
Assert-True ($codex.Args[-1] -eq '-' -and $codex.Args[0] -eq 'exec') 'the Codex overrides go between exec and the stdin marker' ($codex.Args -join ' ')

$noServers = Get-AgentArguments -Target (ConvertTo-AgentTarget 'codex') -Workspace $ws -Message 'm'
Assert-True ((Get-Pairs $noServers.Args) -contains 'features.plugins=false') 'a Codex run with no configured server still turns off plugins' ($noServers.Args -join ' ')

foreach ($bad in 'my.server', 'a b', "x'y", 'a=b') {
    $threw = $false
    try { $null = Get-AgentArguments -Target (ConvertTo-AgentTarget 'codex') -Workspace $ws -Message 'm' -McpServers @($bad) } catch { $threw = $true }
    Assert-True $threw "a Codex MCP server name '$bad' that cannot be a -c key stops the run"
}

$opencode = Get-AgentArguments -Target (ConvertTo-AgentTarget 'opencode:opencode/demo-free') -Workspace $ws -Message 'm' -McpServers @('memorizer', 'my.server') -HiddenSkills $hidden -InheritedOpencodeConfig ''
$config = $opencode.Environment.OPENCODE_CONFIG_CONTENT | ConvertFrom-Json
Assert-True ($config.mcp.memorizer.enabled -eq $false -and $config.mcp.'my.server'.enabled -eq $false) 'an opencode run turns off each configured MCP server' $opencode.Environment.OPENCODE_CONFIG_CONTENT
Assert-True ($config.permission.skill.'fsharp-demo' -eq 'deny') 'an opencode run keeps the global skill deny next to the MCP block' $opencode.Environment.OPENCODE_CONFIG_CONTENT
Assert-True ($opencode.Args -contains '--pure') 'an opencode run does not load external plugins' ($opencode.Args -join ' ')
$plain = Get-AgentArguments -Target (ConvertTo-AgentTarget 'opencode') -Workspace $ws -Message 'm' -InheritedOpencodeConfig '{"model":"a/b"}'
Assert-True ($plain.Environment.Count -eq 0) 'an opencode run with nothing to turn off sets no config content' ($plain.Environment.Keys -join ',')
$inherited = '{"model":"a/b","mcp":{"memorizer":{"type":"remote","url":"http://localhost:5000/mcp"},"kept":{"type":"local"}},"permission":{"bash":"ask","skill":{"other":"deny"}}}'
$merged = (Get-AgentArguments -Target (ConvertTo-AgentTarget 'opencode') -Workspace $ws -Message 'm' -McpServers @('memorizer') -HiddenSkills $hidden -InheritedOpencodeConfig $inherited).Environment.OPENCODE_CONFIG_CONTENT | ConvertFrom-Json
Assert-True ($merged.model -eq 'a/b' -and $merged.permission.bash -eq 'ask' -and $merged.mcp.kept.type -eq 'local') 'an opencode run keeps the settings of an inherited OPENCODE_CONFIG_CONTENT' ($merged | ConvertTo-Json -Depth 8 -Compress)
Assert-True ($merged.mcp.memorizer.enabled -eq $false -and $merged.mcp.memorizer.url -eq 'http://localhost:5000/mcp') 'an inherited MCP server keeps its fields and gets enabled false' ($merged | ConvertTo-Json -Depth 8 -Compress)
Assert-True ($merged.permission.skill.other -eq 'deny' -and $merged.permission.skill.'fsharp-demo' -eq 'deny') 'an inherited skill deny list keeps its entries next to the hidden skills' ($merged | ConvertTo-Json -Depth 8 -Compress)
$stringSkill = (Get-AgentArguments -Target (ConvertTo-AgentTarget 'opencode') -Workspace $ws -Message 'm' -HiddenSkills $hidden -InheritedOpencodeConfig '{"permission":{"skill":"allow"}}').Environment.OPENCODE_CONFIG_CONTENT | ConvertFrom-Json
Assert-True ($stringSkill.permission.skill.'*' -eq 'allow' -and $stringSkill.permission.skill.'fsharp-demo' -eq 'deny') 'an inherited skill permission string becomes the default next to the denies' ($stringSkill | ConvertTo-Json -Depth 8 -Compress)
$wildcardAfter = '{"permission":{"skill":{"fsharp-demo":"allow","*":"allow"},"*":"allow"}}'
$ordered = (Get-AgentArguments -Target (ConvertTo-AgentTarget 'opencode') -Workspace $ws -Message 'm' -HiddenSkills $hidden -InheritedOpencodeConfig $wildcardAfter).Environment.OPENCODE_CONFIG_CONTENT | ConvertFrom-Json -AsHashtable
Assert-True (@($ordered.permission.skill.Keys)[-1] -eq 'fsharp-demo' -and $ordered.permission.skill['fsharp-demo'] -eq 'deny') 'a hidden skill deny comes after an inherited wildcard allow' ($ordered | ConvertTo-Json -Depth 8 -Compress)
Assert-True (@($ordered.permission.Keys)[-1] -eq 'skill') 'the skill rules come after an inherited top-level wildcard allow' ($ordered | ConvertTo-Json -Depth 8 -Compress)

$rule = { param($p, $pattern, $action) [pscustomobject]@{ permission = $p; pattern = $pattern; action = $action } }
$cases = @(
    @{ Name = 'a deny before a wildcard allow'; Rules = @((& $rule 'skill' 'fsharp-demo' 'deny'), (& $rule 'skill' '*' 'allow')); Expected = 'allow' }
    @{ Name = 'a deny after a wildcard allow'; Rules = @((& $rule 'skill' '*' 'allow'), (& $rule 'skill' 'fsharp-demo' 'deny')); Expected = 'deny' }
    @{ Name = 'a top-level wildcard allow after the deny'; Rules = @((& $rule 'skill' 'fsharp-demo' 'deny'), (& $rule '*' '*' 'allow')); Expected = 'allow' }
    @{ Name = 'a prefix pattern deny'; Rules = @((& $rule 'skill' '*' 'allow'), (& $rule 'skill' 'fsharp-*' 'deny')); Expected = 'deny' }
    @{ Name = 'a rule for another tool'; Rules = @((& $rule 'bash' '*' 'deny')); Expected = 'ask' }
)
foreach ($c in $cases) {
    $action = Get-OpencodeSkillAction -Rules $c.Rules -Skill 'fsharp-demo'
    Assert-True ($action -eq $c.Expected) "the opencode last-match rule gives $($c.Expected) for $($c.Name)" $action
}

foreach ($bad in 'not json', '[1]', '{"mcp":[1]}') {
    $threw = $false
    try { $null = Get-AgentArguments -Target (ConvertTo-AgentTarget 'opencode') -Workspace $ws -Message 'm' -McpServers @('memorizer') -InheritedOpencodeConfig $bad } catch { $threw = $true }
    Assert-True $threw "an inherited OPENCODE_CONFIG_CONTENT '$bad' that the runner cannot merge stops the run"
}

$codexList = ConvertFrom-McpList -Agent codex -Text '[{"name":"memorizer","enabled":true},{"name":"docs","enabled":false}]'
Assert-True ($codexList.Count -eq 2 -and $codexList[0].Name -eq 'memorizer' -and $codexList[0].Enabled -and -not $codexList[1].Enabled) 'the Codex list gives each server and its state' ($codexList | ConvertTo-Json -Compress)
Assert-True (@(ConvertFrom-McpList -Agent codex -Text '[]').Count -eq 0) 'an empty Codex list gives no servers'
$openList = @(ConvertFrom-McpList -Agent opencode -Text '{"mcp":{"a":{"type":"remote","enabled":true},"b":{"enabled":false},"c":{"type":"local"}}}')
Assert-True ($openList.Count -eq 3) 'the opencode config gives each server' ($openList | ConvertTo-Json -Compress)
Assert-True (($openList | Where-Object Name -eq 'c').Enabled) 'an opencode server with no enabled value counts as started' ($openList | ConvertTo-Json -Compress)
Assert-True (-not ($openList | Where-Object Name -eq 'b').Enabled) 'an opencode server with enabled false counts as off' ($openList | ConvertTo-Json -Compress)
Assert-True (@(ConvertFrom-McpList -Agent opencode -Text '{"model":"x"}').Count -eq 0) 'an opencode config with no mcp block gives no servers'
$noState = @(ConvertFrom-McpList -Agent codex -Text '[{"name":"memorizer"}]')
Assert-True ($noState.Count -eq 1 -and $noState[0].Enabled) 'a Codex entry with no enabled value counts as started' ($noState | ConvertTo-Json -Compress)
foreach ($text in 'Error: failed to load configuration', '', 'null', '[{"enabled":true}]') {
    $message = ''
    try { $null = ConvertFrom-McpList -Agent codex -Text $text } catch { $message = "$_" }
    Assert-True ($message -like '*Codex*' -or $message -like '*codex*') "the Codex list '$text' stops the run with an MCP message" $message
}
$long = '{' + ('x' * 5000)
$message = ''
try { $null = ConvertFrom-McpList -Agent opencode -Text $long } catch { $message = "$_" }
Assert-True ($message.Length -lt 400) 'a list that is not JSON stops the run and quotes only the start of the output' "$($message.Length) characters"

New-Item -ItemType Directory -Force -Path $ws | Out-Null
try {
    $withServer = Join-Path $ws 'with-server.jsonl'
    Set-Content $withServer @('{"type":"system","subtype":"hook_started"}', '{"type":"system","subtype":"init","mcp_servers":[{"name":"memorizer","status":"connected"}]}')
    Assert-True ((@(Get-ClaudeMcpServers -TranscriptPath $withServer) -join ',') -eq 'memorizer') 'the Claude init event names a started MCP server'
    $none = Join-Path $ws 'none.jsonl'
    Set-Content $none '{"type":"system","subtype":"init","mcp_servers":[]}'
    Assert-True (@(Get-ClaudeMcpServers -TranscriptPath $none).Count -eq 0) 'a Claude init event with no MCP servers gives none'
    $noInit = Join-Path $ws 'no-init.jsonl'
    Set-Content $noInit '{"type":"result","subtype":"success"}'
    Assert-True (@(Get-ClaudeMcpServers -TranscriptPath $noInit).Count -eq 0) 'a Claude transcript with no init event gives none'
    Assert-True (@(Get-ClaudeMcpServers -TranscriptPath (Join-Path $ws 'missing.jsonl')).Count -eq 0) 'a missing Claude transcript gives none'

    $bin = Join-Path $ws 'bin'
    New-Item -ItemType Directory -Force -Path $bin | Out-Null
    function New-FakeCli([string]$Name, [string]$Script) {
        $body = Join-Path $bin "$Name-fake.ps1"
        Set-Content $body $Script
        if ($IsWindows) {
            Set-Content (Join-Path $bin "$Name.cmd") "@pwsh -NoProfile -File `"%~dp0$Name-fake.ps1`" %*"
        } else {
            $path = Join-Path $bin $Name
            Set-Content $path "#!/usr/bin/env pwsh`n& '$body' @args`nexit `$LASTEXITCODE"
            chmod +x $path
        }
    }
    New-FakeCli 'codex' 'Write-Output ''[{"name":"memorizer","enabled":true}]'''
    New-FakeCli 'opencode' '[Console]::Error.WriteLine("config error: " + ("y" * 5000)); exit 3'
    $savedPath = $env:PATH
    try {
        $env:PATH = $bin + [IO.Path]::PathSeparator + $env:PATH
        $runDir = Join-Path $ws 'run'
        New-Item -ItemType Directory -Force -Path $runDir | Out-Null
        $message = ''
        try { $null = Invoke-Agent -Target (ConvertTo-AgentTarget 'codex') -Workspace $ws -RunDir $runDir -Message 'm' -TimeoutMinutes 1 } catch { $message = "$_" }
        Assert-True ($message -like '*still starts these MCP servers: memorizer*') 'a Codex server that the overrides leave on stops the run' $message
        Assert-True (-not (Test-Path (Join-Path $runDir 'transcript.jsonl'))) 'the agent does not start when a server stays on'
        $message = ''
        try { $null = Invoke-Agent -Target (ConvertTo-AgentTarget 'opencode') -Workspace $ws -RunDir $runDir -Message 'm' -TimeoutMinutes 1 } catch { $message = "$_" }
        Assert-True ($message -like '*exited with code 3*config error*' -and $message.Length -lt 600) 'a failed opencode list stops the run and quotes only the start of its error output' "$($message.Length) characters: $($message.Substring(0, [Math]::Min(200, $message.Length)))"

        $reallow = '[{"permission":"*","pattern":"*","action":"allow"},{"permission":"skill","pattern":"fsharp-demo","action":"deny"},{"permission":"skill","pattern":"*","action":"allow"}]'
        $denyLast = '[{"permission":"skill","pattern":"*","action":"allow"},{"permission":"skill","pattern":"fsharp-demo","action":"deny"}]'
        foreach ($case in @(@{ Rules = $reallow; Stops = $true }, @{ Rules = $denyLast; Stops = $false })) {
            New-FakeCli 'opencode' ("if (`$args -contains 'agent') { Write-Output 'agent build'; Write-Output '{""name"":""build"",""permission"":" + $case.Rules.Replace("'", "''") + "}' } else { Write-Output '{""mcp"":{}}' }")
            $message = ''
            try { $null = Get-McpServersOff -Target (ConvertTo-AgentTarget 'opencode') -Workspace $ws -HiddenSkills $hidden } catch { $message = "$_" }
            if ($case.Stops) {
                Assert-True ($message -like "*agent 'build' still allows these hidden skills: fsharp-demo*") 'a configuration rule that allows a hidden skill after the deny stops the run' $message
            } else {
                Assert-True ($message -eq '') 'a hidden skill whose deny is the last match passes the check' $message
            }
        }

        $runEvals = Join-Path $PSScriptRoot '../run-evals.ps1'
        $sweep = @{ Skill = 'fsharp-idiom-review'; Task = @('port-order-report'); Mode = 'without'; Runs = 1; TimeoutMinutes = 1 }
        $out = Join-Path $ws 'out-codex'
        $message = ''
        try { $null = & $runEvals @sweep -Target 'codex' -OutputRoot $out 6>$null 3>$null } catch { $message = "$_" }
        Assert-True ($message -like '*still starts these MCP servers: memorizer*') 'the sweep stops before the first run when a Codex server stays on' $message
        Assert-True (@(Get-ChildItem $out -Recurse -Directory -Filter 'r001' -ErrorAction SilentlyContinue).Count -eq 0) 'no run folder exists after the preflight stop'

        New-FakeCli 'claude' 'Write-Output ''{"type":"system","subtype":"init","model":"fake","mcp_servers":[{"name":"memorizer","status":"connected"}]}''; Write-Output ''{"type":"result","subtype":"success","num_turns":1,"usage":{"input_tokens":1,"output_tokens":1}}'''
        $out = Join-Path $ws 'out-claude'
        $message = ''
        try { $null = & $runEvals @sweep -Target 'claude' -OutputRoot $out 6>$null 3>$null } catch { $message = "$_" }
        Assert-True ($message -like '*Run 1 started these MCP servers: memorizer*') 'a Claude run whose init event lists a server stops the sweep' $message
        $runFolder = @(Get-ChildItem $out -Recurse -Directory -Filter 'r001')
        Assert-True ($runFolder.Count -eq 1 -and (Test-Path (Join-Path $runFolder[0].FullName 'run-stopped.json')) -and -not (Test-Path (Join-Path $runFolder[0].FullName 'run.json'))) 'the stopped Claude run writes run-stopped.json and no run.json' (($runFolder | ForEach-Object { Get-ChildItem $_.FullName -Name }) -join ',')
    } finally {
        $env:PATH = $savedPath
    }

    $dry = Invoke-Agent -Target (ConvertTo-AgentTarget 'claude') -Workspace $ws -RunDir $ws -Message 'm' -DryRun
    Assert-True ($dry.Command -like '*--strict-mcp-config*') 'a dry run shows the Claude MCP flag' $dry.Command
    $dry = Invoke-Agent -Target (ConvertTo-AgentTarget 'codex') -Workspace $ws -RunDir $ws -Message 'm' -DryRun
    Assert-True ($dry.Command -like '*features.plugins=false*') 'a dry run shows the Codex plugin override' $dry.Command
} finally {
    Remove-Item -Recurse -Force -LiteralPath $ws -ErrorAction SilentlyContinue
}

if ($failures.Count) {
    $failures | ForEach-Object { Write-Host "FAIL $_" }
    exit 1
}
Write-Host 'All agent argument tests passed.'
