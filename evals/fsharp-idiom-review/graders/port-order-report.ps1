#Requires -Version 7.4
param(
    [Parameter(Mandatory)][string]$Workspace,
    [Parameter(Mandatory)][string]$OutDir,
    [switch]$SkipNative
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../../lib/Grading.psm1') -Force

$checks = @()
$source = Join-Path $Workspace 'OrderReport.fsx'
if (-not (Test-Path $source)) {
    Write-Checks (Join-Path $OutDir 'grading.json') @(New-Check 'OrderReport.fsx and the probe compile together' $false 'OrderReport.fsx missing')
    return
}

$inputs = Join-Path (Split-Path $PSScriptRoot) 'inputs'
$unchanged = @('Domain.fsx', 'OrderReport.cs') | Where-Object {
    $ws = Join-Path $Workspace $_
    (Test-Path $ws) -and ((Get-Content -Raw $ws) -replace "`r`n", "`n") -eq ((Get-Content -Raw (Join-Path $inputs $_)) -replace "`r`n", "`n")
}
$checks += New-Check 'Domain.fsx and OrderReport.cs are unchanged' ($unchanged.Count -eq 2) "unchanged: $($unchanged -join ', ')"

$dir = Join-Path $OutDir 'probe'
Copy-Workspace -Workspace $Workspace -Destination $dir
Copy-Item (Join-Path $inputs 'Domain.fsx') $dir -Force
Copy-Item (Join-Path $PSScriptRoot 'Probe.fsx') $dir

$probe = Invoke-Capture dotnet @('fsi', 'Probe.fsx') -WorkingDirectory $dir
$results = @(ConvertFrom-ProbeOutput $probe.Lines)
$checks += New-Check 'OrderReport.fsx and the probe compile together' ($probe.ExitCode -eq 0 -and $results.Count -gt 0) $(if ($results.Count -eq 0) { Get-LastLines $probe.Text 6 } else { '' })
$checks += $results
$checks += Invoke-Rubric -Workspace $Workspace -EvalDir (Split-Path $PSScriptRoot) -TaskId 'port-order-report'

Write-Checks (Join-Path $OutDir 'grading.json') $checks
