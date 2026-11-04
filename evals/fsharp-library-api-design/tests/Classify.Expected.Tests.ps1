#Requires -Version 7.4
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$root = Join-Path ([IO.Path]::GetTempPath()) "library-api-design-expected-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
$inputs = Join-Path $PSScriptRoot '../inputs'
$grader = Join-Path $PSScriptRoot '../graders/minor-release.ps1'
$globalJson = Get-Content -Raw (Join-Path $PSScriptRoot '../graders/global.json')
$expected = Get-Content -Raw (Join-Path $PSScriptRoot '../graders/classify-expected.json') | ConvertFrom-Json
$failures = [System.Collections.Generic.List[string]]::new()
$feed = Join-Path $root 'feed'
$previousPackages = $env:NUGET_PACKAGES
$env:NUGET_PACKAGES = Join-Path $root 'packages'
$packageId = '-p:PackageId=FsApiDesignEvalPayments'

function Invoke-Pack([string]$ProjectDir, [string[]]$Extra) {
    Push-Location $ProjectDir
    try {
        $output = dotnet pack -c Release @Extra 2>&1 | ForEach-Object { "$_" }
        [pscustomobject]@{ ExitCode = $LASTEXITCODE; Text = ($output -join "`n") }
    } finally { Pop-Location }
}

try {
    New-Item -ItemType Directory -Force -Path $feed | Out-Null
    & (Join-Path $PSScriptRoot 'New-ClassifyVariants.ps1') -Destination (Join-Path $root 'variants')
    $baseline = Join-Path $root 'baseline'
    New-Item -ItemType Directory -Force -Path $baseline | Out-Null
    Set-Content (Join-Path $baseline 'global.json') $globalJson
    Copy-Item (Join-Path $inputs 'Payments') $baseline -Recurse
    $p = Invoke-Pack (Join-Path $baseline 'Payments') @('-o', $feed, $packageId)
    if ($p.ExitCode -ne 0) { throw "The 1.0.0 baseline did not pack:`n$($p.Text)" }

    foreach ($change in $expected.PSObject.Properties) {
        $ws = Join-Path $root "$($change.Name)/ws"
        $out = Join-Path $root "$($change.Name)/grade"
        New-Item -ItemType Directory -Force -Path $ws, $out | Out-Null
        foreach ($name in 'Payments', 'Checkout', 'CheckoutCs') { Copy-Item (Join-Path $inputs $name) $ws -Recurse }
        Copy-Item (Join-Path $root "variants/$($change.Name)/Payments.fs") (Join-Path $ws 'Payments') -Force
        & $grader -Workspace $ws -OutDir $out
        $checks = @{}
        foreach ($c in @(Get-Content -Raw (Join-Path $out 'grading.json') | ConvertFrom-Json)) { $checks[$c.text] = $c.passed }
        if (-not $checks['Payments builds']) { $failures.Add("$($change.Name): the changed library did not build."); continue }

        $pack = Invoke-Pack (Join-Path $out 'ws/Payments') @('-o', (Join-Path $root "$($change.Name)/pkg"), $packageId, '-p:Version=1.1.0',
            '-p:EnablePackageValidation=true', '-p:PackageValidationBaselineVersion=1.0.0', "-p:RestoreAdditionalProjectSources=$feed")
        $actual = [ordered]@{
            fsharpSource = -not $checks['The 1.0.0 source of Checkout builds against the new Payments and prints the same output']
            csharpSource = -not $checks['The 1.0.0 source of CheckoutCs builds against the new Payments and prints the same output']
            binary = -not ($checks['Checkout compiled against 1.0.0 runs with the new Payments.dll and prints the same output'] -and
                $checks['CheckoutCs compiled against 1.0.0 runs with the new Payments.dll and prints the same output'])
            packageValidation = $pack.ExitCode -ne 0
        }
        if ($pack.ExitCode -ne 0 -and $pack.Text -notmatch 'error CP\d+') { $failures.Add("$($change.Name): pack failed without a CP error:`n$($pack.Text)"); continue }
        $line = ($actual.Keys | ForEach-Object { "$_=$($actual[$_])" }) -join ' '
        Write-Host ("{0,-20} {1}" -f $change.Name, $line)
        foreach ($field in $actual.Keys) {
            $want = $change.Value.PSObject.Properties[$field]
            if ($want -and $want.Value -ne $actual[$field]) { $failures.Add("$($change.Name) ${field}: expected $($want.Value), measured $($actual[$field]).") }
        }
    }
} finally {
    $env:NUGET_PACKAGES = $previousPackages
    Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Host "FAIL $_" }
    exit 1
}
Write-Host 'PASS each expected classification matches a real build'
