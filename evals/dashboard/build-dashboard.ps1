#!/usr/bin/env pwsh
#Requires -Version 7.4
<#
.SYNOPSIS
Builds the static eval dashboard from the committed result sets.

.EXAMPLE
pwsh ./evals/dashboard/build-dashboard.ps1 -OutDir $env:TEMP/eval-dashboard
#>
param(
    [Parameter(Mandatory)][string]$OutDir,
    [string]$ResultsRoot = (Join-Path $PSScriptRoot '../results')
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../lib/Results.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Dashboard.psm1') -Force

$evals = Split-Path $PSScriptRoot
$repo = Split-Path $evals

$commit = $env:GITHUB_SHA
if (-not $commit -and (Get-Command git -CommandType Application -ErrorAction SilentlyContinue)) {
    $head = git -C $repo rev-parse HEAD 2>$null
    if ($LASTEXITCODE -eq 0) { $commit = "$head".Trim() }
}

$repoUrl = 'https://github.com/TheAngryByrd/fsharp-skills'
if ($env:GITHUB_SERVER_URL -and $env:GITHUB_REPOSITORY) { $repoUrl = "$($env:GITHUB_SERVER_URL.TrimEnd('/'))/$($env:GITHUB_REPOSITORY)" }

$catalog = @(Get-SkillCatalog -EvalsRoot $evals -SkillsRoot (Join-Path $repo 'skills'))
$sets = @()
if (Test-Path $ResultsRoot) {
    $sets = @(Get-ChildItem -Path $ResultsRoot -Filter '*.json' -Recurse -File | Sort-Object FullName | ForEach-Object { Read-ResultSet $_.FullName })
}
$data = New-DashboardData -Catalog $catalog -ResultSets $sets -Commit "$commit" -RepoUrl $repoUrl -GeneratedAt (Format-IsoUtc ([DateTime]::UtcNow))

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$json = $data | ConvertTo-Json -Depth 12 -EscapeHandling Default
[IO.File]::WriteAllText((Join-Path $OutDir 'data.js'), "window.EVAL_DASHBOARD = $json;`n", [Text.UTF8Encoding]::new($false))
foreach ($asset in 'index.html', 'dashboard.js', 'dashboard.css') { Copy-Item (Join-Path $PSScriptRoot $asset) $OutDir -Force }
(Resolve-Path $OutDir).Path
