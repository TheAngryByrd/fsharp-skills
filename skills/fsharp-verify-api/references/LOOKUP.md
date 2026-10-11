# API lookup methods

Use the first method that answers the question. Each method runs without a project build.

## 1. Find the version in use

```powershell
rg -n 'PackageReference|PackageVersion' -g '*.fsproj' -g 'Directory.Packages.props'
rg -n '^\s+FsToolkit.ErrorHandling ' paket.lock
```

With central package management, the `.fsproj` has no `Version`. The version is in `Directory.Packages.props`.

## 2. List the signatures

```powershell
pwsh <skill-root>/scripts/show-api.ps1 -Package <id> -Version <version> -Type <type-name-part> -Member <member-name-part>
```

The script writes a temporary `.fsx` with `#r "nuget: <id>, <version>"` and prints the public API through reflection.
Output lines:

- `ASSEMBLY <name> <version>`: the loaded assembly.
- `TYPE <full name>`: the namespace for the `open` line.
- `new Type(param: Type)`: a constructor.
- `Name<'T>(param: Type) : Return`: a method. `static` marks static methods.
- `Name : Type with get, set`: a property. `with get` only means it has no public setter. `Item[index: Int32]` is an indexer.
- `extension Name(param: Type) : Return  (from Holder)`: an extension method on the type. The `open` line needs the namespace of `Holder`.
- `(from Base)`: an inherited member.
- `NO TYPE matches`, `NO MEMBER matches`, or `NOT LOADED`: the type, the member, or the assembly does not exist in that version.

F# module functions show their F# source name, for example `static tryHead<'T>(list: FSharpList<'T>)` for `List.tryHead`.
A module that has the same name as a type has the `Module` suffix in its type name, for example `Microsoft.FSharp.Collections.ListModule`.
For `FSharp.Core`, omit `-Version`. FSI rejects `#r "nuget: FSharp.Core"` with FS0999, so the script lists the `FSharp.Core` that FSI runs on.

C# property initializers become F# named arguments on the constructor call:

```fsharp
// Listing: new HttpClient(), Timeout : TimeSpan with get, set
let client = new System.Net.Http.HttpClient(Timeout = System.TimeSpan.FromSeconds 5.0)
```

## 3. Read the XML docs in the NuGet cache

The package folder holds an XML doc file next to each assembly:

```powershell
$xml = "$env:USERPROFILE/.nuget/packages/fstoolkit.errorhandling/5.2.0/lib/netstandard2.1/FsToolkit.ErrorHandling.xml"
Select-String -Path $xml -Pattern 'name="M:FsToolkit.ErrorHandling.Result.requireSome' -Context 0,4
```

On Linux and macOS the cache is `~/.nuget/packages`. `NUGET_PACKAGES` moves it.
Folder names are lowercase. The `name` attribute prefix tells the member kind: `T:` type, `M:` method or constructor (`#ctor`), `P:` property.
The `<summary>` text often names the replacement for a removed member.

## 4. Read the metadata of an assembly without a package

For a local `.dll`, use reflection in a script file. Run it with `dotnet fsi probe.fsx`:

```fsharp
let asm = System.Reflection.Assembly.LoadFrom "/path/to/Library.dll"
for t in asm.GetExportedTypes() do
    if t.Name.Contains "Client" then
        for m in t.GetMembers() do printfn "%s.%s" t.FullName (string m)
```

For a full C# view, `ilspycmd` decompiles an assembly: `ilspycmd -t Namespace.Type Library.dll`. Install it only when the project already uses it.

## 5. Search the codebase for an existing helper

```powershell
rg -n 'let (inline )?\w*(parse|try|to|from)\w*' -g '*.fs'
rg -n ': Result<Email' -g '*.fs'
```

Search by the result type, by the input type, and by the verb. Reviewers reject a new helper that duplicates one in a shared module.

## `.fsx` rules

| Rule | Failure when broken |
|---|---|
| A relative `#r "lib/X.dll"` resolves from the script's directory. | FS0078 when you run the script from another directory and the path is relative to that directory. |
| `#r "nuget: X"` without a version loads the latest stable version. | The script compiles against a different API than the project. Pin `#r "nuget: X, 2.0.0"`. |
| `#r` and `#load` belong in `.fsx` files. | A project gets its references from `PackageReference` and `ProjectReference` items, not from `#r` lines. |
| `#r "nuget: FSharp.Core"` is rejected. | FS0999. FSI uses its own `FSharp.Core`. |
| `dotnet fsi` selects the SDK from `global.json` above the working directory. | An older SDK gives an older F# compiler, for example F# 8 under a parent `global.json` for SDK 8. Run `dotnet --version` in that directory. |

`#r "nuget: ..."` works in a non-interactive run (`dotnet fsi script.fsx`) on SDK 8 and SDK 10. The first run restores the package and takes longer.
