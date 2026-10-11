#Requires -Version 7.4
param(
    [Parameter(Mandatory)][string]$Workspace,
    [Parameter(Mandatory)][string]$OutDir,
    [switch]$SkipNative
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../../lib/Grading.psm1') -Force

$checks = @()
$source = Join-Path $Workspace 'Dashboard.fsx'
if (-not (Test-Path $source)) {
    Write-Checks (Join-Path $OutDir 'grading.json') @(New-Check 'Dashboard.fsx and the probe compile together' $false 'Dashboard.fsx missing')
    return
}
$dir = Join-Path $OutDir 'probe'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
Copy-Workspace $Workspace $dir
$probeText = Get-Content -Raw (Join-Path $PSScriptRoot 'DashboardProbe.fsx')
# A script that declares `module Dashboard =` loads as the nested module Dashboard.Dashboard.
if ((Get-Content -Raw $source) -match '(?m)^module\s+Dashboard\s*=') {
    $probeText = $probeText -replace '(?m)^open Dashboard\r?$', "open Dashboard`nopen Dashboard.Dashboard"
}
Set-Content -Path (Join-Path $dir 'DashboardProbe.fsx') -Value $probeText
Copy-Item (Join-Path $PSScriptRoot 'global.json') $dir

$probe = Invoke-Capture dotnet @('fsi', 'DashboardProbe.fsx') -WorkingDirectory $dir
$results = @($probe.Lines | Where-Object { $_ -match '^(PASS|FAIL) ' })
$checks += New-Check 'Dashboard.fsx and the probe compile together' ($probe.ExitCode -eq 0 -and $results.Count -gt 0) $(if ($results.Count -eq 0) { Get-LastLines $probe.Text 8 } else { '' })
foreach ($line in $results) {
    $name = ($line -replace '^(PASS|FAIL) ', '') -replace ' \[.*\]$', ''
    $checks += New-Check $name ($line.StartsWith('PASS')) $(if ($line.StartsWith('FAIL')) { $line } else { '' })
}

Write-Checks (Join-Path $OutDir 'grading.json') $checks
