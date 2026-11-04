#Requires -Version 7.4
param([string[]]$Case = @())
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$Case = @($Case | ForEach-Object { $_ -split ',' } | Where-Object { $_ })

$failures = [System.Collections.Generic.List[string]]::new()
$artifacts = Join-Path ([IO.Path]::GetTempPath()) "fsharp-binary-compatibility-proof-$PID"
New-Item -ItemType Directory -Force -Path $artifacts | Out-Null
$env:FSHARP_BINCOMPAT_PROOF_ROOT = $artifacts
$proof = Join-Path $PSScriptRoot 'proof'
$libProject = Join-Path $proof 'Lib/Lib.fsproj'
$consumerProject = Join-Path $proof 'Consumer/Consumer.fsproj'
$sigTargets = Join-Path $PSScriptRoot 'SigDiff.targets'

function Invoke-Dotnet([string[]]$Arguments, [string]$WorkingDirectory = $PSScriptRoot) {
    # dotnet selects its SDK from global.json above the working directory.
    Push-Location $WorkingDirectory
    try {
        $output = @(dotnet @Arguments 2>&1 | ForEach-Object { "$_" })
        [pscustomobject]@{ ExitCode = $LASTEXITCODE; Lines = $output; Text = ($output -join "`n") }
    } finally { Pop-Location }
}

$restored = @{}
function Get-RestoreArgument([string]$Project) {
    if ($restored.ContainsKey($Project)) { return @('--no-restore') }
    $restored[$Project] = $true
    @()
}

