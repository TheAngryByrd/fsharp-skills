#Requires -Version 7.4
param(
    [Parameter(Mandatory)][string]$Workspace,
    [Parameter(Mandatory)][string]$OutDir,
    [switch]$SkipNative
)
& (Join-Path $PSScriptRoot 'shipping-1-1.ps1') -Workspace $Workspace -OutDir $OutDir -SkipNative:$SkipNative `
    -LegacySource (Join-Path $PSScriptRoot 'hidden/Program.fs') -AppName 'A customer app' -StatusOfReturnsHeld $false
