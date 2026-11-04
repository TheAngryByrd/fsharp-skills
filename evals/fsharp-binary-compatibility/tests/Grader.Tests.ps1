#!/usr/bin/env pwsh
#Requires -Version 7.4
param([string[]]$Case)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$evalDir = Split-Path $PSScriptRoot
$spec = Get-Content -Raw (Join-Path $evalDir 'evals.json') | ConvertFrom-Json
$failures = [System.Collections.Generic.List[string]]::new()
$root = Join-Path ([IO.Path]::GetTempPath()) ("binary-compatibility-grader-tests-" + [guid]::NewGuid().ToString('n'))

$names = [ordered]@{
    build    = 'Shipping builds'
    version  = 'The Shipping version is 1.1.0'
    load     = 'LegacyApp compiled against 1.0.0 runs with the new Shipping.dll with no MissingMethodException, TypeLoadException, or MissingFieldException'
    output   = 'LegacyApp compiled against 1.0.0 prints the same output with the new Shipping.dll'
    compat   = 'apicompat finds no break from Shipping 1.0.0'
    newapp   = 'NewApp references Shipping and prints the requested lines for express, insurance, and Held'
    tool     = 'The transcript shows an automated compatibility check: package validation, apicompat, or an F# signature diff'
}

function New-Transcript([string]$Path, [string[]]$Commands) {
    # 'FAIL <output> :: <command>' gives a failed result and 'OK <output> :: <command>' a successful one, each with that output.
    # A plain command succeeds with the result text that its tool prints.
    $i = 0
    $lines = foreach ($entry in $Commands) {
        $i++
        $explicit = $entry -match '^(?<state>FAIL|OK) (?<output>.*?) :: (?<command>.*)$'
        $failed = $explicit -and $Matches.state -eq 'FAIL'
        $command = if ($explicit) { $Matches.command } else { $entry }
        $output = if ($explicit) { $Matches.output }
        elseif ($command -match 'apicompat') { 'APICompat ran successfully without finding any breaking changes.' }
        elseif ($command -match 'sig-diff') { 'No F# signature change.' }
        elseif ($command -match 'dotnet pack') { 'Successfully created package' }
        else { 'ok' }
        ConvertTo-Json -Depth 10 -Compress -InputObject @{ type = 'assistant'; message = @{ content = @(@{ type = 'tool_use'; id = "t$i"; name = 'Bash'; input = @{ command = $command } }) } }
        ConvertTo-Json -Depth 10 -Compress -InputObject @{ type = 'user'; message = @{ content = @(@{ type = 'tool_result'; tool_use_id = "t$i"; is_error = $failed; content = $output }) } }
    }
    Set-Content $Path $lines
}

function Invoke-Case([string]$Name, [scriptblock]$Prepare, [string[]]$Command, [hashtable]$Expected, [string]$TaskId = 'shipping-1-1') {
    if ($Case -and $Name -notin $Case) { return }
    $task = $spec.tasks | Where-Object id -eq $TaskId
    $grader = Join-Path $evalDir $task.grader
    $run = Join-Path $root $Name
    $ws = Join-Path $run 'ws'
    New-Item -ItemType Directory -Force -Path $ws | Out-Null
    foreach ($f in @($task.files)) { Copy-Item (Join-Path $evalDir $f) $ws -Recurse }
    & $Prepare $ws
    if ($Command) { New-Transcript (Join-Path $run 'transcript.jsonl') $Command }
    $grade = Join-Path $run 'grade'
    New-Item -ItemType Directory -Force -Path $grade | Out-Null
    & $grader -Workspace $ws -OutDir $grade | Out-Null
    $checks = @(Get-Content -Raw (Join-Path $grade 'grading.json') | ConvertFrom-Json)
    foreach ($key in $Expected.Keys) {
        $text = if ($TaskId -eq 'feed-codes') { $names[$key] -replace '^LegacyApp ', 'A customer app ' } else { $names[$key] }
        $check = $checks | Where-Object text -eq $text | Select-Object -First 1
        $got = if ($check) { $check.passed } else { 'absent' }
        $want = $Expected[$key]
        if ("$got" -eq "$want") { Write-Host "PASS $Name $key = $want" }
        else {
            Write-Host "FAIL $Name $key = $got (expected $want) $($check.evidence)"
            $failures.Add("$Name $key")
        }
    }
}