function Get-ErrorCodes([string]$Text) {
    @([regex]::Matches($Text, 'error (FS\d+|CP\d+|RS\d+|NU\d+)') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
}

function Build-Lib([string]$Source, [string]$OutDir) {
    $flags = ''
    $first = Get-Content -TotalCount 1 $Source
    if ($first -match '^//\s*flags:\s*(.+)$') { $flags = $Matches[1].Trim() }
    $sig = "$OutDir.fsi"
    $r = Invoke-Dotnet (@('build', $libProject, '-c', 'Release', '--no-incremental', '-nologo', '-o', $OutDir) + (Get-RestoreArgument $libProject) + @(
        "-p:CaseFile=$Source", "-p:ProofFlags=$flags",
        "-p:CustomAfterMicrosoftCommonTargets=$sigTargets", "-p:SigDiffProject=$libProject", "-p:SigDiffOutput=$sig"))
    [pscustomobject]@{ Ok = $r.ExitCode -eq 0; Codes = (Get-ErrorCodes $r.Text); Text = $r.Text; Dll = (Join-Path $OutDir 'Lib.dll'); Sig = $sig }
}

function Build-Consumer([string]$Source, [string]$LibDll, [string]$OutDir, [string[]]$Extra = @()) {
    $r = Invoke-Dotnet (@('build', $consumerProject, '-c', 'Release', '--no-incremental', '-nologo', '-o', $OutDir) + (Get-RestoreArgument $consumerProject) + @(
        "-p:ConsumerFile=$Source", "-p:LibDll=$LibDll") + $Extra)
    $warnings = @([regex]::Matches($r.Text, 'warning (FS\d+)') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
    [pscustomobject]@{ Ok = $r.ExitCode -eq 0; Codes = (Get-ErrorCodes $r.Text); Warnings = $warnings; Text = $r.Text }
}

function Invoke-Consumer([string]$Dir) {
    $r = Invoke-Dotnet @((Join-Path $Dir 'Consumer.dll'))
    $exception = if ($r.Text -match 'Unhandled exception\. (?:[\w]+\.)*(\w+(?:Exception)?):') { $Matches[1] } elseif ($r.ExitCode -ne 0) { "exit $($r.ExitCode)" } else { $null }
    [pscustomobject]@{ Exception = $exception; Output = (($r.Lines | ForEach-Object { $_.TrimEnd() }) -join "`n").Trim() }
}

function Get-Signature([string]$Path) {
    if (-not (Test-Path $Path)) { return $null }
    ((Get-Content $Path | ForEach-Object { $_.TrimEnd() } | Where-Object { $_ }) -join "`n")
}

function Invoke-ApiCompat([string]$Left, [string]$Right, [switch]$Strict) {
    $arguments = @('apicompat', '--left', $Left, '--right', $Right)
    if ($Strict) { $arguments += @('--strict-mode', '--enable-rule-attributes-must-match', '--enable-rule-cannot-change-parameter-name') }
    $r = Invoke-Dotnet $arguments
    if ($r.ExitCode -eq 0 -and $r.Text -match 'without finding any breaking changes') { return 'clean' }
    if ($r.ExitCode -ne 0 -and $r.Text -match 'CP\d{4}') { return 'reports' }
    "error: $($r.Text)"
}

$restore = Invoke-Dotnet @('tool', 'restore')
if ($restore.ExitCode -ne 0) { throw "dotnet tool restore failed:`n$($restore.Text)" }

$rows = [System.Collections.Generic.List[object]]::new()
$apiJobs = [System.Collections.Generic.List[string]]::new()
$apiChecks = [System.Collections.Generic.List[object]]::new()

try {
    $caseDirs = @(Get-ChildItem (Join-Path $proof 'cases') -Directory | Where-Object { $Case.Count -eq 0 -or $_.Name -in $Case } | Sort-Object Name)
    if ($caseDirs.Count -eq 0) { $failures.Add("No case matches: $($Case -join ', ').") }
    foreach ($caseDir in $caseDirs) {
        $consumer = Join-Path $caseDir.FullName 'Consumer.fs'
        $expects = @(Get-Content $consumer | ForEach-Object {
                if ($_ -match '^//\s*expect\s+(\S+)\s+from\s+(\S+):\s*(.+)$') {
                    $values = [ordered]@{}
                    foreach ($pair in $Matches[3].Trim() -split '\s+') { $k, $v = $pair -split '=', 2; $values[$k] = $v }
                    [pscustomobject]@{ Variant = $Matches[1]; Base = $Matches[2]; Values = $values }
                }
            })
        if ($expects.Count -eq 0) { $failures.Add("$($caseDir.Name): Consumer.fs has no // expect line."); continue }
        $out = Join-Path $artifacts $caseDir.Name
        $libs = @{}
        $baseRuns = @{}
        foreach ($name in @($expects | ForEach-Object { $_.Base; $_.Variant } | Select-Object -Unique)) {
            $libs[$name] = Build-Lib (Join-Path $caseDir.FullName "$name.fs") (Join-Path $out $name)
        }
        foreach ($base in @($expects.Base | Select-Object -Unique)) {
            if (-not $libs[$base].Ok) { $failures.Add("$($caseDir.Name): base $base did not build.`n$($libs[$base].Text)"); continue }
            $dir = Join-Path $out "consumer-$base"
            $c = Build-Consumer $consumer $libs[$base].Dll $dir
            if (-not $c.Ok) { $failures.Add("$($caseDir.Name): Consumer.fs did not build against $base.`n$($c.Text)"); continue }
            $baseRuns[$base] = @{ Dir = $dir; Run = (Invoke-Consumer $dir) }
            if ($baseRuns[$base].Run.Exception) { $failures.Add("$($caseDir.Name): Consumer.fs threw against $base. $($baseRuns[$base].Run.Output)") }
            $apiJobs.Add("$($libs[$base].Dll)|$(Join-Path $out "$base.api.txt")")
        }

        foreach ($e in $expects) {
            $actual = [ordered]@{}
            $lib = $libs[$e.Variant]
            if ($e.Values.Contains('build')) {
                $actual.build = if ($lib.Ok) { 'ok' } elseif ($lib.Codes -ccontains $e.Values.build) { $e.Values.build } else { $lib.Codes -join ',' }
            } elseif (-not $lib.Ok) {
                $actual.build = $lib.Codes -join ','
            } elseif ($baseRuns.ContainsKey($e.Base)) {
                $baseRun = $baseRuns[$e.Base].Run
                $oldDir = Join-Path $out "old-$($e.Variant)-from-$($e.Base)"
                Copy-Item $baseRuns[$e.Base].Dir $oldDir -Recurse
                Copy-Item $lib.Dll (Join-Path $oldDir 'Lib.dll') -Force
                $old = Invoke-Consumer $oldDir

                $rebuiltDir = Join-Path $out "rebuilt-$($e.Variant)-from-$($e.Base)"
                $rb = Build-Consumer $consumer $lib.Dll $rebuiltDir
                $rebuilt = if ($rb.Ok) { Invoke-Consumer $rebuiltDir } else { $null }
                $wantRebuild = "$($e.Values['rebuild'])"
                $actual.rebuild = if (-not $rb.Ok) { if ($rb.Codes -ccontains $wantRebuild) { $wantRebuild } else { 'fails:' + ($rb.Codes -join ',') } } elseif ($rebuilt.Exception) { $rebuilt.Exception } elseif ($rebuilt.Output -ceq $baseRun.Output) { 'same' } else { 'differs' }
                if ($e.Values.Contains('rebuildwarn')) {
                    $wantWarning = "$($e.Values['rebuildwarn'])"
                    $actual.rebuildwarn = if ($rb.Warnings -ccontains $wantWarning) { $wantWarning } else { 'none:' + ($rb.Warnings -join ',') }
                }
                if ($e.Values.Contains('strictrebuild')) {
                    $strict = Build-Consumer $consumer $lib.Dll (Join-Path $out "strict-$($e.Variant)-from-$($e.Base)") @('-p:TreatWarningsAsErrors=true')
                    $wantStrict = "$($e.Values['strictrebuild'])"
                    $actual.strictrebuild = if ($strict.Ok) { 'ok' } elseif ($strict.Codes -ccontains $wantStrict) { $wantStrict } else { 'fails:' + ($strict.Codes -join ',') }
                }
                $rebuiltOutput = if ($rebuilt -and -not $rebuilt.Exception) { $rebuilt.Output } else { $null }
                $actual.old = if ($old.Exception) { $old.Exception }
                elseif ($old.Output -ceq $baseRun.Output) { if ($null -ne $rebuiltOutput -and $rebuiltOutput -cne $baseRun.Output) { 'stale' } else { 'same' } }
                elseif ($null -ne $rebuiltOutput -and $old.Output -ceq $rebuiltOutput) { 'updated' }
                else { 'wrong' }

                $actual.apicompat = Invoke-ApiCompat $libs[$e.Base].Dll $lib.Dll
                $actual.strict = Invoke-ApiCompat $libs[$e.Base].Dll $lib.Dll -Strict
                $baseSig = Get-Signature $libs[$e.Base].Sig
                $variantSig = Get-Signature $lib.Sig
                $actual.sig = if ($null -eq $baseSig -or $null -eq $variantSig) { 'missing' } elseif ($baseSig -ceq $variantSig) { 'clean' } else { 'reports' }
                $apiJobs.Add("$($lib.Dll)|$(Join-Path $out "$($e.Variant).api.txt")")
                $apiChecks.Add([pscustomobject]@{ Case = $caseDir.Name; Expect = $e; Actual = $actual; Before = (Join-Path $out "$($e.Base).api.txt"); After = (Join-Path $out "$($e.Variant).api.txt") })
            }
            $rows.Add([pscustomobject]@{ Case = $caseDir.Name; Expect = $e; Actual = $actual })
        }
    }

    if ($apiJobs.Count -gt 0) {
        $api = Invoke-Dotnet (@('fsi', '--nologo', (Join-Path $PSScriptRoot 'PublicApi.fsx')) + @($apiJobs | Select-Object -Unique))
        if ($api.ExitCode -ne 0) { $failures.Add("PublicApi.fsx failed:`n$($api.Text)") }
        foreach ($a in $apiChecks) {
            $a.Actual.api = if (-not (Test-Path $a.Before) -or -not (Test-Path $a.After)) { 'missing' }
            elseif ((Get-Content -Raw $a.Before) -ceq (Get-Content -Raw $a.After)) { 'clean' } else { 'reports' }
        }
    }

    Write-Output ''
    Write-Output ('{0,-20} {1,-13} {2}' -f 'case', 'variant', 'result (expected value when it differs)')
    foreach ($row in $rows) {
        $parts = foreach ($key in $row.Expect.Values.Keys) {
            $want = $row.Expect.Values[$key]
            $got = if ($row.Actual.Contains($key)) { $row.Actual[$key] } else { 'not run' }
            if ($got -ceq $want) { "$key=$got" } else {
                $failures.Add("$($row.Case) $($row.Expect.Variant): $key is '$got'. Expected '$want'.")
                "$key=$got (expected $want)"
            }
        }
        if ($row.Actual.Contains('build') -and -not $row.Expect.Values.Contains('build')) {
            $failures.Add("$($row.Case) $($row.Expect.Variant): the library did not build ($($row.Actual.build)).")
            $parts = @("build=$($row.Actual.build)")
        }
        Write-Output ('{0,-20} {1,-13} {2}' -f $row.Case, "$($row.Expect.Variant)", ($parts -join ' '))
    }

    if ($Case.Count -eq 0) {
        Write-Output ''
        & (Join-Path $PSScriptRoot 'proof/ToolProofs.ps1') -Artifacts $artifacts -Failures $failures
    }
} finally {
    Remove-Item Env:FSHARP_BINCOMPAT_PROOF_ROOT -ErrorAction SilentlyContinue
    if (Test-Path $artifacts) { Remove-Item -Recurse -Force -LiteralPath $artifacts -ErrorAction SilentlyContinue }
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ -ErrorAction Continue }
    exit 1
}
Write-Output 'All binary compatibility proofs passed.'
