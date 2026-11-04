#Requires -Version 7.4
$ErrorActionPreference = 'Stop'

$root = Join-Path ([IO.Path]::GetTempPath()) "serialization-grader-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
$failures = [System.Collections.Generic.List[string]]::new()

function Invoke-Case {
    param([string]$Name, [string]$Codec, [scriptblock]$Edit)
    $ws = Join-Path $root "$Name/ws"
    $out = Join-Path $root "$Name/grade"
    New-Item -ItemType Directory -Force -Path $ws, $out | Out-Null
    Copy-Item (Join-Path $PSScriptRoot '../inputs/billing/*') $ws -Recurse -Force
    if ($Codec) { Copy-Item (Join-Path $PSScriptRoot "$Codec/Codec.fsx") $ws }
    if ($Edit) { & $Edit $ws }
    & (Join-Path $PSScriptRoot '../graders/billing-codec.ps1') -Workspace $ws -OutDir $out
    @(Get-Content -Raw (Join-Path $out 'grading.json') | ConvertFrom-Json)
}

function Assert-Checks {
    param([string]$Case, $Checks, [hashtable]$Expected)
    $actual = @{}
    foreach ($c in $Checks) { $actual[$c.text] = $c.passed }
    $wrong = @($Expected.Keys | Where-Object { -not $actual.ContainsKey($_) -or $actual[$_] -ne $Expected[$_] })
    $extra = @($actual.Keys | Where-Object { -not $Expected.ContainsKey($_) })
    if ($wrong.Count -gt 0 -or $extra.Count -gt 0) {
        $detail = ($Checks | ForEach-Object { "  [$($_.passed)] $($_.text) $($_.evidence)" }) -join "`n"
        $failures.Add("${Case}: unexpected checks: $($wrong + $extra -join '; ')`n$detail")
    }
}

$names = @(
    'Domain.fsx is unchanged'
    'The codec uses JsonSerializer and does not read or write JSON by hand'
    'Codec.fsx and the probe compile together'
    'order-card.json decodes to the expected order'
    'The card order encodes to the order-card.json shape'
    'order-cash.json decodes to the expected order'
    'The cash order encodes to the order-cash.json shape'
    'order-gift-card.json decodes to the expected order and ignores the unknown property'
    'The gift card order encodes to the order-gift-card.json shape without the unknown property'
    'Optional properties sent as null decode to None'
    'A null discount decodes to None'
    'Unknown properties in a line and in the payment are ignored'
    'A missing required id returns Error'
    'A null required id returns Error'
    'A line without quantity returns Error'
    'A missing lines property returns Error'
    'A missing reserved property returns Error'
    'A null reserved property returns Error'
    'An unknown payment kind returns Error'
    'An unknown status returns Error'
    'The JSON null returns Error'
    'Malformed JSON returns Error'
    'No encoded order has a Case or Fields property'
    'Stored customer ann.json decodes to the same customer'
    'encodeCustomer still writes the ann.json shape'
    'Stored customer bo.json decodes to the same customer'
    'encodeCustomer still writes the bo.json shape'
)

function New-Expected([string[]]$Failing) {
    $h = @{}
    foreach ($n in $names) { $h[$n] = $n -notin $Failing }
    $h
}

