#Requires -Version 7.4
param(
    [Parameter(Mandatory)][string]$Workspace,
    [Parameter(Mandatory)][string]$OutDir,
    [switch]$SkipNative
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../../lib/Grading.psm1') -Force

$checks = @()
$source = Join-Path $Workspace 'Invoice.fsx'
if (-not (Test-Path $source)) {
    Write-Checks (Join-Path $OutDir 'grading.json') @(New-Check 'Invoice.fsx and the probe compile together' $false 'Invoice.fsx missing')
    return
}
$dir = Join-Path $OutDir 'probe'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
Copy-Item $source $dir
Copy-Item (Join-Path $PSScriptRoot 'Probe.fsx') $dir

$probe = Invoke-Capture dotnet @('fsi', 'Probe.fsx') -WorkingDirectory $dir
$results = @($probe.Lines | Where-Object { $_ -match '^(PASS|FAIL) ' })
$checks += New-Check 'Invoice.fsx and the probe compile together' ($probe.ExitCode -eq 0 -and $results.Count -gt 0) $(if ($results.Count -eq 0) { Get-LastLines $probe.Text 6 } else { '' })
foreach ($line in $results) {
    $name = ($line -replace '^(PASS|FAIL) ', '') -replace ' \[.*\]$', ''
    $checks += New-Check $name ($line.StartsWith('PASS')) $(if ($line.StartsWith('FAIL')) { $line } else { '' })
}

Write-Checks (Join-Path $OutDir 'grading.json') $checks
