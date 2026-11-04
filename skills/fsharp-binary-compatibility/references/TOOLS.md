# Compatibility tools on F# changes

The proof runner ran each tool on each case in
[../scripts/proof/cases](../scripts/proof/cases). The left side of each comparison is
the baseline. `reports` means that the tool showed a difference, and `clean` means
that it showed none.

- `apicompat`: `dotnet apicompat --left <base>/Lib.dll --right <new>/Lib.dll`, with
  `Microsoft.DotNet.ApiCompat.Tool` 10.0.403. It exits with code 1 and prints
  `CP0002` for a break.
- `strict`: the same with `--strict-mode --enable-rule-attributes-must-match
  --enable-rule-cannot-change-parameter-name`. Strict mode also reports each added
  member, so it reports most safe changes.
- `sig`: a diff of the compiler `--sig` output, as `scripts/sig-diff.ps1` prints it.
- `api`: a diff of the PublicApiGenerator 11.4.6 text.

| Case | Change | Old app | `apicompat` | `strict` | `sig` | `api` |
| --- | --- | --- | --- | --- | --- | --- |
| `module-parameter` | New curried parameter | `MissingMethodException` | reports | reports | reports | reports |
| `module-parameter` | New function and old wrapper | same | clean | reports | reports | reports |
| `member-optional` | New optional member parameter | `MissingMethodException` | reports | reports | reports | reports |
| `member-optional` | New overload | same | clean | reports | reports | reports |
| `infer-generic` | `int` becomes `'a` | `MissingMethodException` | reports | reports | reports | reports |
| `infer-collection` | `seq` becomes `list` | `MissingMethodException` | reports | reports | reports | reports |
| `union-insert` | Case in the middle | wrong | clean | reports | reports | reports |
| `union-insert` | Case at the end | same | clean | reports | reports | reports |
| `union-new-case` | Existing function returns a new case | wrong | clean | reports | reports | reports |
| `record-field` | New field | `MissingMethodException` | reports | reports | reports | reports |
| `record-copy` | New field, app uses copy-and-update | `MissingMethodException` | reports | reports | reports | reports |
| `record-inlined` | New field, small factory copied | `MissingMethodException` | reports | reports | reports | reports |
| `inline-body` | `inline` body changed | stale | clean | clean | clean | clean |
| `literal-value` | `[<Literal>]` value changed | stale | clean | clean | reports | reports |
| `literal-value` | Plain `let` value changed, default flags | stale | clean | clean | clean | clean |
| `interface-member` | New abstract interface member | `TypeLoadException` | reports | reports | reports | reports |
| `body-inlined` | Small function body changed | stale | clean | clean | clean | clean |
| `rename` | Rename | `MissingMethodException` | reports | reports | reports | reports |
| `rename` | Rename with `CompiledName` | same | clean | clean | reports | reports |
| `rename` | `[<Obsolete>]` wrapper with the old name | same | clean | reports | reports | reports |
| `curried-tupled` | Curried to tupled | same | clean | clean | reports | reports |

What the results show:

- `apicompat` and package validation report each change that removes or changes a
  compiled member. They miss the union tag numbers, the `[<Literal>]` value, the
  curried and tupled change, and each body change. Strict mode reports a new case,
  but it reports a case at the end in the same way as a case in the middle.
- `--enable-rule-attributes-must-match` does not report the removed
  `CompilationArgumentCounts` attribute of a curried function.
- The `--sig` diff is the only check here that shows the F# source view. The tool
  proofs check two of its lines: a new `| Refunded` case line, and
  `quantity: int * unitPrice: decimal` after a change from curried to tupled. It
  shows no body.
- PublicApiGenerator reports the union, literal, and curried-to-tupled changes, which
  `apicompat` misses. It also reports each safe addition, so a snapshot test fails
  for every public change.
- No tool reports a copied body. Only an old app that runs with the new DLL shows it.

## Package validation

The runner packs the `module-parameter` baseline as version 1.0.0 into a local feed.
It packs the other versions with these properties:

```xml
<EnablePackageValidation>true</EnablePackageValidation>
<PackageValidationBaselineVersion>1.0.0</PackageValidationBaselineVersion>
<RestoreAdditionalProjectSources>path/to/feed</RestoreAdditionalProjectSources>
```

| Version | `dotnet pack` |
| --- | --- |
| New curried parameter | fails: `error CP0002: Member 'decimal Lib.parsePrice(string)' exists on [Baseline] lib/net10.0/Lib.dll but not on lib/net10.0/Lib.dll` |
| New function and old wrapper | passes |
| Union case in the middle | passes |
| New curried parameter, `-p:ApiCompatGenerateSuppressionFile=true` | passes and writes `CompatibilitySuppressions.xml` next to the project |
| New curried parameter, with that file | passes |

The runner packs only `module-parameter` and `union-insert`. Package validation uses the same compatibility engine as `apicompat`, so the other `apicompat` results in the first table of this file are expected for `dotnet pack` too. The proof does not pack those cases.

## Roslyn PublicApiAnalyzers

`Microsoft.CodeAnalysis.PublicApiAnalyzers` 4.14.0 with an empty
`PublicAPI.Shipped.txt` and `TreatWarningsAsErrors`:

| Project | Result |
| --- | --- |
| C# library with a public method | fails with RS0016 |
| F# library with a public function | builds with no diagnostic |

The F# compiler does not run Roslyn analyzers. Do not add this package to an F#
project as a compatibility check.
