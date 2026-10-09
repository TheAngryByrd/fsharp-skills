#Requires -Version 7.4
param(
    [Parameter(Mandatory)][string]$Workspace,
    [Parameter(Mandatory)][string]$OutDir,
    [switch]$SkipNative
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../../lib/Grading.psm1') -Force

$checks = @()
$source = Join-Path $Workspace 'OrderLogging.fs'
# logging-expected.txt is the JIT output of the original inputs/OrderLogging.fs with LoggingDriver.fs.
$expected = (Get-Content -Raw (Join-Path $PSScriptRoot 'logging-expected.txt')).Replace("`r", '').Trim()

if (-not (Test-Path $source)) {
    $checks += New-Check 'OrderLogging.fs builds with the test driver' $false 'OrderLogging.fs missing'
    Write-Checks (Join-Path $OutDir 'grading.json') $checks
    return
}

$text = Get-Content -Raw $source
$classic = [regex]::Matches($text, '(sprintf|failwithf|printfn|eprintfn)\s+"[^"]*%[^s%"]') | ForEach-Object Value
$checks += New-Check 'No classic format string with a non-string hole remains' ($classic.Count -eq 0) ($classic -join '; ')

$proj = Join-Path $OutDir 'driver'
New-Item -ItemType Directory -Force -Path $proj | Out-Null
Copy-Item $source (Join-Path $proj 'OrderLogging.fs')
Copy-Item (Join-Path $PSScriptRoot 'LoggingDriver.fs') (Join-Path $proj 'Program.fs')
Set-Content (Join-Path $proj 'Driver.fsproj') @'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net10.0</TargetFramework>
    <PublishAot>true</PublishAot>
    <InvariantGlobalization>true</InvariantGlobalization>
  </PropertyGroup>
  <ItemGroup>
    <Compile Include="OrderLogging.fs" />
    <Compile Include="Program.fs" />
  </ItemGroup>
  <ItemGroup>
    <PackageReference Include="Microsoft.Extensions.Logging" Version="10.0.0" />
  </ItemGroup>
</Project>
'@

$r = Invoke-JitAndNative -Project (Join-Path $proj 'Driver.fsproj') -OutRoot (Join-Path $proj 'out') -SkipNative:$SkipNative
$checks += New-Check 'OrderLogging.fs builds with the test driver' $r.Built $(if (-not $r.Built) { Get-LastLines $r.BuildLog } else { '' })

$jit = if ($r.Jit) { ($r.Jit.Lines -join "`n").Replace("`r", '').Trim() } else { '' }
$checks += New-Check 'JIT output equals the original JIT output' ($r.Built -and $jit -eq $expected) $(if ($jit -ne $expected) { Get-LastLines $jit 8 } else { '' })

if ($SkipNative) {
    $checks += New-Check 'Native exe output equals the original JIT output' $null 'skipped: -SkipNative'
} elseif (-not $r.Built) {
    $checks += New-Check 'Native exe output equals the original JIT output' $false 'build failed'
} elseif (-not $r.Published) {
    $checks += New-Check 'Native exe output equals the original JIT output' $false (Get-LastLines $r.PublishLog)
} else {
    $native = ($r.Native.Lines -join "`n").Replace("`r", '').Trim()
    $checks += New-Check 'Native exe output equals the original JIT output' ($native -eq $expected) $(if ($native -ne $expected) { Get-LastLines $native 8 } else { '' })
}

Write-Checks (Join-Path $OutDir 'grading.json') $checks
