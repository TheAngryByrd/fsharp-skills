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
Copy-Workspace -Workspace $Workspace -Destination $dir
Copy-Item (Join-Path $PSScriptRoot 'Probe.fsx') $dir

$probe = Invoke-Capture dotnet @('fsi', 'Probe.fsx') -WorkingDirectory $dir
$results = @(ConvertFrom-ProbeOutput $probe.Lines)
$checks += New-Check 'Invoice.fsx and the probe compile together' ($probe.ExitCode -eq 0 -and $results.Count -gt 0) $(if ($results.Count -eq 0) { Get-LastLines $probe.Text 6 } else { '' })
$checks += $results

Write-Checks (Join-Path $OutDir 'grading.json') $checks
