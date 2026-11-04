#!/usr/bin/env pwsh
#Requires -Version 7.4
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../graders/CompatibilityCommand.ps1')

$failures = [System.Collections.Generic.List[string]]::new()
function Assert-Command([string]$Name, [string]$Command, [bool]$Expected, [bool]$ProjectValidates = $false) {
    $actual = Test-CompatibilityCommand $Command $ProjectValidates
    if ($actual -eq $Expected) { Write-Host "PASS $Name" } else { Write-Host "FAIL $Name (got $actual)"; $failures.Add($Name) }
}
function Assert-Signature([string]$Name, [string]$Command, [bool]$Expected) {
    $actual = Test-SignatureBuild $Command
    if ($actual -eq $Expected) { Write-Host "PASS $Name" } else { Write-Host "FAIL $Name (got $actual)"; $failures.Add($Name) }
}
function Assert-Baseline([string]$Name, [string]$Command, [int]$Expected) {
    $actual = @(Get-SignatureBuilds $Command | Where-Object Baseline).Count
    if ($actual -eq $Expected) { Write-Host "PASS $Name" } else { Write-Host "FAIL $Name (got $actual)"; $failures.Add($Name) }
}

$heredocScript = @'
cat > check.ps1 <<'EOF'
dotnet apicompat --left a.dll --right b.dll
EOF
'@
$heredocNotes = @'
cat > notes.md <<EOF
pwsh ./scripts/sig-diff.ps1 -Project Shipping/Shipping.fsproj
EOF
echo done
'@
$hereString = @"
Set-Content run.txt @'
dotnet apicompat --left a.dll --right b.dll
'@
"@
$heredocThenRun = @'
cat > notes.md <<'EOF'
text
EOF
dotnet apicompat --left a.dll --right b.dll
'@

$codexToolPath = @'
"C:\\Program Files\\PowerShell\\7\\pwsh.exe" -Command '$env:DOTNET_CLI_HOME = Join-Path $PWD '"'.verification/dotnet-home'
"'$env:DOTNET_NOLOGO = '"'1'
.verification/tools/apicompat.exe --left .verification/baseline/Shipping.dll --right Shipping/bin/Release/net10.0/Shipping.dll | Tee-Object .verification/apicompat.txt
exit "'$LASTEXITCODE'
'@
$codexSigDiffFile = @'
"C:\\Program Files\\PowerShell\\7\\pwsh.exe" -Command '$env:DOTNET_CLI_HOME = Join-Path $PWD '"'.verification/dotnet-home'
"'$env:DOTNET_NOLOGO = '"'1'
pwsh -NoProfile -File .agents/skills/x/scripts/sig-diff.ps1 -Project Shipping/Shipping.fsproj -BaselineProject .verification/baseline/Shipping/Shipping.fsproj"
'@
$codexRead = @'
"C:\\Program Files\\PowerShell\\7\\pwsh.exe" -Command 'Get-Content Shipping/Shipping.fs; Get-Content .agents/skills/x/scripts/sig-diff.ps1; git status --short'
'@

