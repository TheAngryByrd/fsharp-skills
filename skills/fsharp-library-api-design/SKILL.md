---
name: fsharp-library-api-design
description: Design and change the public API of an F# library without breaking its consumers. Covers F#-specific breaking changes (new union cases, new record fields, curried and tupled forms, generic and inline functions, RequireQualifiedAccess, renamed modules), binary breaks that a clean build does not show (a new optional parameter, a wider parameter type), safe extension patterns (overloads, new functions, Obsolete), a C#-friendly surface, SemVer for each change type, the lowest FSharp.Core version, and compatibility checks with package validation and old consumers. Use when the user adds to or changes a published F# library, asks whether a change is breaking, picks a version number, or exposes F# code to C#.
compatibility: The proof runner requires the .NET 10 SDK, PowerShell 7.4 or later, and NuGet access. Results were verified with SDK 10.0.403 on win-x64.
---

# F# library API design

A published library has two contracts:

- **Source compatibility:** F# and C# code that compiled against 1.0.0 compiles against 1.1.0.
- **Binary compatibility:** an assembly that was compiled against 1.0.0 runs with 1.1.0.
  NuGet gives this case often. When package A was built against 1.0.0 and the app needs 1.1.0, A runs with 1.1.0 and is not compiled again.

A minor or patch version must keep both contracts. A clean build of every consumer that you can see proves only source compatibility.
Many F# breaking changes do not look like breaking changes. Some are source-only, and package validation does not report them.

## Changes and their results

Each row is a change to version 1.0.0 that [scripts/run.ps1](scripts/run.ps1) proves. "Source" rebuilds an F# and a C# consumer with `TreatWarningsAsErrors`. FS0025, FS0044, and CS0618 are warnings that this setting makes errors. "Binary" runs a consumer that was compiled against 1.0.0 with the new DLL.

| Change | F# source | C# source | Binary | Package validation |
|---|---|---|---|---|
| New union case | FS0025 | ok | ok until a new case reaches old code | not reported |
| New record field | FS0764 | CS7036 | MissingMethodException | CP0002 |
| Curried function made tupled | FS0001 | ok | ok | not reported |
| `[<RequireQualifiedAccess>]` added | FS0039 | ok | ok | not reported |
| `inline` body changed | ok | ok | old body runs until rebuild | not reported |
| Parameter made generic (`int list` to `'T list`) | ok | ok | MissingMethodException | CP0002 |
| Parameter type widened (`int list` to `seq<int>`) | ok | ok | MissingMethodException | CP0002 |
| `[<Optional; DefaultParameterValue>]` parameter added to an existing member | ok | ok | MissingMethodException | CP0002 |
| F# `?x` parameter added to an existing member | ok | CS7036 | MissingMethodException | CP0002 |
| Member added to a public interface | FS0366 | CS0535 | TypeLoadException | CP0006 |
| Module renamed | FS0039 | CS0103 | TypeLoadException | CP0001 |
| `[<Obsolete>]` on a function | FS0044 | CS0618 | ok | not reported |
| New overload on a type member | ok | ok | ok | ok |

Read [references/CHANGES.md](references/CHANGES.md) for each change with its code and its safe alternative.

## Rules

- **Extend. Do not change.** Do not change the signature of a public function or member in a minor version. This includes a new optional parameter and a wider or generic parameter type. Add an overload on a type member, or add a new function next to the old one.
- **Overloads need a type.** A module function cannot have an overload. To give a module function a new parameter, add a function with a new name. You can mark the old one `[<Obsolete("Use X.")>]`. A consumer with `TreatWarningsAsErrors` then fails with FS0044 or CS0618, so name each new `Obsolete` in the release notes.
- **Records:** a new field removes the old constructor and breaks each consumer that builds the record, including test code. When a record must grow, plan for it in the first version: expose a `create` function or a class with members. Use [fsharp-signature-files](../fsharp-signature-files/SKILL.md) to hide a representation.
- **Unions:** a new case is a breaking change for each consumer that matches on the union. Old binaries throw `MatchFailureException` when they get the new case. Release a new case in a major version, or hide the representation before the first release.
- **Interfaces:** do not add a member to a public interface. Add a new interface that inherits the old one, for example `IStore2`, and test for it at run time with `:?`.
- **Curried and tupled:** keep the form of each public function. A change compiles to the same method, so package validation does not see it, but F# callers fail.
- **`inline`:** an `inline` body is compiled into each caller. A fix in the body reaches a consumer only when the consumer builds again. Use `inline` on a public function only when it needs statically resolved type parameters.
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
| Major | Any break in the table above, in F# source, C# source, or binary form. A new `[<Obsolete>]` is the exception. |
| Minor | New types, new functions, new overloads, new members on classes, and `[<Obsolete>]`. |
| Patch | Fixes that do not change the public surface. A fix to an `inline` body reaches callers only when they build again, so say so in the release notes. |

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

   `dotnet pack` then fails with CP0001, CP0002, or CP0006 when a type or member signature of 1.0.0 is gone or changed. It does not report F#-only source breaks, a new union case, or a changed `inline` body.
4. Check both contracts with the consumers that you have:
   - Source: build each F# and C# consumer, with its tests, against the new library.
   - Binary: build each consumer against the old version. Copy the new library DLL, and each new dependency DLL, into its output folder. Run the consumer. The output must not change.
5. Compare the public surface with the snapshot. Each removed or changed line is a break. Each added line that C# calls must follow the C#-friendly rules above.
6. Set the version and write a release notes entry that names each addition, each `[<Obsolete>]`, and each FSharp.Core change.

## Verify

Run the proof runner from the skill root:

```powershell
pwsh ./scripts/run.ps1
```

The runner packs [scripts/V1](scripts/V1) as the 1.0.0 baseline. For each folder in [scripts/changes](scripts/changes), it packs the changed library with package validation. It builds the F# and C# consumers against it, and runs the 1.0.0 consumers with the new DLL. It compares each result with the `// expect-` lines of the change and exits with code 1 on a difference. It also checks the FSharp.Core dependency of a package with and without the pinned version.

These rules come from F# language behavior and are not bundled proofs: an incomplete match throws `MatchFailureException` when a value has no matching case, and F# cannot declare a default implementation for an interface member.
