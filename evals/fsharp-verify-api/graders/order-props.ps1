#Requires -Version 7.4
param(
    [Parameter(Mandatory)][string]$Workspace,
    [Parameter(Mandatory)][string]$OutDir,
    [switch]$SkipNative
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../../lib/Grading.psm1') -Force

$checks = @()
$source = Join-Path $Workspace 'OrderProps.fsx'
if (-not (Test-Path $source)) {
    Write-Checks (Join-Path $OutDir 'grading.json') @(New-Check 'OrderProps.fsx and the probe compile together' $false 'OrderProps.fsx missing')
    return
}

$references = @(Get-Content $source | Where-Object { $_ -match '^\s*#r\s+"nuget:\s*FsCheck\b' })
$checks += New-Check 'OrderProps.fsx still references FsCheck 3.4.0' ($references.Count -eq 1 -and $references[0] -match '"nuget:\s*FsCheck\s*,\s*3\.4\.0\s*"') ($references -join '; ')

$dir = Join-Path $OutDir 'probe'
Copy-Workspace -Workspace $Workspace -Destination $dir
Copy-Item (Join-Path $PSScriptRoot 'PropsProbe.fsx') $dir

$probe = Invoke-Capture dotnet @('fsi', 'PropsProbe.fsx') -WorkingDirectory $dir
$results = @($probe.Lines | Where-Object { $_ -match '^(PASS|FAIL) ' })
$checks += New-Check 'OrderProps.fsx and the probe compile together' ($results.Count -gt 0) $(if ($results.Count -eq 0) { Get-LastLines $probe.Text 6 } else { '' })
$names = @(
    'sampleLines 300 returns 300 lines'
    'Every sampled line meets the constraints'
    'Samples use every SKU and vary quantity and price'
    'orderArb gives non-empty orders of valid lines'
    'checkTotal passes the correct total in exactly 250 valid orders'
    'checkTotal throws for a total that ignores quantity'
)
foreach ($name in $names) {
    $line = $results | Where-Object { ($_ -replace '^(PASS|FAIL) ', '') -replace ' \[.*\]$', '' -eq $name } | Select-Object -First 1
    if (-not $line) {
        $checks += New-Check $name $false 'the probe did not run this check'
    } else {
        $checks += New-Check $name ($line.StartsWith('PASS')) $(if ($line.StartsWith('FAIL')) { $line } else { '' })
    }
}

Write-Checks (Join-Path $OutDir 'grading.json') $checks
