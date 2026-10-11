#Requires -Version 7.4
param(
    [Parameter(Mandatory)][string]$Workspace,
    [Parameter(Mandatory)][string]$OutDir,
    [switch]$SkipNative
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../../lib/Grading.psm1') -Force

$checks = @()
$source = Join-Path $Workspace 'Reports.fsx'
if (-not (Test-Path $source)) {
    Write-Checks (Join-Path $OutDir 'grading.json') @(New-Check 'Reports.fsx and the probe compile together' $false 'Reports.fsx missing')
    return
}
$dir = Join-Path $OutDir 'probe'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
Copy-Workspace $Workspace $dir
$probeText = Get-Content -Raw (Join-Path $PSScriptRoot 'ReportsProbe.fsx')
# A script that declares `module Reports =` loads as the nested module Reports.Reports.
if ((Get-Content -Raw $source) -match '(?m)^module\s+Reports\s*=') {
    $probeText = $probeText -replace '(?m)^open Reports\r?$', "open Reports`nopen Reports.Reports"
}
Set-Content -Path (Join-Path $dir 'ReportsProbe.fsx') -Value $probeText
Copy-Item (Join-Path $PSScriptRoot 'global.json') $dir

$probe = Invoke-Capture dotnet @('fsi', 'ReportsProbe.fsx') -WorkingDirectory $dir
$results = @($probe.Lines | Where-Object { $_ -match '^(PASS|FAIL) ' })
$checks += New-Check 'Reports.fsx and the probe compile together' ($results.Count -gt 0) $(if ($results.Count -eq 0) { Get-LastLines $probe.Text 8 } else { '' })
foreach ($line in $results) {
    $name = ($line -replace '^(PASS|FAIL) ', '') -replace ' \[.*\]$', ''
    $checks += New-Check $name ($line.StartsWith('PASS')) $(if ($line.StartsWith('FAIL')) { $line } else { '' })
}
$last = 'a failed served audit does not stop the process'
if ($results.Count -gt 0 -and -not ($checks | Where-Object { $_.text -eq $last })) {
    $checks += New-Check $last $false "The probe process stopped with exit code $($probe.ExitCode).`n$(Get-LastLines $probe.Text 4)"
}

Write-Checks (Join-Path $OutDir 'grading.json') $checks
