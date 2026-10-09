#Requires -Version 7.4
param(
    [Parameter(Mandatory)][string]$Workspace,
    [Parameter(Mandatory)][string]$OutDir,
    [switch]$SkipNative
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../../lib/Grading.psm1') -Force

$checks = @()
$answer = Read-AnswerJson $Workspace
$bugs = @{}
if ($answer -and $answer.PSObject.Properties['bugs']) {
    foreach ($b in @($answer.bugs)) { $bugs[[int]$b.bug] = $b }
}
$checks += New-Check 'answer.json describes bugs 1, 2, and 3' ($bugs.ContainsKey(1) -and $bugs.ContainsKey(2) -and $bugs.ContainsKey(3)) "found $($bugs.Keys -join ',')"

$claims = @(1, 2, 3 | Where-Object { $bugs.ContainsKey($_) -and $bugs[$_].reflectionFreeFixes -eq $true })
$checks += New-Check 'ReflectionFree is judged to fix none of the three bugs' ($bugs.Count -eq 3 -and $claims.Count -eq 0) "claims fix: $($claims -join ',')"

$b1 = if ($bugs.ContainsKey(1)) { $bugs[1] } else { $null }
$checks += New-Check 'Bug 1 cause names the generated ToString or %A path' ([bool]($b1 -and "$($b1.cause)" -match 'ToString|%\+?A')) "$($b1.cause)"
$checks += New-Check 'Bug 1 fix overrides ToString on the union' ([bool]($b1 -and "$($b1.fix)" -match 'override\s+\w+\s*\.\s*ToString')) ''

$b3 = if ($bugs.ContainsKey(3)) { $bugs[3] } else { $null }
$checks += New-Check 'Bug 3 cause names lost tuple contents' ([bool]($b3 -and "$($b3.cause)" -match 'tuple')) "$($b3.cause)"
$fix3 = if ($b3) { "$($b3.fix)".Trim() } else { '' }
$readsEntries = $fix3 -match '\.Key\b|\.Value\b|KeyValue|\(\s*\w+\s*,\s*\w+\s*\)|fun\s+(\w+\s+)?\w+\s+\w+\s*->|fst|snd'
$checks += New-Check 'Bug 3 fix formats each map key and value without %A' ($readsEntries -and $fix3 -notmatch '%\+?A') $fix3

$fix2 = if ($bugs.ContainsKey(2)) { "$($bugs[2].fix)" } else { '' }
$checks += New-Check 'Bug 2 fix keeps %.2f in an interpolated string' ($fix2 -match '\$"[^"]*%\.2f\{') $fix2

if ($SkipNative) {
    $checks += New-Check 'Bug 2 fix prints Avg: 3.14 in the native exe' $null 'skipped: -SkipNative'
} elseif ($fix2 -notmatch '\blet\s+line\b') {
    $checks += New-Check 'Bug 2 fix prints Avg: 3.14 in the native exe' $false 'fix does not bind line'
} else {
    $proj = Join-Path $OutDir 'bug2'
    New-Item -ItemType Directory -Force -Path $proj | Out-Null
    Set-Content (Join-Path $proj 'Bug2.fsproj') @'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net10.0</TargetFramework>
    <PublishAot>true</PublishAot>
    <InvariantGlobalization>true</InvariantGlobalization>
  </PropertyGroup>
  <ItemGroup>
    <Compile Include="Program.fs" />
  </ItemGroup>
</Project>
'@
    $body = ($fix2 -split "`r?`n" | ForEach-Object { '    ' + $_ }) -join "`n"
    Set-Content (Join-Path $proj 'Program.fs') "module Program`n`n[<EntryPoint>]`nlet main _ =`n    let avg = 3.14159`n$body`n    System.Console.WriteLine(line)`n    0`n"
    $r = Invoke-JitAndNative -Project (Join-Path $proj 'Bug2.fsproj') -OutRoot (Join-Path $proj 'out')
    $native = if ($r.Native) { ($r.Native.Lines -join "`n").Trim() } else { '' }
    $evidence = if (-not $r.Built) { Get-LastLines $r.BuildLog } elseif (-not $r.Published) { Get-LastLines $r.PublishLog } else { $native }
    $checks += New-Check 'Bug 2 fix prints Avg: 3.14 in the native exe' ($native -eq 'Avg: 3.14') $evidence
}

Write-Checks (Join-Path $OutDir 'grading.json') $checks
