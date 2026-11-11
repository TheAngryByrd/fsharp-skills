Set-StrictMode -Version Latest

$ResultSchemaVersion = 1
$ProjectedRunKeys = @('target', 'agent', 'model', 'resolvedModel', 'task', 'mode', 'run', 'invocation', 'isolated', 'startedAt', 'skillCommit', 'skillDirty',
    'exitCode', 'timedOut', 'seconds', 'inputTokens', 'outputTokens', 'costUsd', 'turns', 'failedBuilds', 'skillUsed', 'globalSkillUsed', 'checks')
$RequiredRunKeys = @('target', 'agent', 'task', 'mode', 'run', 'skillUsed', 'resolvedModel', 'checks')
$ProjectedTextKeys = @('target', 'agent', 'model', 'resolvedModel', 'task', 'invocation', 'skillCommit')

function Get-Field($Object, [string]$Name) {
    if ($null -ne $Object -and $Object.PSObject.Properties[$Name]) { $Object.$Name } else { $null }
}

function Format-IsoUtc([datetime]$Value) {
    $Value.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture)
}

function ConvertTo-IsoUtc($Value) {
    if ($null -eq $Value) { return $null }
    if ($Value -is [datetime]) { return Format-IsoUtc $Value }
    $parsed = [DateTimeOffset]::MinValue
    $styles = [Globalization.DateTimeStyles]::AssumeUniversal
    if (-not [DateTimeOffset]::TryParse("$Value", [Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$parsed)) { throw "Not a date: '$Value'." }
    Format-IsoUtc $parsed.UtcDateTime
}

$LocalPathPatterns = @(
    '\\'
    '~/'
    '(?<![A-Za-z0-9])[A-Za-z]:/'
    '(?:^|[\s"''`(\[=,])/+[^\s/]'
)

function Test-LocalPath {
    param([AllowNull()][string]$Text, [string]$UserName = [Environment]::UserName)
    if (-not $Text) { return $false }
    foreach ($pattern in $LocalPathPatterns) {
        if ($Text -match $pattern) { return $true }
    }
    $UserName.Length -ge 3 -and $Text -match ('(?<![A-Za-z0-9_])' + [regex]::Escape($UserName) + '(?![A-Za-z0-9_])')
}

function Assert-NoLocalPath([string]$Text, [string]$Where, [string]$Field, [string]$UserName) {
    if (Test-LocalPath $Text -UserName $UserName) {
        throw "${Where}: '$Field' looks like it holds a local path or the user name. Grader check text and target labels must not hold local paths or the user name."
    }
}

function ConvertTo-ProjectedRun {
    # The allowlist and Assert-NoLocalPath are the privacy boundary: workspace, command, and check evidence hold local paths and user names.
    param([Parameter(Mandatory)]$Run, [hashtable]$ResolvedModel = @{}, [string]$UserName = [Environment]::UserName)
    $label = "$(Get-Field $Run 'target')"
    $labelIsSafe = -not (Test-LocalPath $label -UserName $UserName)
    $where = if ($labelIsSafe) { "run $(Get-Field $Run 'id') ($label)" } else { "run $(Get-Field $Run 'id')" }
    foreach ($name in 'target', 'agent', 'task', 'mode', 'run', 'skillUsed') {
        if ($null -eq (Get-Field $Run $name) -or "$(Get-Field $Run $name)" -eq '') { throw "${where}: run.json has no '$name'." }
    }
    if ($Run.mode -notin 'with', 'without') { throw "${where}: mode '$($Run.mode)' is not 'with' or 'without'." }

    $model = "$(Get-Field $Run 'resolvedModel')"
    if (-not $model) { $model = "$($ResolvedModel[$Run.target])" }
    if (-not $model) {
        $key = if ($labelIsSafe) { $label } else { '<target>' }
        throw "${where}: no resolvedModel. Pass -ResolvedModel @{ '$key' = '<exact model>' } to name the exact model."
    }

    $projected = [ordered]@{}
    foreach ($key in $ProjectedRunKeys) { $projected[$key] = Get-Field $Run $key }
    $projected.model = "$(Get-Field $Run 'model')"
    $projected.resolvedModel = $model
    foreach ($key in $ProjectedTextKeys) {
        if ($projected[$key] -is [string]) { Assert-NoLocalPath $projected[$key] $where $key $UserName }
    }
    $projected.startedAt = ConvertTo-IsoUtc (Get-Field $Run 'startedAt')
    $checks = @(@(Get-Field $Run 'checks') | Where-Object { $null -ne $_ })
    $projected.checks = @(for ($i = 0; $i -lt $checks.Count; $i++) {
            $text = "$($checks[$i].text)"
            Assert-NoLocalPath $text $where "checks[$i].text" $UserName
            [ordered]@{ text = $text; passed = $checks[$i].passed }
        })
    $projected
}

function ConvertTo-ResultSetJson {
    param([Parameter(Mandatory)][string]$Skill, [Parameter(Mandatory)][string]$RunId, [Parameter(Mandatory)][object[]]$Runs)
    $set = [ordered]@{ schemaVersion = $ResultSchemaVersion; skill = $Skill; runId = $RunId; runs = $Runs }
    ($set | ConvertTo-Json -Depth 8 -EscapeHandling Default) -replace '\r\n', "`n"
}

function Test-RunId([string]$RunId) { $RunId -match '^\d{8}-\d{6}$' }

function Write-FileAtomic {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Content)
    $folder = Split-Path $Path
    New-Item -ItemType Directory -Force -Path $folder | Out-Null
    $temp = Join-Path $folder ".$([IO.Path]::GetFileName($Path)).$([guid]::NewGuid().ToString('n')).tmp"
    try {
        [IO.File]::WriteAllText($temp, $Content, [Text.UTF8Encoding]::new($false, $true))
        [IO.File]::Move($temp, $Path, $true)
    } finally {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force }
    }
}

