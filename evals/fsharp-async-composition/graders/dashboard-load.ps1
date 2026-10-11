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
$probeText = Get-ProbeScript -ProbePath (Join-Path $PSScriptRoot 'DashboardProbe.fsx') -SourcePath $source -Module 'Dashboard'
Set-Content -Path (Join-Path $dir 'DashboardProbe.fsx') -Value $probeText
Copy-Item (Join-Path $PSScriptRoot 'global.json') $dir

$probe = Invoke-Capture dotnet @('fsi', 'DashboardProbe.fsx') -WorkingDirectory $dir
$results = @(ConvertFrom-ProbeOutput $probe.Lines)
$checks += New-Check 'Dashboard.fsx and the probe compile together' ($probe.ExitCode -eq 0 -and $results.Count -gt 0) $(if ($results.Count -eq 0) { Get-LastLines $probe.Text 8 } else { '' })
$checks += $results

Write-Checks (Join-Path $OutDir 'grading.json') $checks
