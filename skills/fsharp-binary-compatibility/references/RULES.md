# Binary compatibility rules with proofs

Each section names a case in [../scripts/proof/cases](../scripts/proof/cases). The
case holds the baseline library, the breaking change, the safe change, and a consumer.
The runner compiles the consumer against the baseline, then runs that same binary with
the new library DLL. The table values have these meanings:

- **Old app**: the result of the consumer that was compiled against the baseline.
  - `same`: the same output as with the baseline.
  - `wrong`: other output, with no exception.
  - `stale`: the baseline output, but a rebuilt consumer prints new output.
  - `updated`: the output of a rebuilt consumer.
  - An exception name: the consumer stopped with that exception.
- **Rebuilt app**: the consumer compiled again against the new library. `same`,
  `differs`, the compiler error code, or an exception name.

The consumers are built in Release, as a published app is.

## Module functions (`module-parameter`)

```fsharp
// break: one compiled method parsePrice(string, string) replaces parsePrice(string)
let parsePrice (text: string) (currency: string) = ...

// safe
let parsePriceIn (currency: string) (text: string) = ...
let parsePrice (text: string) = parsePriceIn "USD" text
```

| Change | Old app | Rebuilt app |
| --- | --- | --- |
| New parameter | `MissingMethodException` | `differs`: `parsePrice text` is now a function value |
| New function and old wrapper | `same` | `same` |

## Member parameters (`member-optional`)

```fsharp
// break
static member Parse(text: string, ?currency: string) = ...

// safe
static member Parse(text: string, currency: string) = ...
static member Parse(text: string) = Prices.Parse(text, "USD")
```

| Change | Old app | Rebuilt app |
| --- | --- | --- |
| New optional parameter | `MissingMethodException` | `same` |
| New overload | `same` | `same` |

## Inferred types (`infer-generic`, `infer-collection`)

A body change can change the public signature with no change to the code that
declares it:

```fsharp
let firstOr fallback items = match items with [] -> fallback + 0 | x :: _ -> x  // int
let firstOr fallback items = match items with [] -> fallback | x :: _ -> x      // 'a
```

| Change | Old app | Rebuilt app |
| --- | --- | --- |
| `int` becomes `'a` | `MissingMethodException` | `same` |
| `seq<int>` becomes `int list` | `MissingMethodException` | `same` |
| Explicit parameter and return types | `same` | `same` |

## Union cases (`union-insert`, `union-insert-small`, `union-new-case`)

The compiled match of a union with no case fields reads the `Tag` number. A case in
the middle changes the number of each later case:

```fsharp
type OrderState = Pending | Paid | Refunded | Shipped | Delivered | Cancelled  // break
type OrderState = Pending | Paid | Shipped | Delivered | Cancelled | Refunded  // safe
```

| Change | Old app | Rebuilt app |
| --- | --- | --- |
| Case in the middle, 5 cases with no fields | `wrong` | `same` |
| Case at the end | `same` | `same` |
| Case in the middle, 3 cases with a field | `same`: the match uses type tests | `same` |
| Existing function returns a new case that the old app gets | `wrong` | `MatchFailureException`, after warning FS0025 |
| New case only from a new function | `same` | `same` |

The old app does not get `MatchFailureException` for a new case. It runs a wrong
branch of its match, with no error. Which branch runs depends on the compiled match.

## Record fields (`record-field`, `record-inlined`)

| Change | Old app | Rebuilt app |
| --- | --- | --- |
| New field, the app constructs the record | `MissingMethodException` | FS0764: the record expression has no `Note` |
| New field, the app only uses copy-and-update (`record-copy`) | `MissingMethodException` | `same` |
| `new(sku, quantity) = ...` in the record | does not compile: FS0871 | |
| New type `NotedLine = { Line: OrderLine; Note: string option }` | `same` | `same` |
| New field, the app only calls a small `line` factory | `MissingMethodException`: the factory body was copied into the app | `same` |
| The same, with `--nooptimizationdata` in both versions | `same` | `same` |

Copy-and-update (`{ Lib.sample with Quantity = 3 }`) also calls the constructor.

## Copied code (`inline-body`, `literal-value`, `body-inlined`)

| Change | Old app | Rebuilt app |
| --- | --- | --- |
| `inline` body changed | `stale` | `differs` |
| `inline` body changed, `--nooptimizationdata` | `stale` | `differs` |
| Plain function changed, `--nooptimizationdata` in both versions | `updated` | `differs` |
| `[<Literal>]` value changed | `stale` | `differs` |
| Plain `let` value changed, default flags | `stale` | `differs` |
| Plain `let` value changed, `--nooptimizationdata` in both versions | `updated` | `differs` |
| Small plain function changed, default flags | `stale` | `differs` |
| Small plain function changed, `--nooptimizationdata` in both versions | `updated` | `differs` |
| Small plain function changed, `--nooptimizationdata` only in the new version | `stale` | `differs` |

The F# compiler writes optimization data into the library DLL. A consumer that is
built with optimizations (Release) copies small function bodies from that data. A
function with a larger body, such as `parsePrice` in `module-parameter`, was not
copied. The size limit is a compiler detail, so do not depend on it.

## Renames (`rename`)

| Change | Old app | Rebuilt app |
| --- | --- | --- |
| Rename `computeTotal` to `lineTotal` | `MissingMethodException` | FS0039 |
| Rename with `[<CompiledName("computeTotal")>]` | `same` | FS0039 |
| New name and a plain wrapper with the old name | `same` | `same`, also with `TreatWarningsAsErrors` |
| New name and an `[<Obsolete>]` wrapper with the old name | `same` | `same` with warning FS0044. With `TreatWarningsAsErrors`: FS0044 error |

A new `[<Obsolete>]` on an existing member is a source break for a consumer with `TreatWarningsAsErrors`, so it belongs in a major version. Old binaries still run.

## Curried and tupled parameters (`curried-tupled`)

`let lineTotal quantity unitPrice` and `let lineTotal (quantity, unitPrice)` both
compile to `lineTotal(Int32, Decimal)`. Only the `CompilationArgumentCounts`
attribute differs.

| Change | Old app | Rebuilt app |
| --- | --- | --- |
| Curried to tupled | `same` | FS0003 |
| New tupled function next to the curried one | `same` | `same` |

## Interface members (`interface-member`)

```fsharp
// break: an old app that implements IPricer has no Currency
type IPricer =
    abstract Price: quantity: int -> decimal
    abstract Currency: string

// safe
type ICurrencyPricer =
    inherit IPricer
    abstract Currency: string
```

| Change | Old app | Rebuilt app |
| --- | --- | --- |
| New abstract member on the interface | `TypeLoadException` | FS0366 |
| New interface that inherits the old one | `same` | `same` |

## FSharp.Core

| Package | Dependency in the `.nuspec` | Consumer that references FSharp.Core 8.0.400 |
| --- | --- | --- |
| Default implicit FSharp.Core | the SDK version, for example `10.1.403` | NU1605 warning, then `FileNotFoundException` for `FSharp.Core, Version=10.1.0.0` at startup |
| `DisableImplicitFSharpCoreReference` and FSharp.Core 8.0.400 | `8.0.400` | no warning |

NU1605 is a warning in an F# project by default. The consumer builds, copies
FSharp.Core 8.0.0.0 to its output, and stops when it first calls the library.
