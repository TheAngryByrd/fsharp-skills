#Requires -Version 7.4
param(
    [Parameter(Mandatory)][string]$Workspace,
    [Parameter(Mandatory)][string]$OutDir,
    [switch]$SkipNative
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../../lib/Grading.psm1') -Force

$checks = @()
$project = Join-Path $Workspace 'Greeter/Greeter.fsproj'
if (-not (Test-Path $project)) {
    Write-Checks (Join-Path $OutDir 'grading.json') @(New-Check 'The project builds' $false 'Greeter/Greeter.fsproj missing')
    return
}

$versions = @(([xml](Get-Content -Raw $project)).SelectNodes('//PackageReference[@Include="System.CommandLine"]') |
    ForEach-Object { if ($_.Version) { $_.Version } else { $_.GetAttribute('Version') } })
$checks += New-Check 'Greeter.fsproj still references System.CommandLine 2.0.0' ($versions.Count -eq 1 -and $versions[0] -in @('2.0.0', '[2.0.0]')) "versions: $($versions -join ', ')"

$dir = Join-Path $OutDir 'build'
Copy-Workspace -Workspace $Workspace -Destination $dir
$projectDir = Join-Path $dir 'Greeter'
$bin = Join-Path $OutDir 'bin'
$build = Invoke-Capture dotnet @('build', 'Greeter.fsproj', '-c', 'Release', '-o', $bin) -WorkingDirectory $projectDir
$built = $build.ExitCode -eq 0
$checks += New-Check 'The project builds' $built $(if ($built) { '' } else { Get-LastLines $build.Text 8 })

$names = @(
    '`--name Bob --count 2` prints only two greetings and exits 0'
    '`--name Bob` prints only one greeting and exits 0'
    'A missing `--name` exits non-zero with an error and no greeting'
    '`--count 0` exits non-zero with an error and no greeting'
    '`--help` exits 0 and lists `--name` and `--count`'
    'An unknown option exits non-zero with a parse error'
)
if (-not $built) {
    $checks += $names | ForEach-Object { New-Check $_ $false 'the project does not build' }
    Write-Checks (Join-Path $OutDir 'grading.json') $checks
    return
}

$dll = Join-Path $bin 'Greeter.dll'
function Invoke-Greeter([string[]]$CliArgs) { Invoke-Capture dotnet (@($dll) + $CliArgs) -WorkingDirectory $projectDir }
function Get-Greetings($Run) { @($Run.Lines | Where-Object { $_ -match '^Hello, ' }) }
function Get-Output($Run) { @($Run.Lines | Where-Object { $_.Trim() -ne '' }) }
function Format-Run($Run) { "exit $($Run.ExitCode): $(Get-LastLines $Run.Text 4)" }

$two = Invoke-Greeter @('--name', 'Bob', '--count', '2')
$greetings = @(Get-Output $two)
$checks += New-Check $names[0] ($two.ExitCode -eq 0 -and $greetings.Count -eq 2 -and @($greetings | Where-Object { $_ -ne 'Hello, Bob!' }).Count -eq 0) (Format-Run $two)

$one = Invoke-Greeter @('--name', 'Bob')
$greetings = @(Get-Output $one)
$checks += New-Check $names[1] ($one.ExitCode -eq 0 -and $greetings.Count -eq 1 -and $greetings[0] -eq 'Hello, Bob!') (Format-Run $one)

$missing = Invoke-Greeter @('--count', '2')
$checks += New-Check $names[2] ($missing.ExitCode -ne 0 -and @(Get-Greetings $missing).Count -eq 0 -and $missing.Text.Trim().Length -gt 0) (Format-Run $missing)

$zero = Invoke-Greeter @('--name', 'Bob', '--count', '0')
$checks += New-Check $names[3] ($zero.ExitCode -ne 0 -and @(Get-Greetings $zero).Count -eq 0 -and $zero.Text.Trim().Length -gt 0) (Format-Run $zero)

$help = Invoke-Greeter @('--help')
$checks += New-Check $names[4] ($help.ExitCode -eq 0 -and $help.Text -match '--name' -and $help.Text -match '--count') (Format-Run $help)

$unknown = Invoke-Greeter @('--name', 'Bob', '--nmae', 'x')
$checks += New-Check $names[5] ($unknown.ExitCode -ne 0 -and @(Get-Greetings $unknown).Count -eq 0 -and $unknown.Text -match '--nmae') (Format-Run $unknown)

Write-Checks (Join-Path $OutDir 'grading.json') $checks