function Set-Good([string]$Ws) {
    Copy-Item (Join-Path $PSScriptRoot 'good/*') $Ws -Recurse -Force
}

function Edit-Shipping([string]$Ws, [string]$Old, [string]$New) {
    $path = Join-Path $Ws 'Shipping/Shipping.fs'
    $text = (Get-Content -Raw $path) -replace "`r`n", "`n"
    if (-not $text.Contains($Old)) { throw "Shipping.fs does not contain: $Old" }
    Set-Content $path $text.Replace($Old, $New) -NoNewline
}

try {
    $all = @{ build = $true; version = $true; load = $true; output = $true; compat = $true; newapp = $true; tool = $true }
    Invoke-Case 'good' { param($ws) Set-Good $ws } 'dotnet apicompat --left base/Shipping.dll --right bin/Shipping.dll' $all

    Invoke-Case 'naive' { param($ws) Copy-Item (Join-Path $PSScriptRoot 'naive/*') $ws -Recurse -Force } 'dotnet build NewApp' @{
        build = $true; version = $true; load = $false; output = $false; compat = $false; newapp = $true; tool = $false
    }

    Invoke-Case 'held-in-the-middle' {
        param($ws)
        Set-Good $ws
        Edit-Shipping $ws "    | InTransit`n    | Delivered`n    | Returned`n    | Held" "    | InTransit`n    | Held`n    | Delivered`n    | Returned"
    } 'pwsh ./sig-diff.ps1 -Project Shipping/Shipping.fsproj -BaselineProject release-1.0.0/Shipping/Shipping.fsproj' @{
        build = $true; load = $true; output = $false; compat = $true; newapp = $true; tool = $true
    }

    Invoke-Case 'quote-parameter' {
        param($ws)
        Set-Good $ws
        Edit-Shipping $ws 'let quote (parcel: Parcel) : Result<decimal, string> =' 'let quote (parcel: Parcel) (surcharge: decimal) : Result<decimal, string> ='
        Edit-Shipping $ws 'Ok(Math.Round(baseRate + perKg * parcel.WeightKg, 2, MidpointRounding.AwayFromZero))' 'Ok(Math.Round(baseRate + surcharge + perKg * parcel.WeightKg, 2, MidpointRounding.AwayFromZero))'
        Edit-Shipping $ws '| Standard -> quote parcel' '| Standard -> quote parcel 0M'
        Edit-Shipping $ws '| Express -> quote parcel |>' '| Express -> quote parcel 0M |>'
        Edit-Shipping $ws "    quote parcel`n    |> Result.map (fun price -> Math.Round" "    quote parcel 0M`n    |> Result.map (fun price -> Math.Round"
    } $null @{ build = $true; load = $false; compat = $false; newapp = $true; tool = $null }

    Invoke-Case 'parcel-field' {
        param($ws)
        Set-Good $ws
        Edit-Shipping $ws 'type Parcel = { Id: string; WeightKg: decimal }' 'type Parcel = { Id: string; WeightKg: decimal; Fragile: bool }'
        $app = Join-Path $ws 'NewApp/Program.fs'
        Set-Content $app ((Get-Content -Raw $app).Replace('WeightKg = 2.0M }', 'WeightKg = 2.0M; Fragile = false }').Replace('WeightKg = 5.0M }', 'WeightKg = 5.0M; Fragile = false }')) -NoNewline
    } 'dotnet pack Shipping -p:EnablePackageValidation=true -p:PackageValidationBaselineVersion=1.0.0' @{
        build = $true; load = $false; compat = $false; newapp = $true; tool = $true
    }

    Invoke-Case 'reads-tool-files-only' { param($ws) Set-Good $ws } 'sed -n 1,80p .agents/skills/fsharp-binary-compatibility-eval/scripts/sig-diff.ps1; grep -rn apicompat .; cat Shipping/Shipping.fsproj | grep EnablePackageValidation' @{ tool = $false }

    Invoke-Case 'codex-wrapped-apicompat' { param($ws) Set-Good $ws } '"C:\Program Files\PowerShell\7\pwsh.exe" -Command "Set-Location ws; dotnet apicompat --left a.dll --right b.dll"' @{ tool = $true }

    Invoke-Case 'pack-with-project-validation' {
        param($ws)
        Set-Good $ws
        $proj = Join-Path $ws 'Shipping/Shipping.fsproj'
        (Get-Content -Raw $proj).Replace('<Version>1.1.0</Version>', '<Version>1.1.0</Version><EnablePackageValidation>true</EnablePackageValidation><PackageValidationBaselineVersion>1.0.0</PackageValidationBaselineVersion>') | Set-Content $proj
    } 'cd Shipping && dotnet pack -c Release' @{ build = $true; load = $true; output = $true; newapp = $true; tool = $true }

    Invoke-Case 'newapp-prints-fixed-text' {
        param($ws)
        $proj = Join-Path $ws 'Shipping/Shipping.fsproj'
        (Get-Content -Raw $proj).Replace('<Version>1.0.0</Version>', '<Version>1.1.0</Version>') | Set-Content $proj
        Set-Content (Join-Path $ws 'NewApp/Program.fs') "printfn `"P1 standard 6.90`"`nprintfn `"P1 express 13.80`"`nprintfn `"P4 insured 13.50`"`nprintfn `"HD Held`"`n"
    } 'dotnet apicompat --left a.dll --right b.dll' @{ build = $true; version = $true; load = $true; output = $true; newapp = $false }

    Invoke-Case 'newapp-missing' { param($ws) Set-Good $ws; Remove-Item -Recurse -Force (Join-Path $ws 'NewApp') } 'dotnet apicompat --left a.dll --right b.dll' @{ build = $true; newapp = $false }

    Invoke-Case 'one-signature-build' { param($ws) Set-Good $ws } 'dotnet build Shipping -p:OtherFlags=--sig:new.fsi' @{ tool = $false }

    Invoke-Case 'two-signature-builds' { param($ws) Set-Good $ws } @('dotnet build release-1.0.0/Shipping -p:OtherFlags=--sig:old.fsi', 'dotnet build Shipping -p:OtherFlags="--sig:new.fsi --warnon:1182"') @{ tool = $true }

    Invoke-Case 'two-signature-builds-in-one-call' { param($ws) Set-Good $ws } 'dotnet build release-1.0.0/Shipping -p:OtherFlags=--sig:old.fsi && dotnet build Shipping -p:OtherFlags=--sig:new.fsi' @{ tool = $true }

    Invoke-Case 'pack-fails-restore' {
        param($ws)
        Set-Good $ws
        $proj = Join-Path $ws 'Shipping/Shipping.fsproj'
        (Get-Content -Raw $proj).Replace('<Version>1.1.0</Version>', '<Version>1.1.0</Version><EnablePackageValidation>true</EnablePackageValidation><PackageValidationBaselineVersion>1.0.0</PackageValidationBaselineVersion>') | Set-Content $proj
    } 'FAIL error NU1101: Unable to find package Contoso.Shipping :: cd Shipping && dotnet pack -c Release' @{ tool = $false }

    Invoke-Case 'apicompat-reports-a-break' { param($ws) Set-Good $ws } 'FAIL CP0002: Member exists on left but not on right :: dotnet apicompat --left a.dll --right b.dll' @{ tool = $true }

    Invoke-Case 'skipped-apicompat-in-a-successful-call' { param($ws) Set-Good $ws } 'OK done :: false && dotnet apicompat --left a.dll --right b.dll; echo done' @{ tool = $false }

    Invoke-Case 'sig-diff-output-cut-by-tail' { param($ws) Set-Good $ws } 'OK +val quoteInsured: decimal -> Parcel -> Result<decimal,string> :: pwsh ./scripts/sig-diff.ps1 -Project Shipping/Shipping.fsproj -BaselineProject release-1.0.0/Shipping/Shipping.fsproj 2>&1 | tail -15' @{ tool = $true }

    Invoke-Case 'clean-apicompat-then-a-failed-command' { param($ws) Set-Good $ws } 'FAIL APICompat ran successfully without finding any breaking changes. error MSB1009 :: dotnet apicompat --left a.dll --right b.dll && dotnet build missing.fsproj' @{ tool = $true }

    Invoke-Case 'feed-wrapper-record-and-result-parser' { param($ws) Copy-Item (Join-Path $PSScriptRoot 'feed-wrapper/*') $ws -Recurse -Force } 'dotnet apicompat --left a.dll --right b.dll' $all 'feed-codes'

    Invoke-Case 'apicompat-fails-to-start' { param($ws) Set-Good $ws } 'FAIL Could not execute because the specified command or file was not found :: dotnet apicompat --left a.dll --right b.dll' @{ tool = $false }

    Invoke-Case 'features-only-in-newapp' {
        param($ws)
        $proj = Join-Path $ws 'Shipping/Shipping.fsproj'
        (Get-Content -Raw $proj).Replace('<Version>1.0.0</Version>', '<Version>1.1.0</Version>') | Set-Content $proj
        Edit-Shipping $ws "    | Returned`n" "    | Returned`n    | Held`n"
        Edit-Shipping $ws "    | ""RT"" -> Some Returned`n" "    | ""RT"" -> Some Returned`n    | ""HD"" -> Some Held`n"
        $program = @(
            'open Shipping'
            'let show label (result: Result<decimal, string>) ='
            '    match result with'
            '    | Ok price -> printfn "%s %.2f" label price'
            '    | Error message -> printfn "%s error: %s" label message'
            'let p1 = { Id = "P1"; WeightKg = 2.0M }'
            'let p4 = { Id = "P4"; WeightKg = 5.0M }'
            'show "P1 standard" (quote p1)'
            'show "P1 express" (quote p1 |> Result.map (fun price -> price * 2M))'
            'show "P4 insured" (quote p4 |> Result.map (fun price -> price + 300.00M * 0.01M))'
            'match statusOf "HD" with'
            '| Some status -> printfn "HD %A" status'
            '| None -> printfn "HD unknown"'
        )
        Set-Content (Join-Path $ws 'NewApp/Program.fs') $program
    } 'dotnet apicompat --left a.dll --right b.dll' @{ build = $true; load = $true; output = $true; compat = $true; newapp = $false }

    $showLines = @(
        'open Shipping'
        'let show label (result: Result<decimal, string>) ='
        '    match result with'
        '    | Ok price -> printfn "%s %.2f" label price'
        '    | Error message -> printfn "%s error: %s" label message'
        'let p1 = { Id = "P1"; WeightKg = 2.0M }'
        'let p4 = { Id = "P4"; WeightKg = 5.0M }'
        'show "P1 standard" (quote p1)'
    )

    Invoke-Case 'express-and-insurance-as-parcel-members' {
        param($ws)
        Set-Good $ws
        Edit-Shipping $ws 'let quoteFor (service' 'let private quoteFor (service'
        Edit-Shipping $ws 'let quoteInsured (declaredValue' 'let private quoteInsured (declaredValue'
        Add-Content (Join-Path $ws 'Shipping/Shipping.fs') @(
            ''
            'type Parcel with'
            '    member parcel.ExpressPrice : Result<decimal, string> = quoteFor Express parcel'
            '    member parcel.InsuredPrice(declaredValue: decimal) : Result<decimal, string> = quoteInsured declaredValue parcel'
        )
        Set-Content (Join-Path $ws 'NewApp/Program.fs') ($showLines + @(
                'show "P1 express" p1.ExpressPrice'
                'show "P4 insured" (p4.InsuredPrice 300.00M)'
                'match statusOf "HD" with'
                '| Some status -> printfn "HD %A" status'
                '| None -> printfn "HD unknown"'
            ))
    } 'dotnet apicompat --left a.dll --right b.dll' $all

    $quoterClass = @(
        ''
        'type Quoter() ='
        '    member _.Express(parcel: Parcel) : Result<decimal, string> = quoteFor Express parcel'
        '    member _.Insured(parcel: Parcel, declaredValue: decimal) : Result<decimal, string> = quoteInsured declaredValue parcel'
    )
    $quoterLines = @(
        'let quoter = Quoter()'
        'show "P1 express" (quoter.Express p1)'
        'show "P4 insured" (quoter.Insured(p4, 300.00M))'
    )

    Invoke-Case 'feed-quoter-and-status-reader-classes' {
        param($ws)
        Copy-Item (Join-Path $PSScriptRoot 'feed-good/*') $ws -Recurse -Force
        Edit-Shipping $ws 'let quoteFor (service' 'let private quoteFor (service'
        Edit-Shipping $ws 'let quoteInsured (declaredValue' 'let private quoteInsured (declaredValue'
        Edit-Shipping $ws 'let statusOfCode (code' 'let private statusOfCode (code'
        Add-Content (Join-Path $ws 'Shipping/Shipping.fs') ($quoterClass + @(
                ''
                'type StatusReader() ='
                '    member _.Read(code: string) : ParcelStatus option = statusOfCode code'
            ))
        Set-Content (Join-Path $ws 'NewApp/Program.fs') ($showLines + $quoterLines + @(
                'match StatusReader().Read "HD" with'
                '| Some status -> printfn "HD %A" status'
                '| None -> printfn "HD unknown"'
            ))
    } 'dotnet apicompat --left a.dll --right b.dll' $all 'feed-codes'

    Invoke-Case 'quoter-needs-a-constructor-argument' {
        param($ws)
        Set-Good $ws
        Edit-Shipping $ws 'let quoteFor (service' 'let private quoteFor (service'
        Edit-Shipping $ws 'let quoteInsured (declaredValue' 'let private quoteInsured (declaredValue'
        Add-Content (Join-Path $ws 'Shipping/Shipping.fs') (($quoterClass -join "`n").Replace('type Quoter() =', 'type Quoter(currency: string) =') -split "`n")
        Set-Content (Join-Path $ws 'NewApp/Program.fs') ($showLines + ($quoterLines -replace 'Quoter\(\)', 'Quoter("EUR")') + @(
                'match statusOf "HD" with'
                '| Some status -> printfn "HD %A" status'
                '| None -> printfn "HD unknown"'
            ))
    } 'dotnet apicompat --left a.dll --right b.dll' @{ build = $true; load = $true; output = $true; compat = $true; newapp = $false }

    Invoke-Case 'two-signature-builds-without-baseline' { param($ws) Set-Good $ws } @('dotnet build Shipping -p:OtherFlags=--sig:a.fsi', 'dotnet build Shipping -p:OtherFlags=--sig:b.fsi') @{ tool = $false }

    Invoke-Case 'same-signature-build-text-in-two-folders' { param($ws) Set-Good $ws } @('cd /work/ws/release-1.0.0/Shipping && dotnet build -p:OtherFlags=--sig:api.fsi', 'cd /work/ws/Shipping && dotnet build -p:OtherFlags=--sig:api.fsi') @{ tool = $true }

    Invoke-Case 'original-input' { param($ws) } 'dotnet build' @{ build = $true; version = $false; load = $true; output = $true; compat = $true; newapp = $false; tool = $false }

    Invoke-Case 'feed-good' { param($ws) Copy-Item (Join-Path $PSScriptRoot 'feed-good/*') $ws -Recurse -Force } 'dotnet apicompat --left a.dll --right b.dll' $all 'feed-codes'

    Invoke-Case 'held-in-new-type-for-shipping' { param($ws) Copy-Item (Join-Path $PSScriptRoot 'feed-new-type/*') $ws -Recurse -Force } 'dotnet apicompat --left a.dll --right b.dll' @{ build = $true; load = $true; output = $true; newapp = $false }

    Invoke-Case 'feed-held-in-new-type' { param($ws) Copy-Item (Join-Path $PSScriptRoot 'feed-new-type/*') $ws -Recurse -Force } 'dotnet apicompat --left a.dll --right b.dll' $all 'feed-codes'

    Invoke-Case 'feed-statusOf-returns-held' { param($ws) Set-Good $ws } 'dotnet apicompat --left a.dll --right b.dll' @{
        build = $true; version = $true; load = $true; output = $false; compat = $true; newapp = $true; tool = $true
    } 'feed-codes'
} finally {
    Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
}

if ($failures.Count) {
    Write-Host "$($failures.Count) grader test(s) failed: $($failures -join ', ')"
    exit 1
}
Write-Host 'All fsharp-binary-compatibility grader tests passed.'
