---
name: fsharp-library-api-design
description: Design and change the public API of an F# library without breaking its consumers. Covers F#-specific breaking changes (new union cases, new record fields, curried and tupled forms, generic and inline functions, RequireQualifiedAccess, renamed modules), binary breaks that a clean build does not show (a new optional parameter, a wider parameter type, cross-assembly inlining of a small function body into Release consumers, --nooptimizationdata), safe extension patterns (overloads, new functions), a C#-friendly surface, SemVer for each change type, the lowest FSharp.Core version, and compatibility checks with package validation and old consumers. Use when the user adds to or changes a published F# library, asks whether a change is breaking, picks a version number, or exposes F# code to C#.
compatibility: The proof runner requires the .NET 10 SDK, PowerShell 7.4 or later, and NuGet access. Results were verified with SDK 10.0.403 on win-x64.
---

# F# library API design

A published library has two contracts:

- **Source compatibility:** F# and C# code that compiled against 1.0.0 compiles against 1.1.0.
- **Binary compatibility:** an assembly that was compiled against 1.0.0 runs with 1.1.0.
  NuGet gives this case often. When package A was built against 1.0.0 and the app needs 1.1.0, A runs with 1.1.0 and is not compiled again.

A minor or patch version must keep both contracts. A new overload on a type member is the one exception when it makes no existing call ambiguous. It breaks a C# method group with no delegate type. A clean build of every consumer that you can see proves only source compatibility.
Many F# breaking changes do not look like breaking changes. Some are source-only, and package validation does not report them.

## Changes and their results

Each row is a change to version 1.0.0 that [scripts/run.ps1](scripts/run.ps1) proves. "Source" rebuilds an F# and a C# consumer with `TreatWarningsAsErrors`. FS0025, FS0044, and CS0618 are warnings that this setting makes errors. "Binary" runs a consumer that was compiled against 1.0.0 with the new DLL.

| Change | F# source | C# source | Binary | Package validation |
|---|---|---|---|---|
| New union case | FS0025 | ok | ok until a new case reaches old code | not reported |
| New record field | FS0764 | CS7036 | MissingMethodException | CP0002 |
| Curried function made tupled | FS0001 | ok | ok | not reported |
| `[<RequireQualifiedAccess>]` added | FS0039, and FS0025 in a match | ok | ok | not reported |
| `inline` body changed, with or without `--nooptimizationdata` | ok | ok | old body runs in F# until rebuild | not reported |
| Small function body changed | ok | ok | old body runs in F# until rebuild | not reported |
| Small function body changed, `--nooptimizationdata` in 1.0.0 and 1.1.0 | ok | ok | new body runs | not reported |
| Parameter made generic (`int list` to `'T list`) | ok | ok | MissingMethodException | CP0002 |
| Parameter type widened (`int list` to `seq<int>`) | ok | ok | MissingMethodException | CP0002 |
| `[<Optional; DefaultParameterValue>]` parameter added to an existing member | ok | ok | MissingMethodException | CP0002 |
| F# `?x` parameter added to an existing member | ok | CS7036 | MissingMethodException | CP0002 |
| Member added to a public interface | FS0366 | CS0535 | TypeLoadException | CP0006 |
| Module renamed | FS0039 | CS0103 | TypeLoadException | CP0001 |
| `[<CompiledName>]` added to an existing function | ok | CS0117 | MissingMethodException, except in a Release F# consumer that used cross-assembly inlining of a small body | CP0002 |
| `[<Obsolete>]` on a function | FS0044 | CS0618 | ok | not reported |
| New overload on a type member (`seq<int>` beside `int list`, or one more parameter) | ok | CS8917 for a method group such as `var total = client.Total;` | ok | ok |
| New overload with an unrelated reference type (`Send(System.Uri)` beside `Send(string)`) | FS0041 for an unannotated function parameter | CS0121 for `client.Send(null)` | ok | ok |

Read [references/CHANGES.md](references/CHANGES.md) for each change with its code and its safe alternative.

## Rules

- **Extend. Do not change.** Do not change the signature of a public function or member in a minor version. This includes a new optional parameter and a wider or generic parameter type. Add an overload on a type member, or add a new function next to the old one.
- **Check overload resolution.** A new overload must not make an existing call ambiguous. When neither parameter type is a subtype of the other, as with `Uri` and `string`, a call that both accept is ambiguous. C# `client.Send(null)` then fails with CS0121. An F# call fails with FS0041 when the argument type is not known before the call, such as an unannotated function parameter. Use a new member name instead, or test these call shapes in an F# and a C# consumer, including `null` and a numeric literal.
- **Overloads need a type.** A module function cannot have an overload. To give a module function a new parameter, add a function with a new name. Mark the old one `[<Obsolete("Use X.")>]` only in a major version. A consumer with `TreatWarningsAsErrors` fails with FS0044 or CS0618.
- **Records:** a new field removes the old constructor and breaks each consumer that builds the record, including test code. When a record must grow, plan for it in the first version: expose a `create` function or a class with members. Use [fsharp-signature-files](../fsharp-signature-files/SKILL.md) to hide a representation.
- **Unions:** a new case is a breaking change for each consumer that matches on the union. Old binaries throw `MatchFailureException` when they get the new case. Release a new case in a major version, or hide the representation before the first release.
- **Interfaces:** do not add a member to a public interface. Add a new interface that inherits the old one, for example `IStore2`, and test for it at run time with `:?`.
- **Curried and tupled:** keep the form of each public function. A change compiles to the same method, so package validation does not see it, but F# callers fail.
- **`inline`:** an `inline` body is compiled into each caller. A fix in the body reaches a consumer only when the consumer builds again, also with `--nooptimizationdata`. Use `inline` on a public function only when it needs statically resolved type parameters.
- **Small function bodies:** Release builds also copy small non-`inline` functions through cross-assembly inlining. The F# compiler puts optimization data in the library DLL, and an F# consumer that is built in Release copies small public function bodies from it. An old consumer then keeps the old body. C# consumers do not copy bodies. A library that must take body fixes with no consumer rebuild needs `--nooptimizationdata` from its first release:

  ```xml
  <OtherFlags>$(OtherFlags) --nooptimizationdata</OtherFlags>
  ```

  The flag does not change consumers that were compiled against an earlier DLL that had optimization data. Without cross-assembly inlining, consumer code can be slower. `inline` functions are still copied with the flag. Decide this before the first release.
