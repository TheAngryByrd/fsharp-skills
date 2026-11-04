---
name: fsharp-binary-compatibility
description: Change a published F# library so that apps compiled against the old version still run against the new DLL with no rebuild. Covers new parameters on let-bound functions (no overloads), optional member parameters, inferred type changes, union case order and new cases, record fields, inline and [<Literal>] values, cross-assembly inlining (--nooptimizationdata), renames with CompiledName, curried and tupled parameters, abstract interface members, the FSharp.Core dependency, and automated checks with package validation, apicompat, and an F# signature diff. Use when the user changes the public API of an F# library or NuGet package in a minor or patch release, asks for a non-breaking change, or asks whether an F# change is binary compatible.
compatibility: The proof runner and sig-diff.ps1 require the .NET 10 SDK, PowerShell 7.4 or later, and NuGet access. Results were verified with SDK 10.0.403 on win-x64. scripts/global.json selects .NET 10.
---

# F# binary compatibility

A change is binary compatible when an app that was compiled against v1 still runs,
with the same results, after you replace the library DLL with v2. The app is not
rebuilt. A successful build of the solution proves only source compatibility,
because the build compiles every consumer again.

F# adds traps that C# does not have. A `let` function cannot have overloads. The
compiler copies some library code into each consumer. A union match uses case
numbers. The rules below come from the proof runner in [scripts/](scripts). Each rule
names its proof case in `scripts/proof/cases/`.

To stop type inference from changing a signature, use
[fsharp-signature-files](../fsharp-signature-files/SKILL.md). This skill does not
repeat it.

## Rules

1. **Do not add a parameter to a public `let` function.** The compiled static method
   gets a new signature, and an old app gets `MissingMethodException`. Add a new
   function and keep the old one as a wrapper (`module-parameter`):

   ```fsharp
   let parsePriceIn (currency: string) (text: string) = ...
   let parsePrice (text: string) = parsePriceIn "USD" text
   ```

   A rebuilt caller can still compile after the break: `parsePrice text` becomes a
   partial application, and `%A` prints a function value.
2. **On a type member, add an overload.** A new optional parameter (`?currency`)
   keeps source compatibility, but it replaces the old method, and an old app gets
   `MissingMethodException` (`member-optional`). Keep the old member and add a
   second `static member` or method with the new parameter.
3. **Write explicit types on each public function**, or use a `.fsi` file. A body
   change can change the inferred signature, for example `int` to `'a`, or `seq` to
   `list`. Each one gives `MissingMethodException` (`infer-generic`,
   `infer-collection`).
4. **Add a union case only at the end.** A case in the middle changes the tag number
   of each later case. An old app then runs the wrong match branch, with no error
   (`union-insert`). Package validation and `apicompat` do not report it. A small
   union with case fields kept working in the proof (`union-insert-small`), but do
   not depend on that.
5. **Do not return a new union case to an old app.** An old app that gets an unknown
   case runs a wrong branch of its match, with no error. A rebuilt app gets warning
   FS0025 and `MatchFailureException` (`union-new-case`). When an old app can get the
   new case from an existing function, for example because it already passes the new
   input, keep that function on the old cases and add a new function that can return
   the new case. Otherwise, make a major version. An existing function can return the
   new case only when no old app can get it.
6. **Do not add a field to a public record that callers construct.** Record
   construction and copy-and-update (`{ r with ... }`) call the record constructor,
   and an old app gets `MissingMethodException` (`record-field`, `record-copy`). A record cannot
   keep its old constructor: `new` in a record gives FS0871. Put the new data in a
   new type, for example `{ Line: OrderLine; Note: string option }`, with new
   functions.
7. **Treat `inline` bodies and `[<Literal>]` values as copied into each app.** An old
   app keeps the old body or value until it is rebuilt (`inline-body`,
   `literal-value`). Use a plain function and a plain `let` value when the body or
   value can change, and build the library with the rule 8 flag. With default flags,
   a Release app also copies a plain `let` value and keeps the old value
   (`literal-value`, `plain-default`).
8. **Know that Release builds also copy small non-inline functions.** The F# compiler
   puts optimization data in the library DLL, and a consumer that is built in
   Release copies small public function bodies from it. An old app then keeps the
   old body (`body-inlined`). A copied body can also call a changed member: an app
   that only called a small `line` factory got `MissingMethodException` for the
   record constructor (`record-inlined`). A library that must take body changes
   with no consumer rebuild needs `--nooptimizationdata` from its first release:

   ```xml
   <OtherFlags>$(OtherFlags) --nooptimizationdata</OtherFlags>
   ```

   The flag does not change apps that were compiled against an earlier DLL that had
   optimization data (`body-inlined`, `safe from v1`). It also stops cross-assembly
   inlining, so consumer code can be slower. `inline` functions are still copied
   with the flag.
9. **Rename with a wrapper.** In a minor release, add the new name and keep the old
   name as a plain wrapper (`rename`). Mark the old name `[<Obsolete("Use X.")>]` only
   in a major version, and name it in the release notes. A new `[<Obsolete>]` on an
   existing member is a source break: a rebuilt caller gets warning FS0044, and a
   consumer with `TreatWarningsAsErrors` fails (`rename`, variant `obsolete`). Old
   binaries still run. `[<CompiledName("oldName")>]` on the renamed function keeps old
   apps working, but each F# caller that is rebuilt gets FS0039.
10. **Do not change between curried and tupled parameters.** Both forms compile to
    the same method, so an old app keeps working, but a rebuilt F# caller fails
    (`curried-tupled`). `apicompat` does not report it. Add a new function instead.
