Set-StrictMode -Version Latest

function New-Check {
    param(
        [Parameter(Mandatory)][string]$Text,
        [AllowNull()][Nullable[bool]]$Passed,
        [string]$Evidence = ''
    )
    [pscustomobject]@{ text = $Text; passed = $Passed; evidence = $Evidence }
}

function Write-Checks {
    param([Parameter(Mandatory)][string]$ResultPath, [object[]]$Checks)
    ConvertTo-Json -InputObject @($Checks) -Depth 5 | Set-Content -Path $ResultPath -Encoding utf8
}

function Read-AnswerJson {
    param([Parameter(Mandatory)][string]$Workspace)
    $path = Join-Path $Workspace 'answer.json'
    if (-not (Test-Path $path)) { return $null }
    try { Get-Content -Raw $path | ConvertFrom-Json } catch { $null }
}

function Get-AgentFiles {
    param([Parameter(Mandatory)][string]$Workspace, [string[]]$Include = @('*.fs', '*.fsx', '*.cs'))
    Get-ChildItem -Path $Workspace -Recurse -File -Include $Include |
        Where-Object { $_.FullName -notmatch '[\\/](\.claude|\.agents|\.opencode|\.git|bin|obj)[\\/]' }
}

function Copy-Workspace {
    param([Parameter(Mandatory)][string]$Workspace, [Parameter(Mandatory)][string]$Destination)
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    $root = (Resolve-Path $Workspace).Path
    Get-ChildItem -Path $root -Recurse -File -Force |
        Where-Object { $_.FullName.Substring($root.Length) -notmatch '^[\\/]?(\.claude|\.agents|\.opencode|\.git)[\\/]|[\\/](bin|obj)[\\/]' } |
        ForEach-Object {
            $target = Join-Path $Destination $_.FullName.Substring($root.Length).TrimStart('\', '/')
            New-Item -ItemType Directory -Force -Path (Split-Path $target) | Out-Null
            Copy-Item $_.FullName $target
        }
}

function Invoke-Capture {
    param([Parameter(Mandatory)][string]$FilePath, [string[]]$Arguments = @(), [string]$WorkingDirectory = $PWD.Path)
    Push-Location $WorkingDirectory
    try {
        $output = & $FilePath @Arguments 2>&1 | ForEach-Object { "$_" }
        [pscustomobject]@{ ExitCode = $LASTEXITCODE; Lines = @($output); Text = ($output -join "`n") }
    } finally {
        Pop-Location
    }
}

function Get-RuntimeId { [System.Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier }

# dotnet selects its SDK from global.json above the working directory, so each command runs in the project directory.
function Invoke-JitAndNative {
    param(
        [Parameter(Mandatory)][string]$Project,
        [Parameter(Mandatory)][string]$OutRoot,
        [switch]$SkipNative
    )
    $name = [IO.Path]::GetFileNameWithoutExtension($Project)
    $dir = Split-Path (Resolve-Path $Project).Path
    $result = [ordered]@{ Built = $false; BuildLog = ''; Jit = $null; Published = $null; PublishLog = ''; Native = $null }

    $build = Invoke-Capture dotnet @('build', $Project, '-c', 'Release', '-o', (Join-Path $OutRoot 'jit')) -WorkingDirectory $dir
    $result.BuildLog = $build.Text
    if ($build.ExitCode -ne 0) { return [pscustomobject]$result }
    $result.Built = $true
    $result.Jit = Invoke-Capture dotnet @((Join-Path $OutRoot "jit/$name.dll")) -WorkingDirectory $dir

    if ($SkipNative) { return [pscustomobject]$result }
    $aot = Invoke-Capture dotnet @('msbuild', $Project, '-getProperty:PublishAot', '-p:Configuration=Release', "-p:RuntimeIdentifier=$(Get-RuntimeId)") -WorkingDirectory $dir
    if ($aot.ExitCode -ne 0) {
        $result.Published = $false
        $result.PublishLog = "MSBuild could not evaluate PublishAot.`n$($aot.Text)"
        return [pscustomobject]$result
    }
    if ($aot.Text.Trim() -ne 'true') {
        $result.Published = $false
        $result.PublishLog = "The project does not set PublishAot to true for Release. Evaluated value: '$($aot.Text.Trim())'."
        return [pscustomobject]$result
    }
    $publish = Invoke-Capture dotnet @('publish', $Project, '-c', 'Release', '-r', (Get-RuntimeId), '-o', (Join-Path $OutRoot 'native')) -WorkingDirectory $dir
    $result.PublishLog = $publish.Text
    $result.Published = $publish.ExitCode -eq 0
    if ($result.Published) {
        $exe = Join-Path $OutRoot ('native/' + $name + $(if ($IsWindows) { '.exe' } else { '' }))
        $result.Native = Invoke-Capture $exe -WorkingDirectory $dir
    }
    [pscustomobject]$result
}

function Get-LastLines {
    param([string]$Text, [int]$Count = 15)
    (($Text -split "`n") | Select-Object -Last $Count) -join "`n"
}

Export-ModuleMember -Function New-Check, Write-Checks, Read-AnswerJson, Get-AgentFiles, Copy-Workspace,
    Invoke-Capture, Get-RuntimeId, Invoke-JitAndNative, Get-LastLines