- **Names:** a renamed module, type, or function and a new `[<RequireQualifiedAccess>]` break callers. Add the new name and keep the old one.

## C#-friendly surface

Apply these rules to new public members that C# can call:

- Do not use F#-only types in parameters: `option`, `voption`, `list`, `Map`, `Set`, function types, and `Async`. C# must then build these values with FSharp.Core. Use `seq<'T>`, arrays, `IReadOnlyList<'T>`, delegates such as `Func<'T, 'U>`, and `null` or an overload for an absent value.
- Do not return `option`, `voption`, function types, or `Async` to C#. For an absent result, return `null`, or use a `TryX` method with an `outref` parameter. Return a delegate instead of an F# function and `Task<'T>` instead of `Async<'T>`. A returned `list`, `Map`, or `Set` works in C# as a .NET collection, but `IReadOnlyList<'T>` or an array is easier to use.
- An F# `?x` parameter is an `FSharpOption<T>` parameter in C#, and C# must pass it. For a parameter that C# can leave out, use `[<Optional; DefaultParameterValue(...)>]` on a new member only.
- Use `[<CompiledName("PascalCase")>]` on a new module function that C# calls. Do not add `CompiledName` to an existing function, because it renames the compiled method.
- Return `Task<'T>` at the boundary. Keep `Async<'T>` for F# callers in a separate function or module.

## Versioning

Use SemVer for each change type:

| Version | Allowed changes |
|---|---|
| Major | Any break in the table above, in F# source, C# source, or binary form. This includes a new `[<Obsolete>]`, because a consumer with `TreatWarningsAsErrors` fails. A new overload that makes no existing call ambiguous is the exception: it stays minor, and the release notes name it. |
| Minor | New types, new functions, new overloads that make no existing call ambiguous, and new members on classes. |
| Patch | Fixes that do not change the public surface. A fix to an `inline` body, or to a small function body without `--nooptimizationdata`, reaches F# callers only when they build again. Say so in the release notes. |

Set the lowest FSharp.Core version that the library needs. By default, the package depends on the FSharp.Core version of the SDK (10.1.403 with SDK 10.0.403), and each consumer must then use that version or a later one. The proof pins FSharp.Core 6.0.7 in a `netstandard2.0` library. An older FSharp.Core can lack functions that the code uses, so build the library with the pin:

```xml
<ItemGroup>
  <PackageReference Update="FSharp.Core" Version="6.0.7" />
</ItemGroup>
```

A higher minimum FSharp.Core forces consumers to upgrade. Name each increase in the release notes.

## Steps

1. Before the change, record the public surface of the built library. If [fsharp-signature-files](../fsharp-signature-files/SKILL.md) is installed, use its `public-surface.ps1`. Keep the output as a snapshot file. Without that script, use package validation in step 3 as the surface check.
2. List each public change that the request needs. Find its row in the table. If a row breaks a contract, use the safe alternative from [references/CHANGES.md](references/CHANGES.md), or make the version major.
3. Turn on package validation against the last released version and pack:

   ```xml
   <PropertyGroup>
     <EnablePackageValidation>true</EnablePackageValidation>
     <PackageValidationBaselineVersion>1.0.0</PackageValidationBaselineVersion>
   </PropertyGroup>
   ```

   `dotnet pack` then fails with CP0001, CP0002, or CP0006 when a type or member signature of 1.0.0 is gone or changed. It does not report F#-only source breaks, a new union case, or a changed function body.
4. Check both contracts with the consumers that you have:
   - Source: build each F# and C# consumer, with its tests, against the new library. For a new overload, also build the call shapes from the overload rule above.
   - Binary: build each consumer against the old version. Copy the new library DLL, and each new dependency DLL, into its output folder. Run the consumer. The output must not change.
5. Compare the public surface with the snapshot. Each removed or changed line is a break. Each added line that C# calls must follow the C#-friendly rules above.
6. Set the version and write a release notes entry that names each addition, each `[<Obsolete>]`, and each FSharp.Core change.

## Verify

Run the proof runner from the skill root:

```powershell
pwsh ./scripts/run.ps1
```

The runner packs [scripts/V1](scripts/V1) as the 1.0.0 baseline. For each folder in [scripts/changes](scripts/changes), it packs the changed library with package validation. It builds the F# and C# consumers against it, and runs the 1.0.0 consumers with the new DLL. A `// flags:` line in a change gives compiler flags to the 1.0.0 and the changed library. It compares each result with the `// expect-` lines of the change and exits with code 1 on a difference. It also checks the FSharp.Core dependency of a package with and without the pinned version.

These rules come from F# language behavior and are not bundled proofs: an incomplete match throws `MatchFailureException` when a value has no matching case, and F# cannot declare a default implementation for an interface member. The `IStore2` sample in [references/CHANGES.md](references/CHANGES.md) is not compiled by the runner. The runner gives a `// flags:` line to both versions, so it does not prove that a flag only in 1.1.0 leaves old consumers with the body that cross-assembly inlining copied.
