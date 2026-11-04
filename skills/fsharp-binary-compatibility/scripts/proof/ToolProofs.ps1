#Requires -Version 7.4
param(
    [Parameter(Mandatory)][string]$Artifacts,
    [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[string]]$Failures
)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$scripts = Split-Path $PSScriptRoot
$cases = Join-Path $PSScriptRoot 'cases'
$feed = Join-Path $Artifacts 'feed'
$packageId = "BinaryCompatibilityProof$PID"
New-Item -ItemType Directory -Force -Path $feed | Out-Null

function Invoke-Dotnet([string[]]$Arguments, [string]$WorkingDirectory = $scripts) {
    Push-Location $WorkingDirectory
    try {
        $output = @(dotnet @Arguments 2>&1 | ForEach-Object { "$_" })
        [pscustomobject]@{ ExitCode = $LASTEXITCODE; Text = ($output -join "`n") }
    } finally { Pop-Location }
}

function Assert-Proof([string]$Name, [bool]$Condition, [string]$Detail) {
    Write-Output ('tool    {0,-72} {1}' -f $Name, $(if ($Condition) { 'ok' } else { 'MISMATCH' }))
    if (-not $Condition) { $Failures.Add("$Name`n$Detail") }
}

# Copies under the temp folder do not read a nuget.config with package source mapping from the user's repository.
$packages = Join-Path $Artifacts 'pkg'
New-Item -ItemType Directory -Force -Path $packages | Out-Null
foreach ($name in 'Package', 'CoreConsumer', 'Analyzers') { Copy-Item (Join-Path $PSScriptRoot $name) (Join-Path $packages $name) -Recurse }
foreach ($name in 'global.json', 'Directory.Build.targets', 'Directory.Packages.props') { Copy-Item (Join-Path $scripts $name) $packages }
@"
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <clear />
    <add key="nuget.org" value="https://api.nuget.org/v3/index.json" />
    <add key="proof" value="$feed" />
  </packageSources>
  <packageSourceMapping>
    <clear />
  </packageSourceMapping>
