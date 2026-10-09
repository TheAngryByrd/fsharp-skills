#Requires -Version 7.4
param(
    [Parameter(Mandatory)][string]$Workspace,
    [Parameter(Mandatory)][string]$OutDir,
    [switch]$SkipNative
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../../lib/Grading.psm1') -Force

$checks = @()
$copy = Join-Path $OutDir 'solution'
Copy-Workspace -Workspace $Workspace -Destination $copy
$app = Join-Path $copy 'App/App.fsproj'

$perRecord = @(Get-AgentFiles $copy | Select-String -Pattern 'JsonConverter\s*<\s*(Domain\.)?(Address|Contact|Account)\s*>' | ForEach-Object { "$($_.Filename): $($_.Line.Trim())" })
$checks += New-Check 'No hand-written converter for a record type' ($perRecord.Count -eq 0) ($perRecord -join '; ')

if (-not (Test-Path $app)) {
    $checks += New-Check 'App/App.fsproj builds' $false 'App/App.fsproj missing'
    Write-Checks (Join-Path $OutDir 'grading.json') $checks
    return
}

$r = Invoke-JitAndNative -Project $app -OutRoot (Join-Path $OutDir 'out') -SkipNative:$SkipNative
$checks += New-Check 'App/App.fsproj builds' $r.Built $(if (-not $r.Built) { Get-LastLines $r.BuildLog } else { '' })

$jitLines = if ($r.Jit) { @($r.Jit.Lines | ForEach-Object { $_.TrimEnd() } | Where-Object { $_ }) } else { @() }
$jitText = $jitLines -join "`n"
$json = @($jitLines | Where-Object { $_.TrimStart().StartsWith('{') }) | Select-Object -First 1
$checks += New-Check 'JIT run prints roundtrip=True' ($jitLines.Count -gt 0 -and $jitLines[-1] -match 'roundtrip=True') (Get-LastLines $jitText 4)
$checks += New-Check 'JSON writes None as null and Some without a {"value":...} wrapper' ([bool]$json -and $json -match ':\s*null' -and $json -notmatch '"value"\s*:') "$json"

function Get-PropertyNames($Node) {
    if ($Node -is [System.Collections.IEnumerable] -and $Node -isnot [string]) { foreach ($i in $Node) { Get-PropertyNames $i } }
    elseif ($Node -is [psobject] -and $Node -isnot [string] -and $Node -isnot [ValueType]) {
        foreach ($p in $Node.PSObject.Properties) { $p.Name; Get-PropertyNames $p.Value }
    }
}
$names = @()
if ($json) { try { $names = @(Get-PropertyNames ($json | ConvertFrom-Json)) | Select-Object -Unique } catch { } }
$required = 'id', 'owner', 'name', 'email', 'age', 'addresses', 'street', 'city', 'postCode', 'tags', 'balance', 'parentId'
$missing = @($required | Where-Object { $_ -cnotin $names })
$checks += New-Check 'JSON uses camelCase names for every Account, Contact, and Address field' ($names.Count -gt 0 -and $missing.Count -eq 0) "missing: $($missing -join ', ')"

if ($SkipNative) {
    $checks += New-Check 'App publishes as delivered' $null 'skipped: -SkipNative'
    $checks += New-Check 'Native exe output equals JIT output' $null 'skipped: -SkipNative'
} elseif (-not $r.Built) {
    $checks += New-Check 'App publishes as delivered' $false 'build failed'
    $checks += New-Check 'Native exe output equals JIT output' $false 'build failed'
} else {
    $checks += New-Check 'App publishes as delivered' $r.Published $(if (-not $r.Published) { Get-LastLines $r.PublishLog } else { '' })
    if ($r.Published) {
        $native = @($r.Native.Lines | ForEach-Object { $_.TrimEnd() } | Where-Object { $_ }) -join "`n"
        $checks += New-Check 'Native exe output equals JIT output' ($native -eq $jitText) $(if ($native -ne $jitText) { Get-LastLines $native 4 } else { '' })
    } else {
        $checks += New-Check 'Native exe output equals JIT output' $false 'publish failed'
    }
}

Write-Checks (Join-Path $OutDir 'grading.json') $checks
