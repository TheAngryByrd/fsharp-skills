#Requires -Version 7.2
param(
    [Parameter(Mandatory)][string]$Package,
    [string]$Version = '',
    [string]$Type = '',
    [string]$Member = '',
    [string]$Assembly = $Package
)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

function ConvertTo-FSharpString([string]$Value) { '"' + $Value.Replace('\', '\\').Replace('"', '\"') + '"' }

$dir = Join-Path ([IO.Path]::GetTempPath()) "show-api-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
New-Item -ItemType Directory -Path $dir | Out-Null
$probe = Join-Path $dir 'probe.fsx'
$showApi = (Join-Path $PSScriptRoot 'ShowApi.fsx').Replace('\', '/')
# FSI rejects '#r "nuget: FSharp.Core"' (FS0999) and lists the FSharp.Core that it runs on.
$reference = if ($Package -eq 'FSharp.Core') { '' } elseif ($Version) { "#r `"nuget: $Package, $Version`"" } else { "#r `"nuget: $Package`"" }
@(
    $reference
    "#load `"$showApi`""
    "ShowApi.print $(ConvertTo-FSharpString $Assembly) $(ConvertTo-FSharpString $Type) $(ConvertTo-FSharpString $Member)"
) | Set-Content -Path $probe -Encoding utf8

# dotnet selects its SDK from global.json above the working directory.
Push-Location $PSScriptRoot
try {
    dotnet fsi --nologo $probe 2>&1 | ForEach-Object { "$_" }
    $exitCode = $LASTEXITCODE
} finally {
    Pop-Location
    Remove-Item -Recurse -Force $dir -ErrorAction SilentlyContinue
}
exit $exitCode