</configuration>
"@ | Set-Content (Join-Path $packages 'nuget.config')
$previousCache = $env:NUGET_PACKAGES
$env:NUGET_PACKAGES = Join-Path $Artifacts 'packages'
try {
    $package = Join-Path $packages 'Package/Package.fsproj'
    function Invoke-Pack([string]$Source, [string]$Version, [string[]]$Extra = @()) {
        Invoke-Dotnet (@('pack', $package, '-c', 'Release', '-nologo', '-o', $feed, "-p:Version=$Version",
                "-p:CaseFile=$Source", "-p:ProofPackageId=$packageId", "-p:ProofFeed=$feed") + $Extra) $packages
    }
    $parameter = Join-Path $cases 'module-parameter'
    $v1 = Invoke-Pack (Join-Path $parameter 'v1.fs') '1.0.0'
    Assert-Proof 'package validation: pack 1.0.0 baseline' ($v1.ExitCode -eq 0) $v1.Text
    $break = Invoke-Pack (Join-Path $parameter 'break.fs') '1.1.0' @('-p:PackageValidationBaselineVersion=1.0.0')
    Assert-Proof 'package validation: new curried parameter fails dotnet pack with CP0002' ($break.ExitCode -ne 0 -and $break.Text -match 'error CP0002') $break.Text
    $safe = Invoke-Pack (Join-Path $parameter 'safe.fs') '1.1.1' @('-p:PackageValidationBaselineVersion=1.0.0')
    Assert-Proof 'package validation: new function with old wrapper passes dotnet pack' ($safe.ExitCode -eq 0) $safe.Text
    $suppress = Join-Path $packages 'suppress'
    New-Item -ItemType Directory -Force -Path $suppress | Out-Null
    Copy-Item $package $suppress
    $suppressProject = Join-Path $suppress 'Package.fsproj'
    $suppressArgs = @('pack', $suppressProject, '-c', 'Release', '-nologo', '-o', (Join-Path $Artifacts 'suppress-out'), '-p:Version=1.1.2',
        "-p:CaseFile=$(Join-Path $parameter 'break.fs')", "-p:ProofPackageId=$packageId", "-p:ProofFeed=$feed", '-p:PackageValidationBaselineVersion=1.0.0')
    $generate = Invoke-Dotnet ($suppressArgs + '-p:ApiCompatGenerateSuppressionFile=true') $suppress
    $suppressionFile = Join-Path $suppress 'CompatibilitySuppressions.xml'
    $written = (Test-Path $suppressionFile) -and (Get-Content -Raw $suppressionFile) -match '<DiagnosticId>CP0002</DiagnosticId>'
    Assert-Proof 'package validation: ApiCompatGenerateSuppressionFile writes CompatibilitySuppressions.xml next to the project' ($generate.ExitCode -eq 0 -and $written) $generate.Text
    $suppressed = Invoke-Dotnet $suppressArgs $suppress
    Assert-Proof 'package validation: the next pack reads CompatibilitySuppressions.xml and passes' ($suppressed.ExitCode -eq 0) $suppressed.Text

    $union = Join-Path $cases 'union-insert'
    $u1 = Invoke-Pack (Join-Path $union 'v1.fs') '2.0.0'
    $u2 = Invoke-Pack (Join-Path $union 'break.fs') '2.1.0' @('-p:PackageValidationBaselineVersion=2.0.0')
    Assert-Proof 'package validation: union case inserted in the middle passes dotnet pack' ($u1.ExitCode -eq 0 -and $u2.ExitCode -eq 0) "$($u1.Text)`n$($u2.Text)"

    $nupkg = Join-Path $feed "$packageId.1.0.0.nupkg"
    $nuspec = if (-not (Test-Path $nupkg)) { '' } else {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [IO.Compression.ZipFile]::OpenRead($nupkg)
        try {
            $entry = $zip.Entries | Where-Object { $_.FullName -like '*.nuspec' } | Select-Object -First 1
            $reader = [IO.StreamReader]::new($entry.Open())
            try { $reader.ReadToEnd() } finally { $reader.Dispose() }
        } finally { $zip.Dispose() }
    }
    $coreVersion = if ($nuspec -match 'id="FSharp.Core" version="([^"]+)"') { $Matches[1] } else { '' }
    Assert-Proof "FSharp.Core: default package depends on the SDK FSharp.Core ($coreVersion)" ($coreVersion -and [version]($coreVersion -replace '-.*$', '') -ge [version]'10.0') $nuspec

    $coreConsumer = Join-Path $packages 'CoreConsumer/CoreConsumer.fsproj'
    $high = Invoke-Dotnet @('restore', $coreConsumer, "-p:ProofPackageId=$packageId", "-p:ProofFeed=$feed") $packages
    Assert-Proof 'FSharp.Core: consumer pinned to 8.0.400 gets NU1605 from the default package' ($high.Text -match 'NU1605') $high.Text
    $lowId = "$packageId.Low"
    $low = Invoke-Dotnet @('pack', $package, '-c', 'Release', '-nologo', '-o', $feed, '-p:Version=1.0.0',
        "-p:CaseFile=$(Join-Path $parameter 'v1.fs')", "-p:ProofPackageId=$lowId", "-p:ProofFeed=$feed", '-p:ProofFSharpCore=8.0.400') $packages
    $lowRestore = Invoke-Dotnet @('restore', $coreConsumer, "-p:ProofPackageId=$lowId", "-p:ProofFeed=$feed", '--force') $packages
    $highBuild = Invoke-Dotnet @('build', $coreConsumer, '-c', 'Release', '-nologo', '-o', (Join-Path $Artifacts 'core-high'), "-p:ProofPackageId=$packageId", "-p:ProofFeed=$feed") $packages
    $coreDll = Join-Path $Artifacts 'core-high/FSharp.Core.dll'
    $loaded = if (Test-Path $coreDll) { [Reflection.AssemblyName]::GetAssemblyName($coreDll).Version.ToString() } else { 'missing' }
    $highRun = Invoke-Dotnet @((Join-Path $Artifacts 'core-high/CoreConsumer.dll')) $packages
    Assert-Proof "FSharp.Core: that consumer builds, copies FSharp.Core $loaded, and fails at startup with FileNotFoundException for FSharp.Core 10" ($highBuild.ExitCode -eq 0 -and $loaded -eq '8.0.0.0' -and $highRun.ExitCode -ne 0 -and $highRun.Text -match "FileNotFoundException: Could not load file or assembly 'FSharp.Core, Version=10\.") "$($highBuild.Text)`n$($highRun.Text)"
    Assert-Proof 'FSharp.Core: package with an explicit FSharp.Core 8.0.400 gives no NU1605' ($low.ExitCode -eq 0 -and $lowRestore.ExitCode -eq 0 -and $lowRestore.Text -notmatch 'NU1605') "$($low.Text)`n$($lowRestore.Text)"

    $fsharpAnalyzer = Invoke-Dotnet @('build', (Join-Path $packages 'Analyzers/FSharpLib/FSharpLib.fsproj'), '-c', 'Release', '--no-incremental', '-nologo') $packages
    Assert-Proof 'PublicApiAnalyzers: F# library with an empty PublicAPI.Shipped.txt builds with no RS0016' ($fsharpAnalyzer.ExitCode -eq 0 -and $fsharpAnalyzer.Text -notmatch 'RS0016') $fsharpAnalyzer.Text
    $csharpAnalyzer = Invoke-Dotnet @('build', (Join-Path $packages 'Analyzers/CSharpLib/CSharpLib.csproj'), '-c', 'Release', '--no-incremental', '-nologo') $packages
    Assert-Proof 'PublicApiAnalyzers: C# control library fails with RS0016' ($csharpAnalyzer.ExitCode -ne 0 -and $csharpAnalyzer.Text -match 'RS0016') $csharpAnalyzer.Text
} finally {
    $env:NUGET_PACKAGES = $previousCache
}