try {
    Assert-Checks 'good' (Invoke-Case 'good' 'good') (New-Expected @())
    Assert-Checks 'module Codec =' (Invoke-Case 'module-wrapper' 'module-wrapper') (New-Expected @())
    Assert-Checks 'DTO layer' (Invoke-Case 'dto' 'dto') (New-Expected @())

    $testsFile = {
        param($ws)
        Set-Content (Join-Path $ws 'Tests.fsx') "#load ""Codec.fsx""`nopen System.Text.Json.Nodes`nlet same (a: string) (b: string) = JsonNode.DeepEquals(JsonNode.Parse a, JsonNode.Parse b)"
        Add-Content (Join-Path $ws 'Codec.fsx') ("`nlet private regressionJson = " + '"""{"note":"JsonNode // (* JsonDocument"}"""' + "`nlet private script = " + '"""' + "`n#load ""Tests.fsx""`n" + '"""' + "`nlet private label = ""JsonElement""`n// Do not parse JSON by hand with JsonDocument.`n(* JsonNode is not used here. Example:`n#load ""Tests.fsx""`n*)`n// #load ""Tests.fsx""")
        $codec = Join-Path $ws 'Codec.fsx'
        Set-Content (Join-Path $ws 'JsonNode.fsx') "module JsonNodeNames`nlet sample = 1"
        Set-Content $codec ((Get-Content -Raw $codec).Replace('#load "Domain.fsx"', "#load ""Domain.fsx"" // See ""Tests.fsx"" for JsonNode comparisons.`n#load ""JsonNode.fsx"""))
    }
    Assert-Checks 'JsonNode in a test file, comments, and strings' (Invoke-Case 'tests-file' 'good' $testsFile) (New-Expected @())

    $strictLines = {
        param($ws)
        $codec = Join-Path $ws 'Codec.fsx'
        Set-Content $codec ((Get-Content -Raw $codec) -replace '\[<CLIMutable>\]\r?\ntype LineDto', "[<CLIMutable; JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)>]`ntype LineDto")
    }
    Assert-Checks 'DTO that rejects unknown line properties' (Invoke-Case 'strict-lines' 'dto' $strictLines) (New-Expected @('Unknown properties in a line and in the payment are ignored'))

    $emptyReserved = {
        param($ws)
        $codec = Join-Path $ws 'Codec.fsx'
        Set-Content $codec ((Get-Content -Raw $codec).Replace('required "reserved" dto.Reserved', 'Ok(if isNull dto.Reserved then Dictionary<int, int>() else dto.Reserved)'))
    }
    Assert-Checks 'DTO that reads a missing reserved as empty' (Invoke-Case 'empty-reserved' 'dto' $emptyReserved) (New-Expected @('A missing reserved property returns Error', 'A null reserved property returns Error'))

    $exnCustomer = {
        param($ws)
        $codec = Join-Path $ws 'Codec.fsx'
        $text = (Get-Content -Raw $codec).Replace('let decodeCustomer (json: string) : Result<Customer, string> =', 'let decodeCustomer (json: string) : Result<Customer, exn> =')
        $text = $text.Replace("Ok(JsonSerializer.Deserialize<Customer>(json, options))`n    with :? JsonException as ex ->`n        Error ex.Message", "Ok(JsonSerializer.Deserialize<Customer>(json, options))`n    with :? JsonException as ex ->`n        Error(ex :> exn)")
        Set-Content $codec $text
    }
    Assert-Checks 'decodeCustomer with an exn error' (Invoke-Case 'exn-customer' 'good' $exnCustomer) @{ ($names[0]) = $true; ($names[1]) = $true; ($names[2]) = $false }

    Assert-Checks 'original input' (Invoke-Case 'input') (New-Expected (@($names[3..11]) + 'No encoded order has a Case or Fields property'))

    $noCodec = { param($ws) Remove-Item (Join-Path $ws 'Codec.fsx') }
    Assert-Checks 'no Codec.fsx' (Invoke-Case 'no-codec' -Edit $noCodec) @{ ($names[0]) = $true; ($names[2]) = $false }

    $editedDomain = { param($ws) Add-Content (Join-Path $ws 'Domain.fsx') "`ntype Extra = { X: int }" }
    Assert-Checks 'edited Domain.fsx' (Invoke-Case 'edited-domain' 'good' $editedDomain) (New-Expected @($names[0]))

    $jsonObject = { param($ws) Add-Content (Join-Path $ws 'Codec.fsx') "`nlet private probe = JsonSerializer.Deserialize<System.Text.Json.Nodes.JsonObject>(""{}"")" }
    Assert-Checks 'JsonObject' (Invoke-Case 'json-object' 'good' $jsonObject) (New-Expected @($names[1]))

    $loadedHelper = {
        param($ws)
        Set-Content (Join-Path $ws 'Helpers.fsx') "module Helpers`nlet kindOf (json: string) = System.Text.Json.JsonDocument.Parse(json).RootElement.ToString()"
        $codec = Join-Path $ws 'Codec.fsx'
        Set-Content $codec ((Get-Content -Raw $codec) -replace '#load "Domain.fsx"', "#load ""Domain.fsx""`n#load ""Helpers.fsx""")
    }
    Assert-Checks 'JsonDocument in a loaded file' (Invoke-Case 'loaded-helper' 'good' $loadedHelper) (New-Expected @($names[1]))

    $verbatimHelper = {
        param($ws)
        & $loadedHelper $ws
        $codec = Join-Path $ws 'Codec.fsx'
        Set-Content $codec ((Get-Content -Raw $codec).Replace('#load "Helpers.fsx"', '#load @"Helpers.fsx"'))
    }
    Assert-Checks 'JsonDocument in a file loaded with a verbatim path' (Invoke-Case 'verbatim-helper' 'good' $verbatimHelper) (New-Expected @($names[1]))

    Assert-Checks 'one options value for both types' (Invoke-Case 'one-options' 'one-options') (New-Expected @(
            'Stored customer ann.json decodes to the same customer'
            'encodeCustomer still writes the ann.json shape'
            'Stored customer bo.json decodes to the same customer'
            'encodeCustomer still writes the bo.json shape'
        ))

    Assert-Checks 'WhenWritingNull' (Invoke-Case 'when-writing-null' 'when-writing-null') (New-Expected @(
            'A missing required id returns Error'
            'A line without quantity returns Error'
            'A missing reserved property returns Error'
        ))

    Assert-Checks 'default skippable options' (Invoke-Case 'skippable-default' 'skippable-default') (New-Expected @(
            'Optional properties sent as null decode to None'
            'A null discount decodes to None'
        ))
} finally {
    Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Host $_ }
    exit 1
}
Write-Host 'All grader cases passed.'