Assert-Command 'a Codex multi-line command runs apicompat from a tool path' $codexToolPath $true
Assert-Command 'a Codex multi-line command runs sig-diff with -File' $codexSigDiffFile $true
Assert-Command 'a Codex command that reads sig-diff.ps1 does not run it' $codexRead $false
Assert-Command 'dotnet apicompat runs''dotnet apicompat --left base/Shipping.dll --right new/Shipping.dll' $true
Assert-Command 'apicompat after cd runs' 'cd ws && dotnet apicompat --left a.dll --right b.dll' $true
Assert-Command 'global apicompat runs' 'apicompat --left a.dll --right b.dll' $true
Assert-Command 'dotnet tool run apicompat runs' 'dotnet tool run apicompat --left a.dll --right b.dll' $true
Assert-Command 'a quoted dotnet path runs apicompat' '& "C:\Program Files\dotnet\dotnet.exe" apicompat --left a.dll --right b.dll' $true
Assert-Command 'a Codex pwsh wrapper runs apicompat' '"C:\Program Files\PowerShell\7\pwsh.exe" -Command "Set-Location ws; dotnet apicompat --left a.dll --right b.dll"' $true
Assert-Command 'a pwsh wrapper with an option value runs apicompat' 'powershell -ExecutionPolicy Bypass -Command "dotnet apicompat --left a.dll --right b.dll"' $true
Assert-Command 'a bash wrapper runs sig-diff' "/bin/bash -lc 'pwsh ./.agents/skills/x/scripts/sig-diff.ps1 -Project Shipping/Shipping.fsproj -BaselineProject release-1.0.0/Shipping/Shipping.fsproj'" $true
Assert-Command 'a direct sig-diff call runs' './.claude/skills/x/scripts/sig-diff.ps1 -Project Shipping/Shipping.fsproj' $true
Assert-Command 'a quoted sig-diff path runs' 'pwsh "./scripts/sig-diff.ps1" -Project a.fsproj' $true
Assert-Command 'a quoted sig-diff path with a space runs' 'pwsh "C:\work folder\scripts\sig-diff.ps1" -Project Shipping/Shipping.fsproj' $true
Assert-Command 'a quoted apicompat path with a space runs' '& "C:\work folder\tools\apicompat.exe" --left a.dll --right b.dll' $true
Assert-Command 'a quoted message that ends in sig-diff.ps1 does not run it' 'echo "see the docs of scripts/sig-diff.ps1"' $false
Assert-Command 'time before apicompat runs' 'time dotnet apicompat --left a.dll --right b.dll' $true
Assert-Command 'an environment assignment before apicompat runs' 'DOTNET_NOLOGO=1 dotnet apicompat --left a.dll --right b.dll' $true
Assert-Command 'apicompat in a for loop runs' 'for d in a b; do dotnet apicompat --left $d/a.dll --right b.dll; done' $true
Assert-Command 'apicompat after a heredoc runs' $heredocThenRun $true
Assert-Command 'a dotnet build with --sig is not a comparison by itself' 'dotnet build Shipping -p:OtherFlags=--sig:out.fsi' $false
Assert-Signature 'dotnet build with --sig writes a signature' 'dotnet build Shipping -p:OtherFlags=--sig:out.fsi' $true
Assert-Signature 'a quoted OtherFlags value with spaces keeps --sig' 'dotnet build Shipping -p:OtherFlags="--warnon:1182 --sig:out.fsi"' $true
Assert-Signature 'a single-quoted OtherFlags value with spaces keeps --sig' "dotnet build Shipping '-p:OtherFlags=--sig:out.fsi --warnon:1182'" $true
$twoBuilds = @(Get-SignatureBuilds 'dotnet build old/Shipping -p:OtherFlags=--sig:old.fsi && dotnet build Shipping -p:OtherFlags=--sig:new.fsi').Count
if ($twoBuilds -eq 2) { Write-Host 'PASS one shell call with two --sig builds gives two signature builds' } else { Write-Host "FAIL one shell call with two --sig builds gives two signature builds (got $twoBuilds)"; $failures.Add('two builds in one call') }
Assert-Signature 'a plain dotnet build writes no signature' 'dotnet build Shipping -c Release' $false
Assert-Baseline 'a --sig build of release-1.0.0 builds the baseline' 'dotnet build release-1.0.0/Shipping/Shipping.fsproj -c Release -p:OtherFlags=--sig:old.fsi' 1
Assert-Baseline 'a --sig build of a Windows release-1.0.0 path builds the baseline' 'dotnet build -c Release .\release-1.0.0\Shipping -p:OtherFlags=--sig:old.fsi' 1
Assert-Baseline 'a --sig msbuild of release-1.0.0 builds the baseline' 'dotnet msbuild /t:Build release-1.0.0/Shipping/Shipping.fsproj /p:OtherFlags=--sig:old.fsi' 1
Assert-Baseline 'a --sig build after cd release-1.0.0 builds the baseline' 'cd release-1.0.0/Shipping && dotnet build -p:OtherFlags=--sig:../../old.fsi' 1
Assert-Baseline 'a --sig build after Set-Location into release-1.0.0 builds the baseline' 'pwsh -Command "Set-Location release-1.0.0; dotnet build Shipping -p:OtherFlags=--sig:old.fsi"' 1
Assert-Baseline 'a --sig build of the new Shipping is not the baseline' 'dotnet build Shipping -p:OtherFlags=--sig:new.fsi' 0
Assert-Baseline 'a signature file named release-1.0.0 is not the baseline' 'dotnet build Shipping -p:OtherFlags=--sig:release-1.0.0.fsi' 0
Assert-Baseline 'an output folder named release-1.0.0 is not the baseline' 'dotnet build Shipping -o release-1.0.0/out -p:OtherFlags=--sig:new.fsi' 0
Assert-Baseline 'a cd into release-1.0.0 after the build does not count' 'dotnet build Shipping -p:OtherFlags=--sig:new.fsi && cd release-1.0.0' 0
Assert-Baseline 'a plain build of release-1.0.0 is not a signature build' 'dotnet build release-1.0.0/Shipping' 0
Assert-Baseline 'a --sig build after an absolute cd into release-1.0.0 builds the baseline' 'cd /work/ws/release-1.0.0/Shipping && dotnet build -p:OtherFlags=--sig:old.fsi' 1
Assert-Baseline 'a --sig build after an absolute Windows Set-Location builds the baseline' 'pwsh -Command "Set-Location C:\work\ws\release-1.0.0\Shipping; dotnet build -p:OtherFlags=--sig:old.fsi"' 1
Assert-Baseline 'a --sig build after cd ~ into release-1.0.0 builds the baseline' 'cd ~/ws/release-1.0.0/Shipping && dotnet build -p:OtherFlags=--sig:old.fsi' 1
Assert-Baseline 'a --sig build after Push-Location into release-1.0.0 builds the baseline' 'pwsh -Command "Push-Location release-1.0.0/Shipping; dotnet build -p:OtherFlags=--sig:old.fsi"' 1
Assert-Baseline 'a --sig build after Set-Location -LiteralPath builds the baseline' 'pwsh -Command "Set-Location -LiteralPath release-1.0.0/Shipping; dotnet build -p:OtherFlags=--sig:old.fsi"' 1
Assert-Baseline 'a --tl value is not the project' 'dotnet build --tl off release-1.0.0/Shipping -p:OtherFlags=--sig:old.fsi' 1
Assert-Baseline 'a --self-contained value is not the project' 'dotnet build --self-contained false release-1.0.0/Shipping -p:OtherFlags=--sig:old.fsi' 1
Assert-Baseline 'msbuild -r takes no value' 'dotnet msbuild -r release-1.0.0/Shipping/Shipping.fsproj /p:OtherFlags=--sig:old.fsi' 1
Assert-Baseline 'a cd back out of release-1.0.0 is not the baseline' 'cd release-1.0.0 && ls && cd .. && dotnet build Shipping -p:OtherFlags=--sig:new.fsi' 0
Assert-Baseline 'a popd out of release-1.0.0 is not the baseline' 'pushd release-1.0.0 && popd && dotnet build Shipping -p:OtherFlags=--sig:new.fsi' 0
Assert-Baseline 'a popd returns to the folder before its pushd' 'cd release-1.0.0 && pushd Shipping && popd && dotnet build Shipping -p:OtherFlags=--sig:old.fsi' 1
Assert-Baseline 'a bare cd leaves release-1.0.0' 'cd release-1.0.0 && cd && dotnet build Shipping -p:OtherFlags=--sig:new.fsi' 0
Assert-Signature 'a commit message that names --sig writes no signature' 'git commit -m "dotnet build -p:OtherFlags=--sig:a.fsi"' $false
Assert-Command 'apicompat package comparison runs' 'dotnet apicompat package new/Shipping.1.1.0.nupkg --baseline-package old/Shipping.1.0.0.nupkg' $true
Assert-Command 'apicompat --help does not count' 'dotnet apicompat --help' $false
Assert-Command 'apicompat --version does not count' 'apicompat --version' $false
Assert-Command 'apicompat with no comparison arguments does not count' 'dotnet apicompat' $false
Assert-Command 'sig-diff.ps1 -? does not count' 'pwsh ./scripts/sig-diff.ps1 -?' $false
Assert-Command 'sig-diff.ps1 with no -Project does not count' 'pwsh ./scripts/sig-diff.ps1' $false
Assert-Command 'dotnet pack with validation and a baseline on the command line runs' 'dotnet pack Shipping -p:EnablePackageValidation=true -p:PackageValidationBaselineVersion=1.0.0' $true
Assert-Command 'dotnet pack with validation in the project runs' 'cd Shipping && dotnet pack -c Release' $true $true

