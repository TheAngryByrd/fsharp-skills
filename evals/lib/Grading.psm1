Set-StrictMode -Version Latest

function New-Check {
    param(
        [Parameter(Mandatory)][string]$Text,
        [AllowNull()][Nullable[bool]]$Passed,
        [string]$Evidence = ''
    )
    [pscustomobject]@{ text = $Text; passed = $Passed; evidence = $Evidence }
}

function Write-Checks {
    param([Parameter(Mandatory)][string]$ResultPath, [object[]]$Checks)
    ConvertTo-Json -InputObject @($Checks) -Depth 5 | Set-Content -Path $ResultPath -Encoding utf8
}

function Read-AnswerJson {
    param([Parameter(Mandatory)][string]$Workspace)
    $path = Join-Path $Workspace 'answer.json'
    if (-not (Test-Path $path)) { return $null }
    try { Get-Content -Raw $path | ConvertFrom-Json } catch { $null }
}

function Get-AgentFiles {
    param([Parameter(Mandatory)][string]$Workspace, [string[]]$Include = @('*.fs', '*.fsx', '*.cs'))
    Get-ChildItem -Path $Workspace -Recurse -File -Include $Include |
        Where-Object { $_.FullName -notmatch '[\\/](\.claude|\.agents|\.opencode|\.git|bin|obj)[\\/]' }
}

