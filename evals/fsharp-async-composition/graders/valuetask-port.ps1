#Requires -Version 7.4
param(
    [Parameter(Mandatory)][string]$Workspace,
    [Parameter(Mandatory)][string]$OutDir,
    [switch]$SkipNative
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../../lib/Grading.psm1') -Force

$checks = @()
$source = Join-Path $Workspace 'Frames.fsx'
if (-not (Test-Path $source)) {
    Write-Checks (Join-Path $OutDir 'grading.json') @(New-Check 'Frames.fsx and the probe compile together' $false 'Frames.fsx missing')
    return
}
$dir = Join-Path $OutDir 'probe'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
Copy-Workspace $Workspace $dir
$probeText = Get-Content -Raw (Join-Path $PSScriptRoot 'FramesProbe.fsx')
# A script that declares `module Frames =` loads as the nested module Frames.Frames.
if ((Get-Content -Raw $source) -match '(?m)^module\s+Frames\s*=') {
    $probeText = $probeText -replace '(?m)^open Frames\r?$', "open Frames`nopen Frames.Frames"
}
Set-Content -Path (Join-Path $dir 'FramesProbe.fsx') -Value $probeText
Copy-Item (Join-Path $PSScriptRoot 'global.json') $dir

$probe = Invoke-Capture dotnet @('fsi', 'FramesProbe.fsx') -WorkingDirectory $dir
$results = @($probe.Lines | Where-Object { $_ -match '^(PASS|FAIL) ' })
$checks += New-Check 'Frames.fsx and the probe compile together' ($probe.ExitCode -eq 0 -and $results.Count -gt 0) $(if ($results.Count -eq 0) { Get-LastLines $probe.Text 8 } else { '' })
foreach ($line in $results) {
    $name = ($line -replace '^(PASS|FAIL) ', '') -replace ' \[.*\]$', ''
    $checks += New-Check $name ($line.StartsWith('PASS')) $(if ($line.StartsWith('FAIL')) { $line } else { '' })
}

Write-Checks (Join-Path $OutDir 'grading.json') $checks