$sigDiff = Join-Path $scripts 'sig-diff.ps1'
$repo = Join-Path $Artifacts 'sig-repo'
New-Item -ItemType Directory -Force -Path (Join-Path $repo 'src/Lib') | Out-Null
foreach ($name in 'global.json', 'Directory.Build.targets', 'Directory.Packages.props') { Copy-Item (Join-Path $scripts $name) $repo }
@'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <OtherFlags>$(OtherFlags) --warnon:1182 --warnaserror+:1182</OtherFlags>
  </PropertyGroup>
  <ItemGroup>
    <Compile Include="Lib.fs" />
  </ItemGroup>
</Project>
'@ | Set-Content (Join-Path $repo 'src/Lib/Lib.fsproj')
Copy-Item (Join-Path $union 'v1.fs') (Join-Path $repo 'src/Lib/Lib.fs')
Push-Location $repo
try {
    git init -q 2>&1 | Out-Null
    git add -A 2>&1 | Out-Null
    $commit = @(git -c user.name=proof -c user.email=proof@example.invalid -c commit.gpgsign=false -c core.hooksPath= commit -q -m v1 2>&1)
    if ($LASTEXITCODE -ne 0) { $Failures.Add("git commit in the sig-diff proof repository failed:`n$($commit -join "`n")") }
} finally { Pop-Location }
$project = Join-Path $repo 'src/Lib/Lib.fsproj'

$same = @(& $sigDiff -Project $project -BaselineRef HEAD -OutDir (Join-Path $Artifacts 'sig-same'))
$sameExit = $LASTEXITCODE
Assert-Proof 'sig-diff.ps1: no change exits 0' ($sameExit -eq 0 -and ($same -join "`n") -match 'No F# signature change') ($same -join "`n")

Copy-Item (Join-Path $union 'break.fs') (Join-Path $repo 'src/Lib/Lib.fs') -Force
$changed = @(& $sigDiff -Project $project -BaselineRef HEAD -OutDir (Join-Path $Artifacts 'sig-changed'))
$changedExit = $LASTEXITCODE
$text = $changed -join "`n"
Assert-Proof 'sig-diff.ps1: union case inserted in the middle exits 1 and shows the case' ($changedExit -eq 1 -and $text -match '(?m)^\+\s+\| Refunded') $text
$worktrees = @(git -C $repo worktree list 2>&1)
Assert-Proof 'sig-diff.ps1: the baseline worktree is removed' ($worktrees.Count -eq 1) ($worktrees -join "`n")
$curried = Join-Path $Artifacts 'sig-curried'
New-Item -ItemType Directory -Force -Path (Join-Path $curried 'before'), (Join-Path $curried 'after') | Out-Null
foreach ($side in 'before', 'after') {
    Copy-Item (Join-Path $repo 'src/Lib/Lib.fsproj') (Join-Path $curried "$side/Lib.fsproj")
    Copy-Item (Join-Path $cases "curried-tupled/$(if ($side -eq 'before') { 'v1' } else { 'break' }).fs") (Join-Path $curried "$side/Lib.fs")
}
foreach ($name in 'global.json', 'Directory.Build.targets', 'Directory.Packages.props') { Copy-Item (Join-Path $scripts $name) $curried }
$tupled = @(& $sigDiff -Project (Join-Path $curried 'after/Lib.fsproj') -BaselineProject (Join-Path $curried 'before/Lib.fsproj') -OutDir (Join-Path $Artifacts 'sig-tupled'))
$tupledExit = $LASTEXITCODE
$text = $tupled -join "`n"
Assert-Proof 'sig-diff.ps1: -BaselineProject shows a curried to tupled change' ($tupledExit -eq 1 -and $text -match 'quantity: int \* unitPrice: decimal') $text

$missing = @(& $sigDiff -Project (Join-Path $Artifacts 'no-such/Lib.fsproj') -BaselineProject $project -OutDir (Join-Path $Artifacts 'sig-missing'))
$missingExit = $LASTEXITCODE
Assert-Proof 'sig-diff.ps1: a missing project path exits 2' ($missingExit -eq 2 -and ($missing -join "`n") -match 'sig-diff.ps1 failed') ($missing -join "`n")

$parent = Join-Path $Artifacts 'sig-parent'
New-Item -ItemType Directory -Force -Path (Join-Path $parent 'repo/src/Lib') | Out-Null
foreach ($name in 'global.json', 'Directory.Build.targets', 'Directory.Packages.props') { Copy-Item (Join-Path $scripts $name) $parent }
@'
<Project>
  <PropertyGroup>
    <DefineConstants>$(DefineConstants);PARENT_PROPS</DefineConstants>
  </PropertyGroup>
</Project>
'@ | Set-Content (Join-Path $parent 'Directory.Build.props')
Copy-Item (Join-Path $repo 'src/Lib/Lib.fsproj') (Join-Path $parent 'repo/src/Lib/Lib.fsproj')
Set-Content (Join-Path $parent 'repo/src/Lib/Lib.fs') "module Lib`n`nlet total (amount: decimal) : decimal = amount`n#if PARENT_PROPS`nlet parentOnly = 1`n#endif`n"
Push-Location (Join-Path $parent 'repo')
try {
    git init -q 2>&1 | Out-Null
    git add -A 2>&1 | Out-Null
    $commit = @(git -c user.name=proof -c user.email=proof@example.invalid -c commit.gpgsign=false -c core.hooksPath= commit -q -m v1 2>&1)
    if ($LASTEXITCODE -ne 0) { $Failures.Add("git commit in the sig-diff parent proof repository failed:`n$($commit -join "`n")") }
} finally { Pop-Location }
$parentOut = @(& $sigDiff -Project (Join-Path $parent 'repo/src/Lib/Lib.fsproj') -BaselineRef HEAD -OutDir (Join-Path $Artifacts 'sig-parent-out'))
$parentExit = $LASTEXITCODE
$siblings = @(Get-ChildItem $parent -Directory -Filter '.sig-diff-*')
Assert-Proof 'sig-diff.ps1: -BaselineRef applies MSBuild files above the repository to both builds' ($parentExit -eq 0 -and $siblings.Count -eq 0) "exit $parentExit, worktrees left: $($siblings.Count)`n$($parentOut -join "`n")"

$multi = Join-Path $Artifacts 'sig-multi'
New-Item -ItemType Directory -Force -Path $multi | Out-Null
foreach ($name in 'global.json', 'Directory.Build.targets', 'Directory.Packages.props') { Copy-Item (Join-Path $scripts $name) $multi }
Copy-Item (Join-Path $union 'v1.fs') (Join-Path $multi 'Lib.fs')
(Get-Content -Raw (Join-Path $repo 'src/Lib/Lib.fsproj')).Replace('<TargetFramework>net10.0</TargetFramework>', '<TargetFrameworks>net10.0;net9.0</TargetFrameworks>') | Set-Content (Join-Path $multi 'Lib.fsproj')
$multiOut = @(& $sigDiff -Project (Join-Path $multi 'Lib.fsproj') -BaselineProject (Join-Path $multi 'Lib.fsproj') -OutDir (Join-Path $Artifacts 'sig-multi-out'))
$multiExit = $LASTEXITCODE
Assert-Proof 'sig-diff.ps1: a multi-target project without -Framework exits 2' ($multiExit -eq 2 -and ($multiOut -join "`n") -match 'several target frameworks') ($multiOut -join "`n")

Set-Content (Join-Path $repo 'src/Lib/Lib.fs') "module Lib`n`nlet total (unused: int) (amount: decimal) : decimal = amount`n"
$failed = @(& $sigDiff -Project $project -BaselineRef HEAD -OutDir (Join-Path $Artifacts 'sig-failed'))
$failedExit = $LASTEXITCODE
Assert-Proof 'sig-diff.ps1: keeps the project OtherFlags, so FS1182 as error exits 2' ($failedExit -eq 2 -and ($failed -join "`n") -match 'error FS1182') ($failed -join "`n")
