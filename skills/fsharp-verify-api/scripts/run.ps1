#Requires -Version 7.2
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$failures = 0
function Assert-Output {
    param([string]$Name, [string[]]$Lines, [string]$Pattern, [bool]$Present)
    $found = @($Lines | Where-Object { $_ -match $Pattern }).Count -gt 0
    if ($found -eq $Present) {
        "PASS $Name"
    } else {
        "FAIL $Name"
        $script:failures++
    }
}
function Show-Api { & (Join-Path $PSScriptRoot 'show-api.ps1') @args }

$old = @(Show-Api -Package Expecto -Version 10.2.3 -Type Expecto.Expect -Member floatClose)
$old
Assert-Output 'Expecto 10.2.3 loads' $old '^ASSEMBLY Expecto 10\.2\.3' $true
Assert-Output 'Expecto 10 floatClose takes a non-generic Accuracy' $old '^\s+static floatClose\(accuracy: Accuracy, ' $true

$new = @(Show-Api -Package Expecto -Version 11.1.1 -Type Expecto.Expect -Member floatClose)
$new
Assert-Output 'Expecto 11.1.1 loads' $new '^ASSEMBLY Expecto 11\.1\.1' $true
Assert-Output 'Expecto 11 floatClose takes Accuracy<Double, Double>' $new '^\s+static floatClose\(accuracy: Accuracy<Double, Double>, ' $true
Assert-Output 'Expecto 11 has no non-generic Accuracy overload' $new '^\s+static floatClose\(accuracy: Accuracy, ' $false

$missing = @(Show-Api -Package Expecto -Version 11.1.1 -Type Expecto.NoSuchType)
Assert-Output 'A missing type is reported' $missing '^NO TYPE matches' $true

$noMember = @(Show-Api -Package Expecto -Version 11.1.1 -Type Expecto.Expect -Member NoSuchMember)
Assert-Output 'A missing member is reported' $noMember '^\s+NO MEMBER matches' $true

$fsharp = @(Show-Api -Package FSharp.Core -Type Microsoft.FSharp.Collections.ListModule -Member tryHead)
$fsharp
Assert-Output 'F# module functions show their source name' $fsharp '^\s+static tryHead<' $true

$array2d = @(Show-Api -Package FSharp.Core -Type Microsoft.FSharp.Collections.Array2DModule -Member copy)
Assert-Output 'Multidimensional arrays keep their rank' $array2d "^\s+static copy<'T>\(array: 'T\[,\]\) : 'T\[,\]" $true

$extension = @(Show-Api -Package Microsoft.Extensions.DependencyInjection.Abstractions -Version 8.0.2 -Type Microsoft.Extensions.DependencyInjection.IServiceCollection -Member AddSingleton)
Assert-Output 'Extension methods show on the extended type' $extension '^\s+extension AddSingleton<' $true

$inherited = @(Show-Api -Package Microsoft.Extensions.DependencyInjection.Abstractions -Version 8.0.2 -Type Microsoft.Extensions.DependencyInjection.IServiceCollection -Member '')
Assert-Output 'Interfaces show members of their base interfaces' $inherited '^\s+Count : Int32 with get\s+\(from ICollection<' $true
Assert-Output 'Indexers show their index parameters' $inherited '^\s+Item\[index: Int32\] : ServiceDescriptor with get, set' $true

$nested = @(Show-Api -Package System.Collections.Immutable -Version 8.0.0 -Type 'System.Collections.Immutable.ImmutableArray`1' -Member GetEnumerator)
Assert-Output 'Nested generic types show their names' $nested '^\s+GetEnumerator\(\) : Enumerator' $true

if ($failures -gt 0) { throw "$failures API checks failed." }