function Read-ResultSet {
    param([Parameter(Mandatory)][string]$Path)
    $set = Get-Content -Raw $Path | ConvertFrom-Json
    if ((Get-Field $set 'schemaVersion') -ne $ResultSchemaVersion) { throw "${Path}: schemaVersion must be $ResultSchemaVersion." }
    foreach ($name in 'skill', 'runId') {
        if (-not (Get-Field $set $name)) { throw "${Path}: no '$name'." }
    }
    if (-not (Test-RunId "$($set.runId)")) { throw "${Path}: runId '$($set.runId)' is not in the form yyyyMMdd-HHmmss." }
    if (-not $set.PSObject.Properties['runs']) { throw "${Path}: no 'runs'." }
    $runs = foreach ($run in @($set.runs)) {
        foreach ($key in $RequiredRunKeys) {
            if (-not $run.PSObject.Properties[$key]) { throw "${Path}: a run has no '$key'." }
        }
        if ($run.mode -notin 'with', 'without') { throw "${Path}: mode '$($run.mode)' is not 'with' or 'without'." }
        if (-not "$($run.resolvedModel)".Trim()) { throw "${Path}: run $($run.target) | $($run.task) | $($run.mode) | $($run.run) has no resolvedModel." }
        foreach ($check in @($run.checks | Where-Object { $null -ne $_ })) {
            foreach ($key in 'text', 'passed') {
                if (-not $check.PSObject.Properties[$key]) { throw "${Path}: a check has no '$key'." }
            }
        }
        foreach ($key in $ProjectedRunKeys) {
            if (-not $run.PSObject.Properties[$key]) { $run | Add-Member -NotePropertyName $key -NotePropertyValue $null }
        }
        $run.startedAt = ConvertTo-IsoUtc $run.startedAt
        $run
    }
    [pscustomobject]@{ skill = "$($set.skill)"; runId = "$($set.runId)"; runs = @($runs) }
}

function Get-SkillCatalog {
    param([Parameter(Mandatory)][string]$EvalsRoot, [Parameter(Mandatory)][string]$SkillsRoot)
    foreach ($file in Get-ChildItem -Path $EvalsRoot -Filter 'evals.json' -Recurse -Depth 1 | Sort-Object FullName) {
        $spec = Get-Content -Raw $file.FullName | ConvertFrom-Json
        $skillFile = Join-Path $SkillsRoot "$($spec.skill)/SKILL.md"
        $description = ''
        if (Test-Path $skillFile) {
            $line = Get-Content $skillFile -TotalCount 20 | Where-Object { $_ -match '^description:\s*' } | Select-Object -First 1
            if ($line) { $description = ($line -replace '^description:\s*', '').Trim().Trim('"', "'") }
        }
        [pscustomobject]@{ skill = "$($spec.skill)"; description = $description; tasks = @($spec.tasks | ForEach-Object { "$($_.id)" }) }
    }
}

Export-ModuleMember -Function ConvertTo-ProjectedRun, ConvertTo-ResultSetJson, Read-ResultSet, Get-SkillCatalog, ConvertTo-IsoUtc, Format-IsoUtc, Test-LocalPath, Test-RunId, Write-FileAtomic
