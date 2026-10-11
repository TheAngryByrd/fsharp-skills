Set-StrictMode -Version Latest
# Callers import ../../lib/Grading.psm1 first. This module uses its functions from the global scope.

$globalJson = '{ "sdk": { "version": "10.0.100", "rollForward": "latestFeature" } }'

function Get-NullnessGlobalJson { $globalJson }

function Get-NullnessSettingsCheck {
    param([Parameter(Mandatory)][string]$Project)
    $dir = Split-Path $Project
    $r = Invoke-Capture dotnet @('msbuild', $Project, '-getProperty:Nullable', '-getProperty:TreatWarningsAsErrors',
        '-getProperty:NoWarn', '-getProperty:WarningsNotAsErrors', '-getProperty:OtherFlags', '-getProperty:WarningLevel', '-getProperty:LangVersion', '-getProperty:TargetFramework', '-getProperty:TargetFrameworks', '-p:Configuration=Release') -WorkingDirectory $dir
    if ($r.ExitCode -ne 0) { return New-Check 'The project targets .NET 10 or later and turns on nullness and warnings as errors, with no FS3261 exemption' $false (Get-LastLines $r.Text) }
    $p = ($r.Text | ConvertFrom-Json).Properties
    $exempt = "$($p.NoWarn);$($p.WarningsNotAsErrors)" -match '(FS)?326[12]' -or
        $p.OtherFlags -match '--(nowarn|warnaserror-)[:+]?\S*326[12]' -or
        $p.OtherFlags -match '--warnaserror-(\s|$)' -or
        $p.OtherFlags -match '--warn:[0-2](\s|$)' -or
        ($p.WarningLevel -match '^\d+$' -and [int]$p.WarningLevel -lt 3)
    $oldLang = $p.LangVersion -match '^(\d+)(\.\d+)?$' -and [int]$Matches[1] -lt 9
    $nullness = -not $oldLang -and ($p.Nullable -eq 'enable' -or $p.OtherFlags -match '--checknulls(\+|\s|$)') -and
        $p.OtherFlags -notmatch '--checknulls-'
    $tfms = @("$($p.TargetFramework);$($p.TargetFrameworks)" -split ';' | Where-Object { $_ })
    $net10 = $tfms.Count -gt 0 -and -not ($tfms | Where-Object { -not ($_ -match '^net(\d+)\.' -and [int]$Matches[1] -ge 10) })
    $ok = $net10 -and $nullness -and $p.TreatWarningsAsErrors -eq 'true' -and -not $exempt
    New-Check 'The project targets .NET 10 or later and turns on nullness and warnings as errors, with no FS3261 exemption' $ok `
        "Nullable='$($p.Nullable)' OtherFlags='$($p.OtherFlags)' TreatWarningsAsErrors='$($p.TreatWarningsAsErrors)' NoWarn='$($p.NoWarn)' WarningsNotAsErrors='$($p.WarningsNotAsErrors)' WarningLevel='$($p.WarningLevel)' LangVersion='$($p.LangVersion)' TargetFramework='$($p.TargetFramework)$($p.TargetFrameworks)'"
}

function Get-ProjectBuildCheck {
    param([Parameter(Mandatory)][string]$Project)
    $r = Invoke-Capture dotnet @('build', $Project, '-c', 'Release', '-p:Nullable=enable', '-p:TreatWarningsAsErrors=true') -WorkingDirectory (Split-Path $Project)
    $errors = ($r.Lines | Where-Object { $_ -match ' error ' } | Sort-Object -Unique) -join "`n"
    New-Check 'The delivered project builds with Nullable=enable and TreatWarningsAsErrors=true forced on' ($r.ExitCode -eq 0) $(if ($r.ExitCode -ne 0) { Get-LastLines $(if ($errors) { $errors } else { $r.Text }) } else { '' })
}

