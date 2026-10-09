#Requires -Version 7.4
param(
    [Parameter(Mandatory)][string]$Workspace,
    [Parameter(Mandatory)][string]$OutDir,
    [switch]$SkipNative
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../../lib/Grading.psm1') -Force

$checks = @()
$source = Join-Path $Workspace 'Registration.fsx'
if (-not (Test-Path $source)) {
    Write-Checks (Join-Path $OutDir 'grading.json') @(New-Check 'Registration.fsx loads under dotnet fsi' $false 'Registration.fsx missing')
    return
}
$text = Get-Content -Raw $source
$dir = Join-Path $OutDir 'probe'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
Copy-Item $source $dir
Copy-Item (Join-Path $PSScriptRoot '*.fsx') $dir

$probe = Invoke-Capture dotnet @('fsi', '--nowarn:3535', 'Probe.fsx') -WorkingDirectory $dir
$results = @($probe.Lines | Where-Object { $_ -match '^(PASS|FAIL) ' })
$checks += New-Check 'Registration.fsx and the probe compile together' ($probe.ExitCode -eq 0 -and $results.Count -gt 0) $(if ($results.Count -eq 0) { Get-LastLines $probe.Text 6 } else { '' })
foreach ($line in $results) {
    $name = ($line -replace '^(PASS|FAIL) ', '') -replace ' \[.*\]$', ''
    $checks += New-Check $name ($line.StartsWith('PASS')) $(if ($line.StartsWith('FAIL')) { $line } else { '' })
}

foreach ($break in @(
        @{ File = 'BreakLiteral.fsx'; Text = 'A Registration record cannot be built from raw strings and ints' },
        @{ File = 'BreakUpdate.fsx'; Text = 'A copy-and-update expression cannot set Age to a raw int' })) {
    $r = Invoke-Capture dotnet @('fsi', '--nowarn:3535', $break.File) -WorkingDirectory $dir
    $own = @($r.Lines | Select-String -Pattern ([regex]::Escape($break.File) + '\(\d+,\d+\).*error FS\d+'))
    $checks += New-Check $break.Text ($r.ExitCode -ne 0 -and $own.Count -gt 0) $(if ($own.Count -eq 0) { Get-LastLines $r.Text 3 } else { '' })
}

$checks += New-Check 'Domain value types use a private representation' ($text -match '=\s*private\b|\bprivate\s+new\b') ''

Write-Checks (Join-Path $OutDir 'grading.json') $checks