Assert-Command 'reading sig-diff.ps1 does not run it' 'sed -n 1,80p .agents/skills/x/scripts/sig-diff.ps1' $false
Assert-Command 'searching for apicompat does not run it' 'grep -rn apicompat .' $false
Assert-Command 'reading a project with validation does not run it' 'cat Shipping/Shipping.fsproj | grep EnablePackageValidation' $false
Assert-Command 'a heredoc that writes apicompat does not run it' $heredocScript $false
Assert-Command 'a heredoc that writes sig-diff does not run it' $heredocNotes $false
Assert-Command 'a PowerShell here-string that writes apicompat does not run it' $hereString $false
Assert-Command 'a commit message that names apicompat does not run it' 'git commit -m "step 1; dotnet apicompat --left a --right b"' $false
Assert-Command 'dotnet pack without validation does not count' 'dotnet pack Shipping -c Release' $false
Assert-Command 'dotnet pack with validation and no baseline does not count' 'dotnet pack Shipping -p:EnablePackageValidation=true' $false
Assert-Command 'dotnet build does not count' 'dotnet build Shipping -c Release' $false
Assert-Command 'an empty command does not count' '' $false

if ($failures.Count) {
    Write-Host "$($failures.Count) command test(s) failed: $($failures -join ', ')"
    exit 1
}
Write-Host 'All compatibility command tests passed.'