function Copy-Workspace {
    param([Parameter(Mandatory)][string]$Workspace, [Parameter(Mandatory)][string]$Destination)
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    $root = (Resolve-Path $Workspace).Path
    Get-ChildItem -Path $root -Recurse -File -Force |
        Where-Object { $_.FullName.Substring($root.Length) -notmatch '^[\\/]?(\.claude|\.agents|\.opencode|\.git)[\\/]|[\\/](bin|obj)[\\/]' } |
        ForEach-Object {
            $target = Join-Path $Destination $_.FullName.Substring($root.Length).TrimStart('\', '/')
            New-Item -ItemType Directory -Force -Path (Split-Path $target) | Out-Null
            Copy-Item $_.FullName $target
        }
}

function Invoke-Capture {
    param([Parameter(Mandatory)][string]$FilePath, [string[]]$Arguments = @(), [string]$WorkingDirectory = $PWD.Path)
    Push-Location $WorkingDirectory
    try {
        $output = & $FilePath @Arguments 2>&1 | ForEach-Object { "$_" }
        [pscustomobject]@{ ExitCode = $LASTEXITCODE; Lines = @($output); Text = ($output -join "`n") }
    } finally {
        Pop-Location
    }
}

function Get-RuntimeId { [System.Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier }

# dotnet selects its SDK from global.json above the working directory, so each command runs in the project directory.
function Invoke-JitAndNative {
    param(
        [Parameter(Mandatory)][string]$Project,
        [Parameter(Mandatory)][string]$OutRoot,
        [switch]$SkipNative
    )
    $name = [IO.Path]::GetFileNameWithoutExtension($Project)
    $dir = Split-Path (Resolve-Path $Project).Path
    $result = [ordered]@{ Built = $false; BuildLog = ''; Jit = $null; Published = $null; PublishLog = ''; Native = $null }

    $build = Invoke-Capture dotnet @('build', $Project, '-c', 'Release', '-o', (Join-Path $OutRoot 'jit')) -WorkingDirectory $dir
    $result.BuildLog = $build.Text
    if ($build.ExitCode -ne 0) { return [pscustomobject]$result }
    $result.Built = $true
    $result.Jit = Invoke-Capture dotnet @((Join-Path $OutRoot "jit/$name.dll")) -WorkingDirectory $dir

    if ($SkipNative) { return [pscustomobject]$result }
    $aot = Invoke-Capture dotnet @('msbuild', $Project, '-getProperty:PublishAot', '-p:Configuration=Release', "-p:RuntimeIdentifier=$(Get-RuntimeId)") -WorkingDirectory $dir
    if ($aot.ExitCode -ne 0) {
        $result.Published = $false
        $result.PublishLog = "MSBuild could not evaluate PublishAot.`n$($aot.Text)"
        return [pscustomobject]$result
    }
    if ($aot.Text.Trim() -ne 'true') {
        $result.Published = $false
        $result.PublishLog = "The project does not set PublishAot to true for Release. Evaluated value: '$($aot.Text.Trim())'."
        return [pscustomobject]$result
    }
    $publish = Invoke-Capture dotnet @('publish', $Project, '-c', 'Release', '-r', (Get-RuntimeId), '-o', (Join-Path $OutRoot 'native')) -WorkingDirectory $dir
    $result.PublishLog = $publish.Text
    $result.Published = $publish.ExitCode -eq 0
    if ($result.Published) {
        $exe = Join-Path $OutRoot ('native/' + $name + $(if ($IsWindows) { '.exe' } else { '' }))
        $result.Native = Invoke-Capture $exe -WorkingDirectory $dir
    }
    [pscustomobject]$result
}

function Get-LastLines {
    param([string]$Text, [int]$Count = 15)
    (($Text -split "`n") | Select-Object -Last $Count) -join "`n"
}

function ConvertFrom-ProbeOutput {
    param([string[]]$Lines)
    foreach ($line in $Lines) {
        if ($line -notmatch '^(PASS|FAIL) ') { continue }
        $name = ($line -replace '^(PASS|FAIL) ', '') -replace ' \[.*\]$', ''
        New-Check $name ($line.StartsWith('PASS')) $(if ($line.StartsWith('FAIL')) { $line } else { '' })
    }
}

function Get-ProbeScript {
    param(
        [Parameter(Mandatory)][string]$ProbePath,
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$Module
    )
    $text = Get-Content -Raw $ProbePath
    $name = [regex]::Escape($Module)
    # A script that declares `module X =` loads as the nested module X.X.
    if ((Get-Content -Raw $SourcePath) -match "(?m)^module\s+$name\s*=") {
        $text = $text -replace "(?m)^open $name\r?$", "open $Module`nopen $Module.$Module"
    }
    $text
}

function Get-TaskSpec {
    param([Parameter(Mandatory)][string]$EvalDir, [Parameter(Mandatory)][string]$TaskId)
    $spec = Get-Content -Raw (Join-Path $EvalDir 'evals.json') | ConvertFrom-Json
    $task = $spec.tasks | Where-Object id -eq $TaskId | Select-Object -First 1
    if (-not $task) { throw "evals.json in $EvalDir has no task $TaskId." }
    $task
}

function New-TempDirectory {
    $dir = Join-Path ([IO.Path]::GetTempPath()) ('skill-eval-' + [guid]::NewGuid().ToString('n'))
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $dir
}

function Get-WorkspaceDiff {
    param(
        [Parameter(Mandatory)][string]$Workspace,
        [Parameter(Mandatory)][string]$EvalDir,
        [Parameter(Mandatory)][string]$TaskId
    )
    $task = Get-TaskSpec -EvalDir $EvalDir -TaskId $TaskId
    $temp = New-TempDirectory
    try {
        $before = Join-Path $temp 'before'
        $after = Join-Path $temp 'after'
        New-Item -ItemType Directory -Force -Path $before | Out-Null
        foreach ($f in @($task.files)) { Copy-Item (Join-Path $EvalDir $f) $before -Recurse }
        Copy-Workspace -Workspace $Workspace -Destination $after
        Remove-Item (Join-Path $after 'TASK.md') -Force -ErrorAction SilentlyContinue
        # git diff --no-index exits 1 when the trees differ.
        $result = Invoke-Utf8Native { Invoke-Capture git @('-c', 'core.quotepath=false', '-c', 'core.autocrlf=false', 'diff', '--no-index', '--no-color', '--no-ext-diff', '--no-textconv', '--ignore-cr-at-eol', '--', 'before', 'after') -WorkingDirectory $temp }
        if ($result.ExitCode -gt 1) { throw "git diff failed: $($result.Text)" }
        $result.Text
    } finally {
        Remove-Item -Recurse -Force $temp -ErrorAction SilentlyContinue
    }
}

$RubricDiffLimit = 60000
$RubricMinQuoteLength = 4

$RubricSchema = @{
    type = 'object'; required = @('items')
    properties = @{
        items = @{
            type = 'array'
            items = @{
                type = 'object'; required = @('id', 'answer', 'quote')
                properties = @{ id = @{ type = 'string' }; answer = @{ type = 'string'; enum = @('yes', 'no') }; quote = @{ type = 'string' } }
            }
        }
    }
} | ConvertTo-Json -Depth 10 -Compress

$RubricSystemPrompt = 'You review code changes against a rubric. Answer each item with yes or no. Base each answer only on the diff. Copy the quote exactly from one added or removed diff line.'

function Get-JudgeCommand {
    $configured = $env:SKILL_EVAL_JUDGE
    if (-not $configured) {
        return @('claude', '-p', '--model', 'haiku', '--tools', '', '--disable-slash-commands', '--no-session-persistence', '--strict-mcp-config',
            '--setting-sources', '', '--system-prompt', $RubricSystemPrompt, '--output-format', 'json', '--json-schema', $RubricSchema)
    }
    if ($configured.Trim() -eq 'off') { return $null }
    $invalid = "SKILL_EVAL_JUDGE must be 'off' or a JSON array of the command and its arguments. Value: $configured"
    try { $parsed = ConvertFrom-Json -InputObject $configured -NoEnumerate } catch { throw $invalid }
    if ($parsed -isnot [array] -or $parsed.Count -eq 0 -or @($parsed | Where-Object { $_ -isnot [string] }).Count -or -not $parsed[0]) { throw $invalid }
    [string[]]$parsed
}

function Get-RubricPrompt {
    param([Parameter(Mandatory)][object[]]$Items, [Parameter(Mandatory)][AllowEmptyString()][string]$Diff)
    $lines = @(
        'Review the diff below against each rubric item.',
        'Answer "yes" or "no" for each item.',
        'For each item, give one quote: an exact substring of one added (+) or removed (-) diff line, without the marker, that shows the answer. Unchanged context lines do not count.',
        'If no diff line shows the answer, give an empty quote.',
        'Reply with JSON only, in this shape: {"items":[{"id":"<item id>","answer":"yes","quote":"<exact text from the diff>"}]}',
        '',
        'Rubric items:'
    )
    $lines += $Items | ForEach-Object { "- $($_.id): $($_.question)" }
    $lines += @('', 'Diff (before/ is the task input, after/ is the result):', '```diff', $Diff, '```')
    $lines -join "`n"
}

function ConvertTo-NormalizedCode([string]$Line) { ($Line -replace '\s+', ' ').Trim() }

function Get-DiffBodyLines([string]$Diff) {
    $inHunk = $false
    foreach ($line in $Diff -split "\r?\n") {
        if ($line.StartsWith('diff --git ')) { $inHunk = $false; continue }
        if ($line.StartsWith('@@')) { $inHunk = $true; continue }
        if (-not $inHunk -or $line -notmatch '^[+\-]') { continue }
        $code = ConvertTo-NormalizedCode $line.Substring(1)
        if ($code) { $code }
    }
}

function Test-QuoteInDiff([string]$Quote, [string[]]$BodyLines) {
    $quoteLines = @($Quote -split "\r?\n" | Where-Object { $_.Trim() })
    if ($quoteLines.Count -ne 1) { return $false }
    $code = ConvertTo-NormalizedCode ($quoteLines[0].Trim() -replace '^[+\-]\s?', '')
    if ($code.Length -lt $RubricMinQuoteLength) { return $false }
    @($BodyLines | Where-Object { $_.Contains($code) }).Count -gt 0
}

function Get-JsonField($Object, [string]$Name) {
    if ($Object -is [psobject] -and $Object.PSObject.Properties[$Name]) { $Object.$Name } else { $null }
}

function ConvertFrom-JudgeOutput([string]$Text) {
    $candidates = @($Text.Trim())
    $start = $Text.IndexOf('{'); $end = $Text.LastIndexOf('}')
    if ($start -ge 0 -and $end -gt $start) { $candidates += $Text.Substring($start, $end - $start + 1) }
    foreach ($candidate in $candidates) {
        try { $obj = ConvertFrom-Json -InputObject $candidate -Depth 20 } catch { continue }
        if ($obj -isnot [psobject]) { continue }
        $structured = Get-JsonField $obj 'structured_output'
        if ($structured) { $obj = $structured }
        $items = Get-JsonField $obj 'items'
        if ($items -is [array]) { return , $items }
        if ($items -is [psobject] -and $items -isnot [string]) { return , @($items) }
        $result = Get-JsonField $obj 'result'
        if ($result -is [string] -and $result -ne $Text) {
            $inner = ConvertFrom-JudgeOutput $result
            if ($null -ne $inner) { return , $inner }
        }
    }
    $null
}

function Invoke-Utf8Native([scriptblock]$Script) {
    # PowerShell decodes native stdout with the console code page, which is not UTF-8 by default on Windows.
    $previous = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
        & $Script
    } finally {
        [Console]::OutputEncoding = $previous
    }
}

function Invoke-Judge {
    param([Parameter(Mandatory)][AllowEmptyString()][string[]]$Command, [Parameter(Mandatory)][string]$Prompt)
    $temp = New-TempDirectory
    try {
        $promptFile = Join-Path $temp 'prompt.txt'
        $errFile = Join-Path $temp 'stderr.txt'
        Set-Content -Path $promptFile -Value $Prompt -Encoding utf8NoBOM -NoNewline
        $exe, $arguments = $Command
        Push-Location $temp
        try {
            $output = Invoke-Utf8Native { Get-Content -Raw -Encoding utf8 $promptFile | & $exe @arguments 2>$errFile }
            $exit = $LASTEXITCODE
        } finally { Pop-Location }
        $stderr = if (Test-Path $errFile) { Get-Content -Raw $errFile } else { '' }
        [pscustomobject]@{ ExitCode = $exit; Output = (@($output) -join "`n"); Stderr = "$stderr" }
    } finally {
        Remove-Item -Recurse -Force $temp -ErrorAction SilentlyContinue
    }
}

function Get-RubricChecks {
    param([object[]]$Items, [string]$Diff, [object[]]$Answers)
    $bodyLines = @(Get-DiffBodyLines $Diff)
    foreach ($item in $Items) {
        $text = "Rubric $($item.id): $($item.question)"
        $hit = @($Answers | Where-Object { "$(Get-JsonField $_ 'id')" -eq "$($item.id)" }) | Select-Object -First 1
        if (-not $hit) { New-Check $text $null 'skipped: the judge gave no answer for this item'; continue }
        $quote = "$(Get-JsonField $hit 'quote')"
        $verdict = "$(Get-JsonField $hit 'answer')".Trim().ToLowerInvariant()
        if ($verdict -notin 'yes', 'no') { New-Check $text $null "skipped: the judge answer '$verdict' is not yes or no"; continue }
        if (-not (Test-QuoteInDiff $quote $bodyLines)) {
            New-Check $text $null "skipped: judge quote not found in one diff line: '$quote'"; continue
        }
        New-Check $text ($verdict -eq 'yes') "${verdict}: $quote"
    }
}

function Invoke-Rubric {
    param(
        [Parameter(Mandatory)][string]$Workspace,
        [Parameter(Mandatory)][string]$EvalDir,
        [Parameter(Mandatory)][string]$TaskId
    )
    $spec = Get-Content -Raw (Join-Path $EvalDir 'evals.json') | ConvertFrom-Json
    $task = Get-TaskSpec -EvalDir $EvalDir -TaskId $TaskId
    $items = @(@(if ($task.PSObject.Properties['rubric']) { $task.rubric }) | ForEach-Object {
            [pscustomobject]@{ id = "$(Get-JsonField $_ 'id')"; question = "$(Get-JsonField $_ 'question')" }
        })
    if ($items.Count -eq 0) { return @() }
    $skipAll = { param($reason) $items | ForEach-Object { New-Check "Rubric $($_.id): $($_.question)" $null "skipped: $reason" } }
    if (@($items | Where-Object { -not $_.id -or -not $_.question }).Count) {
        return @(& $skipAll "each rubric item in $TaskId needs an id and a question")
    }

    try {
        $command = Get-JudgeCommand
        if (-not $command) { return @(& $skipAll 'the judge is off (SKILL_EVAL_JUDGE=off)') }
        $diff = Get-WorkspaceDiff -Workspace $Workspace -EvalDir $EvalDir -TaskId $TaskId
        if ($spec.PSObject.Properties['skill'] -and $spec.skill) {
            $diff = $diff -replace ([regex]::Escape("$($spec.skill)-eval") + '(?![\w-])'), $spec.skill
        }
        if ($diff.Length -gt $RubricDiffLimit) { $diff = $diff.Substring(0, $RubricDiffLimit) + "`n[diff cut at $RubricDiffLimit characters]" }

        $run = Invoke-Judge -Command $command -Prompt (Get-RubricPrompt -Items $items -Diff $diff)
        if ($run.ExitCode -ne 0) { return @(& $skipAll "the judge exited with code $($run.ExitCode): $(Get-LastLines ($run.Stderr + "`n" + $run.Output) 3)") }
        $answers = ConvertFrom-JudgeOutput $run.Output
        if ($null -eq $answers) { return @(& $skipAll "the judge output has no items array: $(Get-LastLines $run.Output 3)") }
        @(Get-RubricChecks -Items $items -Diff $diff -Answers $answers)
    } catch {
        @(& $skipAll "the rubric could not run: $_")
    }
}

Export-ModuleMember -Function New-Check, Write-Checks, Read-AnswerJson, Get-AgentFiles, Copy-Workspace,
    Invoke-Capture, Get-RuntimeId, Invoke-JitAndNative, Get-LastLines, ConvertFrom-ProbeOutput, Get-ProbeScript, Get-WorkspaceDiff, Invoke-Rubric
