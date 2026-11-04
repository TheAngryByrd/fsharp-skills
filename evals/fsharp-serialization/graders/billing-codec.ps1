#Requires -Version 7.4
param(
    [Parameter(Mandatory)][string]$Workspace,
    [Parameter(Mandatory)][string]$OutDir,
    [switch]$SkipNative
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../../lib/Grading.psm1') -Force

$Workspace = (Resolve-Path $Workspace).Path
$inputs = Join-Path $PSScriptRoot '../inputs/billing'
$compileCheck = 'Codec.fsx and the probe compile together'
$checks = @()

$domain = Join-Path $Workspace 'Domain.fsx'
$original = (Get-Content -Raw (Join-Path $inputs 'Domain.fsx')) -replace '\r\n', "`n"
$current = if (Test-Path $domain) { (Get-Content -Raw $domain) -replace '\r\n', "`n" } else { '' }
$checks += New-Check 'Domain.fsx is unchanged' ($current.TrimEnd() -eq $original.TrimEnd()) $(if (Test-Path $domain) { '' } else { 'Domain.fsx missing' })

$source = Join-Path $Workspace 'Codec.fsx'
if (-not (Test-Path $source)) {
    $checks += New-Check $compileCheck $false 'Codec.fsx missing'
    Write-Checks (Join-Path $OutDir 'grading.json') $checks
    return
}

function Get-Code([string]$Path, [switch]$WithoutStrings) {
    $tokens = '"""[\s\S]*?"""|@"(?:""|[^"])*"|"(?:\\.|[^"\\])*"|\(\*[\s\S]*?\*\)|//[^\n]*'
    [regex]::Replace((Get-Content -Raw $Path), $tokens, {
            param($m)
            if ($m.Value.StartsWith('(*') -or $m.Value.StartsWith('//')) { '' }
            elseif ($WithoutStrings) { '""' }
            else { $m.Value }
        })
}

function Get-LoadedSources([string]$Path, [System.Collections.Generic.HashSet[string]]$Seen) {
    $full = [IO.Path]::GetFullPath($Path)
    if (-not (Test-Path $full) -or -not $Seen.Add($full)) { return }
    $full
    foreach ($line in [regex]::Matches((Get-Code $full), '(?m)^\s*#load\s+(.+)$')) {
        foreach ($name in [regex]::Matches($line.Groups[1].Value, '"([^"]+)"')) {
            Get-LoadedSources (Join-Path (Split-Path $full) $name.Groups[1].Value) $Seen
        }
    }
}

$seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$seen.Add([IO.Path]::GetFullPath($domain)) | Out-Null
$sources = @(Get-LoadedSources $source $seen)
$code = ($sources | ForEach-Object { Get-Code $_ -WithoutStrings }) -join "`n"
$byHand = @([regex]::Matches($code, '\b(JsonDocument|JsonNode|JsonObject|JsonArray|JsonValue|JsonElement|Utf8JsonReader|Utf8JsonWriter)\b|\bJsonConverter\s*<') | ForEach-Object Value | Sort-Object -Unique)
$checks += New-Check 'The codec uses JsonSerializer and does not read or write JSON by hand' ($code -match 'JsonSerializer\.(Serialize|Deserialize)' -and $byHand.Count -eq 0) $(if ($byHand) { 'uses ' + ($byHand -join ', ') } else { '' })

$dir = Join-Path $OutDir 'probe'
Copy-Workspace -Workspace $Workspace -Destination $dir
Copy-Item (Join-Path $inputs 'Domain.fsx') $dir -Force
$saved = Join-Path $dir 'grader-samples'
if (Test-Path $saved) { Remove-Item -Recurse -Force $saved }
Copy-Item (Join-Path $inputs 'samples') $saved -Recurse
'{ "sdk": { "version": "10.0.100", "rollForward": "latestFeature" } }' | Set-Content (Join-Path $dir 'global.json')
Get-ProbeScript -ProbePath (Join-Path $PSScriptRoot 'CodecProbe.fsx') -SourcePath $source -Module 'Codec' |
    Set-Content (Join-Path $dir 'CodecProbe.fsx')

$probe = Invoke-Capture dotnet @('fsi', 'CodecProbe.fsx') -WorkingDirectory $dir
$results = @(ConvertFrom-ProbeOutput $probe.Lines)
$checks += New-Check $compileCheck ($probe.ExitCode -eq 0 -and $results.Count -gt 0) $(if ($results.Count -eq 0) { Get-LastLines $probe.Text 8 } else { '' })
$checks += $results

Write-Checks (Join-Path $OutDir 'grading.json') $checks
