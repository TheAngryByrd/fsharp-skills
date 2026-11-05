function Get-AssemblyVersion([string]$Path) {
    try { [Reflection.AssemblyName]::GetAssemblyName($Path).Version } catch { [version]'0.0' }
}

function Get-FileVersion([string]$Path) {
    $info = [Diagnostics.FileVersionInfo]::GetVersionInfo($Path)
    [version]::new($info.FileMajorPart, $info.FileMinorPart, $info.FileBuildPart, $info.FilePrivatePart)
}

function Get-PackageVersions([string]$DepsJson) {
    $versions = @{}
    if (-not (Test-Path $DepsJson)) { return $versions }
    $deps = Get-Content -Raw $DepsJson | ConvertFrom-Json -AsHashtable
    foreach ($target in $deps.targets.Values) {
        foreach ($id in $target.Keys) {
            $library = $deps.libraries[$id]
            if (-not $library -or $library.type -ne 'package' -or -not $target[$id].runtime) { continue }
            $version = $id.Substring($id.IndexOf('/') + 1)
            foreach ($path in $target[$id].runtime.Keys) { $versions[[IO.Path]::GetFileName($path)] = $version }
        }
    }
    $versions
}

function Compare-PackageVersion([string]$Left, [string]$Right) {
    $parse = {
        param([string]$Version)
        $core, $pre = ($Version -split '\+', 2)[0] -split '-', 2
        $parts = @($core -split '\.' | ForEach-Object { [int]$_ }) + @(0, 0, 0, 0)
        [pscustomobject]@{ Core = [version]::new($parts[0], $parts[1], $parts[2], $parts[3]); Pre = @(if ($pre) { $pre -split '\.' }) }
    }
    $a = & $parse $Left
    $b = & $parse $Right
    $result = $a.Core.CompareTo($b.Core)
    if ($result -ne 0) { return $result }
    if ($a.Pre.Count -eq 0 -or $b.Pre.Count -eq 0) { return $b.Pre.Count.CompareTo(0) - $a.Pre.Count.CompareTo(0) }
    for ($i = 0; $i -lt [Math]::Min($a.Pre.Count, $b.Pre.Count); $i++) {
        $x = $a.Pre[$i]; $y = $b.Pre[$i]
        $xNumber = $x -match '^\d+$'; $yNumber = $y -match '^\d+$'
        $result = if ($xNumber -and $yNumber) { ([long]$x).CompareTo([long]$y) }
            elseif ($xNumber -ne $yNumber) { if ($xNumber) { -1 } else { 1 } }
            else { [string]::Compare($x, $y, [StringComparison]::OrdinalIgnoreCase) }
        if ($result -ne 0) { return [Math]::Sign($result) }
    }
    $a.Pre.Count.CompareTo($b.Pre.Count)
}

# A package upgrade can keep the assembly version (FSharp.Core 10.0.113 and 10.0.114 are both 10.0.0.0), so the package version decides first.
function Test-NewerDependency {
    param([Parameter(Mandatory)][string]$NewDll, [Parameter(Mandatory)][string]$OldDll, [hashtable]$NewPackages = @{}, [hashtable]$OldPackages = @{})
    if (-not (Test-Path $OldDll)) { return $true }
    $name = [IO.Path]::GetFileName($NewDll)
    if ($NewPackages.ContainsKey($name) -and $OldPackages.ContainsKey($name)) { return (Compare-PackageVersion $NewPackages[$name] $OldPackages[$name]) -gt 0 }
    $result = (Get-AssemblyVersion $NewDll).CompareTo((Get-AssemblyVersion $OldDll))
    if ($result -ne 0) { return $result -gt 0 }
    (Get-FileVersion $NewDll) -gt (Get-FileVersion $OldDll)
}

Export-ModuleMember -Function Get-PackageVersions, Test-NewerDependency
