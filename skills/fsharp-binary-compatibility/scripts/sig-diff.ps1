#Requires -Version 7.4
<#
.SYNOPSIS
Compares the F# signature (compiler --sig output) of a project with a baseline version of the same project.

.DESCRIPTION
Builds the baseline and the current project with --sig added to the project's own OtherFlags, then prints a diff of the two signatures.
Exit codes: 0 when the signatures are equal, 1 when they differ, 2 when a build or the git checkout fails.
The script builds the current project in place, in Release. It checks out -BaselineRef in a temporary git worktree next to the repository folder, so files above the repository apply to both builds, and removes it after. For a multi-target project, pass -Framework.

.EXAMPLE
pwsh ./sig-diff.ps1 -Project src/Pricing/Pricing.fsproj -BaselineRef v1.0.0

.EXAMPLE
pwsh ./sig-diff.ps1 -Project new/Pricing/Pricing.fsproj -BaselineProject old/Pricing/Pricing.fsproj
#>
[CmdletBinding(DefaultParameterSetName = 'Ref')]
param(
    [Parameter(Mandatory)][string]$Project,
    [Parameter(ParameterSetName = 'Ref')][string]$BaselineRef = 'HEAD',
    [Parameter(Mandatory, ParameterSetName = 'Project')][string]$BaselineProject,
    [string]$Configuration = 'Release',
    [string]$Framework = '',
    [string]$OutDir = ''
)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
trap {
    Write-Output "sig-diff.ps1 failed: $_"
    exit 2
}

$targets = Join-Path $PSScriptRoot 'SigDiff.targets'
$current = (Resolve-Path -LiteralPath $Project).Path
if (-not $OutDir) { $OutDir = Join-Path ([IO.Path]::GetTempPath()) "sig-diff-$([guid]::NewGuid().ToString('N').Substring(0, 8))" }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$OutDir = (Resolve-Path -LiteralPath $OutDir).Path

function Write-Signature([string]$ProjectPath, [string]$SigFile) {
    if (-not $Framework) {
        Push-Location (Split-Path $ProjectPath)
        try { $probe = @(dotnet msbuild $ProjectPath -getProperty:TargetFrameworks 2>&1 | ForEach-Object { "$_" }); $probeExit = $LASTEXITCODE } finally { Pop-Location }
        if ($probeExit -ne 0) { return @("MSBuild could not evaluate $ProjectPath (exit $probeExit):") + $probe }
        $frameworks = ($probe -join ' ').Trim()
        if ($frameworks) { return @("$ProjectPath has several target frameworks ($frameworks). Run again with -Framework <tfm>.") }
    }
    $arguments = @('build', $ProjectPath, '-c', $Configuration, '--no-incremental', '-nologo',
        "-p:CustomAfterMicrosoftCommonTargets=$targets", "-p:SigDiffProject=$ProjectPath", "-p:SigDiffOutput=$SigFile")
    if ($Framework) { $arguments += @('-f', $Framework) }
    # dotnet selects its SDK from global.json above the working directory.
    Push-Location (Split-Path $ProjectPath)
    try { $output = @(dotnet @arguments 2>&1 | ForEach-Object { "$_" }); $exit = $LASTEXITCODE } finally { Pop-Location }
    if ($exit -ne 0 -or -not (Test-Path $SigFile)) {
        return @("Build failed for $ProjectPath (exit $exit):") + @($output | Where-Object { $_ -match ': error ' } | Select-Object -Unique -First 20)
    }
    $lines = @(Get-Content $SigFile | ForEach-Object { $_.TrimEnd() })
    $kept = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $lines) {
        if ($line -eq '' -and ($kept.Count -eq 0 -or $kept[$kept.Count - 1] -eq '')) { continue }
        $kept.Add($line)
    }
    Set-Content -Path $SigFile -Value $kept -Encoding utf8NoBOM
    @()
}

$before = Join-Path $OutDir 'baseline.fsi'
$after = Join-Path $OutDir 'current.fsi'
$worktree = $null
try {
    if ($PSCmdlet.ParameterSetName -eq 'Project') {
        $baseline = (Resolve-Path -LiteralPath $BaselineProject).Path
    } else {
        $root = (git -C (Split-Path $current) rev-parse --show-toplevel 2>$null)
        if ($LASTEXITCODE -ne 0 -or -not $root) { Write-Output "$current is not in a git repository. Use -BaselineProject."; exit 2 }
        $root = (Resolve-Path -LiteralPath $root).Path
        # The worktree is a sibling of the repository, so MSBuild, NuGet, and global.json files above the repository apply to both builds.
        $worktree = Join-Path (Split-Path $root) ".sig-diff-$(Split-Path $root -Leaf)-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
        $add = @(git -C $root worktree add --detach $worktree $BaselineRef 2>&1 | ForEach-Object { "$_" })
        if ($LASTEXITCODE -ne 0) { Write-Output "git worktree add failed for '$BaselineRef':"; $add; $worktree = $null; exit 2 }
        $baseline = Join-Path $worktree ([IO.Path]::GetRelativePath($root, $current))
        if (-not (Test-Path $baseline)) { Write-Output "$BaselineRef has no $([IO.Path]::GetRelativePath($root, $current))."; exit 2 }
    }
    foreach ($side in @(@($baseline, $before), @($current, $after))) {
        $errors = @(Write-Signature $side[0] $side[1])
        if ($errors.Count -gt 0) { $errors; exit 2 }
    }
} finally {
    if ($worktree) {
        git -C $root worktree remove --force $worktree 2>&1 | Out-Null
        if (Test-Path $worktree) { Remove-Item -Recurse -Force -LiteralPath $worktree -ErrorAction SilentlyContinue }
    }
}

$same = (Get-Content -Raw $before) -ceq (Get-Content -Raw $after)
if ($same) {
    Write-Output "No F# signature change. Signatures: $before, $after"
    exit 0
}
Write-Output "The F# signature changed. Signatures: $before, $after"
if (Get-Command git -ErrorAction SilentlyContinue) {
    git -c core.autocrlf=false diff --no-index --no-color --no-ext-diff --no-textconv -- $before $after
} else {
    Write-Output '--- baseline.fsi'
    Get-Content $before
    Write-Output '--- current.fsi'
    Get-Content $after
}
exit 1