11. **Do not raise the FSharp.Core dependency in a minor release.** By default the
    package depends on the FSharp.Core version of the SDK that packed it, for
    example 10.1.403. A consumer that references a lower FSharp.Core gets only warning
    NU1605. It builds, and then fails at startup with `FileNotFoundException` for
    `FSharp.Core, Version=10.1.0.0`. Set the lowest version that the library needs:

    ```xml
    <DisableImplicitFSharpCoreReference>true</DisableImplicitFSharpCoreReference>
    ...
    <PackageReference Include="FSharp.Core" Version="8.0.400" />
    ```
12. **Do not add an abstract member to a public interface.** An old app that
    implements the interface gets `TypeLoadException`, and a rebuilt one gets FS0366
    (`interface-member`). Add a new interface that inherits the old one, and test for
    it with `:?` where you need the new member.

Read [references/RULES.md](references/RULES.md) for each break with its safe form and
its measured result.

## Steps

1. **Keep the baseline.** Before the change, find the released version: a git tag, a
   release folder, or the published package. Build it and keep its DLL.
2. **Make the change with the rules above.** Done when no public `let` function has a
   new parameter, no union case moved, no constructed record has a new field, and no
   public interface has a new abstract member.
3. **Run package validation or `apicompat`.** Package validation runs in `dotnet pack`:

   ```xml
   <EnablePackageValidation>true</EnablePackageValidation>
   <PackageValidationBaselineVersion>1.0.0</PackageValidationBaselineVersion>
   ```

   Restore must find the baseline package on a feed. With package source mapping in
   a `nuget.config`, map the package ID to that feed, or restore gives NU1101. For a
   baseline that is not packed, compare the DLLs with the `apicompat` tool. The left
   side is the baseline:

   ```powershell
   dotnet tool install Microsoft.DotNet.ApiCompat.Tool --create-manifest-if-needed
   dotnet apicompat --left <baseline>/Lib.dll --right <new>/Lib.dll
   ```

   The skill's `scripts/.config/dotnet-tools.json` pins version 10.0.403. Run
   `dotnet tool restore` in `scripts/` to use it from there.

   Both tools fail with `CP0002` for a removed or changed member. Fix each `CP0002`.
4. **Run the F# signature diff.** It shows the changes that the IL tools do not
   report: union case order, curried and tupled parameters, `[<Literal>]` values,
   and inferred types. From the skill root:

   ```powershell
   pwsh ./scripts/sig-diff.ps1 -Project <path>/Lib.fsproj -BaselineRef v1.0.0
   pwsh ./scripts/sig-diff.ps1 -Project <path>/Lib.fsproj -BaselineProject <baseline>/Lib.fsproj
   ```

   Exit code 0 means no signature change, 1 means a change (the diff is printed), and
   2 means a build or checkout failure. The script builds the current project in
   place. It checks out `-BaselineRef` in a temporary folder next to the repository,
   so MSBuild, NuGet, and `global.json` files above the repository apply to both
   builds. Pass `-Framework <tfm>` for a multi-target project. Check each changed line
   against the rules.
   An added line is safe only when it adds a function, adds a member to a type that
   old apps do not implement, or adds a union case after the last case.
5. **Run an old app against the new DLL.** Build a small consumer against the
   baseline DLL in Release. Copy the new library DLL into its output folder, with no
   rebuild, and run it. It must give the same output for the old cases, with no
   `MissingMethodException`, `TypeLoadException`, or `MissingFieldException`. No
   tool finds copied bodies or behavior changes. Only this run does.
6. **Rebuild the consumers against the new version** and test the new features.
7. **For an accepted break,** make a major version. A new `[<Obsolete>]` on an
   existing member also needs a major version, and the release notes must name it.
   Record each binary break in `CompatibilitySuppressions.xml`.
   `dotnet pack -p:ApiCompatGenerateSuppressionFile=true` writes the file next to the
   project, and later packs read it. Add an XML comment with the reason above each
   suppression.

## Tools

| Tool | Use it | Reports | Does not report |
| --- | --- | --- | --- |
| Package validation | Yes, in the build | Removed or changed members (CP0002) | Union case order, copied bodies. From the `apicompat` results, also `[<Literal>]` values and curried and tupled changes |
| `apicompat` | Yes, for DLLs that are not on a feed | The same as package validation. `--strict-mode` also reports each added member. | The same as package validation, also with `--enable-rule-attributes-must-match` |
| `sig-diff.ps1` | Yes, after package validation | The F# view: case order, curried and tupled, literals, inferred types | Body changes, also in `inline` functions |
| PublicApiGenerator snapshot | Optional | Each public change, also the union, literal, and curried-to-tupled changes. Also each addition that does not break. | Body changes |
| `Microsoft.CodeAnalysis.PublicApiAnalyzers` | No | Nothing in F#: the F# compiler does not run Roslyn analyzers | Everything |

Read [references/TOOLS.md](references/TOOLS.md) for the measured result of each tool
on each proof case.

## Verify

Run the proof runner from the skill root:

```powershell
pwsh ./scripts/run.ps1
```

For each case, the runner builds the library versions and a consumer against the
baseline. It runs the old consumer with the new DLL, rebuilds the consumer, and runs
`apicompat`, `apicompat --strict-mode`, the signature diff, and PublicApiGenerator. It
fails when a result differs from the `// expect` line in the case's `Consumer.fs`.
It then checks package validation, the FSharp.Core dependency, the Roslyn analyzer
claim, and `sig-diff.ps1`. Use `-Case <name>` to run only some cases. With `-Case`,
the runner does not run these tool proofs.