function Get-SuppressionCheck {
    param([Parameter(Mandatory)][string]$Workspace)
    $found = @()
    foreach ($file in Get-AgentFiles $Workspace @('*.fs', '*.fsx', '*.fsproj', '*.props', '*.targets')) {
        $lines = @(Get-Content $file.FullName)
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            $where = "$($file.Name):$($i + 1): $($line.Trim())"
            if ($line -match '^\s*#nowarn\b.*326[12]|<(NoWarn|WarningsNotAsErrors)\b[^>]*>[^<]*326[12]') { $found += $where; continue }
            $stripped = [regex]::Replace($line, '(\$?)(@"(?:[^"]|"")*"|"""[\s\S]*?"""|"(?:[^"\\]|\\.)*"|''(?:[^''\\]|\\.)'')', {
                    param($m)
                    if ($m.Groups[1].Value) { '$' + $m.Groups[2].Value.Replace('//', '/ /') } else { '""' }
                })
            $parts = $stripped -split '//', 2
            if ($parts[0] -cmatch '\bnonNull\b|\bNonNullQuick\b|\bnullArgCheck\b') {
                $reasonHere = ($parts.Count -eq 2 -and $parts[1] -match '^(?!/)\s*\S') -or $parts[0] -match '\(\*\s*\w'
                $above = if ($i -gt 0) { $lines[$i - 1].Trim() } else { '' }
                $reasonAbove = $above -match '^//(?!/)\s*\S' -or $above -match '^\(\*\s*\w|\(\*.*\w.*\*\)\s*$'
                if (-not ($reasonHere -or $reasonAbove)) { $found += $where }
            }
        }
    }
    New-Check 'No null is suppressed without a reason (any FS3261 nowarn fails, and nonNull, Unchecked.nonNull, NonNullQuick, or nullArgCheck needs a comment)' ($found.Count -eq 0) ($found -join "`n")
}

function Invoke-NullnessDriver {
    param(
        [Parameter(Mandatory)][string]$Project,
        [Parameter(Mandatory)][string]$Driver,
        [Parameter(Mandatory)][string]$OutDir
    )
    $proj = Join-Path $OutDir 'driver'
    New-Item -ItemType Directory -Force -Path $proj | Out-Null
    Set-Content (Join-Path $proj 'global.json') $globalJson
    Copy-Item $Driver (Join-Path $proj 'Driver.fs')
    $compile = @(
        '    <Compile Include="Driver.fs" />'
        "    <ProjectReference Include=`"$((Resolve-Path $Project).Path)`" />"
    )
    Set-Content (Join-Path $proj 'Driver.fsproj') @"
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net10.0</TargetFramework>
    <Nullable>enable</Nullable>
    <TreatWarningsAsErrors>false</TreatWarningsAsErrors>
    <InvariantGlobalization>true</InvariantGlobalization>
  </PropertyGroup>
  <ItemGroup>
$($compile -join "`n")
  </ItemGroup>
</Project>
"@
    $build = Invoke-Capture dotnet @('build', 'Driver.fsproj', '-c', 'Release', '-o', 'out') -WorkingDirectory $proj
    $driverDiagnostics = @($build.Lines | Where-Object { $_ -match 'Driver\.fs\(\d+,\d+\): (warning|error) FS\d+' } |
        ForEach-Object { ($_ -replace '^.*Driver\.fs', 'Driver.fs') -replace '\s*\[.*$', '' } | Sort-Object -Unique)
    $run = $null
    if ($build.ExitCode -eq 0) { $run = Invoke-Capture dotnet @('out/Driver.dll') -WorkingDirectory $proj }
    [pscustomobject]@{ Built = $build.ExitCode -eq 0; BuildLog = $build.Text; DriverDiagnostics = $driverDiagnostics; Run = $run }
}

function Get-BehaviorChecks {
    param([Parameter(Mandatory)]$Result, [Parameter(Mandatory)][string]$ExpectedPath)
    $expected = @(Get-Content $ExpectedPath | Where-Object { $_ })
    $actual = @{}
    if ($Result.Run) {
        foreach ($line in $Result.Run.Lines) {
            $parts = "$line".TrimEnd() -split ' \| ', 2
            if ($parts.Count -eq 2) { $actual[$parts[0]] = "$line".TrimEnd() }
        }
    }
    $groups = [ordered]@{}
    foreach ($want in $expected) {
        $key = ($want -split ' \| ', 2)[0]
        $fn = ($key -split '-', 2)[0]
        if (-not $groups.Contains($fn)) { $groups[$fn] = @() }
        $groups[$fn] += [pscustomobject]@{ Key = $key; Want = $want }
    }
    foreach ($fn in $groups.Keys) {
        if (-not $Result.Built) {
            New-Check "$fn follows its doc comment for null and non-null inputs" $null 'skipped: driver build failed'
            continue
        }
        $bad = @($groups[$fn] | Where-Object { $actual[$_.Key] -cne $_.Want } |
            ForEach-Object { "expected '$($_.Want)', got '$($actual[$_.Key])'" })
        New-Check "$fn follows its doc comment for null and non-null inputs" ($bad.Count -eq 0) ($bad -join "`n")
    }
}

Export-ModuleMember -Function Get-NullnessGlobalJson, Get-NullnessSettingsCheck, Get-ProjectBuildCheck, Get-SuppressionCheck, Invoke-NullnessDriver, Get-BehaviorChecks
