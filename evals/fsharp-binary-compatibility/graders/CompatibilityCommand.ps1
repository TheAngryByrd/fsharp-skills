$shellWrapper = '(?s)^\s*(?:"[^"]*|[^\s"]*)(?<![\w-])(?:pwsh|powershell|bash|sh|zsh)(?:\.exe)?"?(?:\s+-(?!Command\b|c\b|lc\b)\w+(?:\s+(?!-)[^\s"]+)?)*?\s+-(?:Command|c|lc)\s+(?<script>.+)$'
$toolPath = '(?:\S*[\\/])?'
$dotnetStart = '^' + $toolPath + 'dotnet(?:\.exe)?\s+'
$wordEnd = '(?:\s|$)'
$helpOption = '(?:^|\s)(?:--help|-h|-\?|--version)(?:\s|$)'

function Remove-HeredocBodies([string]$Script) {
    $kept = [System.Collections.Generic.List[string]]::new()
    $terminator = $null
    foreach ($line in $Script -split '\r?\n') {
        if ($null -ne $terminator) {
            if ($line.Trim() -ceq $terminator) { $terminator = $null }
            continue
        }
        if ($line -match '<<-?\s*[''"]?(\w+)[''"]?') { $terminator = $Matches[1] }
        elseif ($line -match '@[''"]\s*$') { $terminator = $(if ($line -match "@'\s*$") { "'@" } else { '"@' }) }
        $kept.Add($line)
    }
    $kept -join "`n"
}

function Get-CommandSegments([string]$Command) {
    $script = $Command
    if ($script -match $shellWrapper) {
        $script = $Matches.script.Trim()
        if ($script -match '^"(.*)"$' -or $script -match "^'(.*)'$") { $script = $Matches[1] -replace '\\"', '"' }
    }
    $script = Remove-HeredocBodies $script
    # Quoted text with spaces is message text, except a property value such as -p:OtherFlags="--sig:a.fsi --warnon:1182".
    $script = [regex]::Replace($script, '(?<eq>=)?(?:"([^"\r\n]*)"|''([^''\r\n]*)'')', {
            param($m)
            $value = if ($m.Groups[1].Success) { $m.Groups[1].Value } else { $m.Groups[2].Value }
            if ($m.Groups['eq'].Success) { '=' + ($value -replace '[\s;&|]', '_') }
            elseif ($value -match '^[-/]p(?:roperty)?:') { $value -replace '[\s;&|]', '_' }
            elseif ($value -match '^[^\s;&|]+$') { $value }
            elseif ($value -match '[\\/](dotnet|pwsh|powershell|apicompat|sig-diff\.ps1)(?:\.exe)?$') { $Matches[1] }
            else { '""' }
        })
    foreach ($segment in $script -split '&&|\|\||[;|\r\n]') {
        $s = $segment.Trim() -replace '^&\s*', ''
        do {
            $before = $s
            $s = $s -replace '^(?:then|do|else|time|nohup|env)\s+', '' -replace '^\w+=\S*\s+', ''
        } while ($s -ne $before)
        if ($s) { $s }
    }
}

function Test-CompatibilityCommand {
    param([string]$Command, [bool]$ProjectValidates)
    foreach ($s in @(Get-CommandSegments $Command)) {
        if ($s -match $helpOption) { continue }
        $apicompat = $s -match ($dotnetStart + '(?:tool\s+run\s+)?apicompat' + $wordEnd) -or $s -match ('^' + $toolPath + 'apicompat(?:\.exe)?' + $wordEnd)
        $compares = ($s -match '\s(?:--left|-l|--left-assembly)\s' -and $s -match '\s(?:--right|-r|--right-assembly)\s') -or $s -match '\spackage\s'
        if ($apicompat -and $compares) { return $true }
        if ($s -match ('^(?:' + $toolPath + '(?:pwsh|powershell)(?:\.exe)?\s+(?:-\w+\s+)*)?\S*sig-diff\.ps1\s.*-Project\s')) { return $true }
        $baselineArgument = $s -match '(?i)EnablePackageValidation=true' -and $s -match '(?i)PackageValidationBaseline(?:Version|Path)='
        if ($s -match ($dotnetStart + 'pack' + $wordEnd) -and ($ProjectValidates -or $baselineArgument)) { return $true }
    }
    $false
}

$baselineFolder = '(?:^|[\\/])release-1\.0\.0(?:[\\/]|$)'
$buildValueOption = '^(?:-c|--configuration|-f|--framework|-r|--runtime|-o|--output|-v|--verbosity|-a|--arch|--os|-s|--source|-p|--property|--version-suffix|--artifacts-path)$'

function Get-BuildProject([string]$Segment) {
    $null = $Segment -match ($dotnetStart + '(?<verb>build|msbuild)\s+(?<rest>.*)$')
    $valueOptions = $Matches.verb -eq 'build'
    $tokens = @($Matches.rest -split '\s+' | Where-Object { $_ })
    for ($i = 0; $i -lt $tokens.Count; $i++) {
        if ($valueOptions -and $tokens[$i] -match $buildValueOption) { $i++; continue }
        if ($tokens[$i] -match '^-' -or $tokens[$i] -match '^/\w+(?::|$)' -or $tokens[$i] -match '^(?:true|false|on|off|auto)$') { continue }
        return $tokens[$i]
    }
    ''
}

function Join-Folder([string]$Folder, [string]$Path) {
    $parts = [System.Collections.Generic.List[string]]::new()
    $start = if ($Path -match '^(?:[\\/~]|\w:)') { $Path } else { "$Folder/$Path" }
    foreach ($part in $start -split '[\\/]+') {
        if ($part -eq '..') { if ($parts.Count) { $parts.RemoveAt($parts.Count - 1) } }
        elseif ($part -and $part -ne '.') { $parts.Add($part) }
    }
    $parts -join '/'
}

function Get-SignatureBuilds([string]$Command) {
    $folder = ''
    $pushed = [System.Collections.Generic.Stack[string]]::new()
    foreach ($s in @(Get-CommandSegments $Command)) {
        if ($s -match '^(?<verb>cd|chdir|pushd|Set-Location|Push-Location|sl)(?:\s+(?:-\w+\s+)?(?<dir>\S+))?(?:\s|$)') {
            if ($Matches.verb -in 'pushd', 'Push-Location') { $pushed.Push($folder) }
            $folder = if ($Matches.dir) { Join-Folder $folder $Matches.dir } else { '' }
            continue
        }
        if ($s -match '^(?:popd|Pop-Location)\b') {
            $folder = if ($pushed.Count) { $pushed.Pop() } else { '' }
            continue
        }
        if ($s -notmatch ($dotnetStart + '(?:build|msbuild)\s.*--sig\b')) { continue }
        [pscustomobject]@{ Segment = $s; Baseline = (Join-Folder $folder (Get-BuildProject $s)) -match $baselineFolder }
    }
}

function Test-SignatureBuild([string]$Command) {
    @(Get-SignatureBuilds $Command).Count -gt 0
}
