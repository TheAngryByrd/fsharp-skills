# Breaking changes and safe alternatives

Each section shows a change to the 1.0.0 library in [../scripts/V1/Lib.fs](../scripts/V1/Lib.fs), what it breaks, and a change that does not break.
The folder in [../scripts/changes](../scripts/changes) with the same name holds the proved version.

## AddUnionCase

```fsharp
type Shape =
    | Circle of radius: float
    | Square of side: float
    | Triangle of side: float // new
```

A consumer that matches each case gets FS0025 (incomplete match). With `TreatWarningsAsErrors`, the build fails. An old binary runs until it gets a `Triangle`.
Package validation does not report it, because the new case only adds members.

Safe alternative: none in a minor version. Release the case in a major version. For a union that must grow, hide its representation from the first release, and expose functions or active patterns.

## AddRecordField

```fsharp
type Point = { X: float; Y: float; Z: float } // Z is new
```

F# record expressions fail with FS0764, C# `new Point(x, y)` fails with CS7036, and old binaries throw `MissingMethodException` for the removed constructor.

Safe alternative: add a new type, or a function that returns the extra value. Before the first release, give a record that can grow a `create` function and hide its representation, or use a class with members.

## CurriedToTupled

```fsharp
let scale (factor: float) (point: Point) = ...   // 1.0.0
let scale (factor: float, point: Point) = ...    // changed
```

Both forms compile to the same `scale(Double, Point)` method. C# and old binaries do not see a change, and package validation reports nothing. F# callers fail with FS0001, most of all partial application such as `List.map (Geometry.scale 2.0)`.

Safe alternative: keep the form. Add a new function for the other form.

## AddRequireQualifiedAccess

```fsharp
[<RequireQualifiedAccess>] // new
type Shape = ...
```

F# code that uses `Circle` without `Shape.` fails with FS0039. A match on the unqualified cases also gives FS0025. C# and old binaries do not see a change.

Safe alternative: add the attribute only in a major version.

## InlineBodyChange

```fsharp
let inline double (x: float) = x * 2.0        // 1.0.0
let inline double (x: float) = x * 2.0 + 1.0  // changed
```

The compiler copies an `inline` body into each caller. An old binary keeps the 1.0.0 body and prints the old result, with no error. Only a rebuilt consumer gets the new body.

Safe alternative: do not make a public function `inline` unless it needs statically resolved type parameters. When you fix an `inline` body, tell consumers to build again.

## GeneralizeParameter and WidenParameterType

```fsharp
let count (items: int list) = List.length items     // 1.0.0
let count (items: 'T list) = List.length items      // GeneralizeParameter
let count (items: seq<int>) = Seq.length items      // WidenParameterType
```

F# and C# callers still compile. F# accepts a list for a `seq<int>` parameter. The compiled method signature changes, so old binaries throw `MissingMethodException`.

Safe alternative for a module function: add a function with a new name. Safe alternative for a type member: add an overload and keep the old member.

```fsharp
type Client(store: IStore) =
    member _.Total(values: int list) : int = List.sum values   // 1.0.0, keep it
    member _.Total(values: seq<int>) : int = Seq.sum values    // 1.1.0, new overload
```

The AddOverload change proves this pair. The F# consumer that passes a list literal and the C# consumer that passes an `FSharpList<int>` still build, and old binaries still run.

## OptionalParameterOnMember

```fsharp
member _.Send(message: string) : string = ...                                   // 1.0.0
member _.Send(message: string, [<Optional; DefaultParameterValue(false)>] urgent: bool) = ...  // changed
```

F# and C# callers still compile, because the parameter is optional in both languages. The compiled method now has two parameters, so old binaries throw `MissingMethodException`.

Safe alternative: keep the old member and add an overload.

```fsharp
member _.Send(message: string) : string = ...
member this.Send(message: string, urgent: bool) : string = ...
```

`[<Optional; DefaultParameterValue>]` is safe on a member that is new in this version.

## FSharpOptionalParameter

```fsharp
member _.Send(message: string, ?urgent: bool) = ...
```

C# sees `FSharpOption<bool> urgent` as a required parameter, so `client.Send("hi")` fails with CS7036. Old binaries throw `MissingMethodException`.

Safe alternative: an overload, as in OptionalParameterOnMember.

## AddInterfaceMember

```fsharp
type IStore =
    abstract Get: key: string -> string
    abstract Count: unit -> int // new
```

Each implementation fails: FS0366 in F# and CS0535 in C#. An old binary that implements the interface throws `TypeLoadException`. Package validation reports CP0006.

Safe alternative: a new interface that inherits the old one. Code that needs the new member tests for it.

```fsharp
type IStore2 =
    inherit IStore
    abstract Count: unit -> int

let count (store: IStore) =
    match store with
    | :? IStore2 as s -> Some(s.Count())
    | _ -> None
```

## RenameModule

`module Geometry` renamed to `module Geo` gives FS0039 in F#, CS0103 in C#, `TypeLoadException` in old binaries, and CP0001 in package validation.

Safe alternative: add the new module and keep the old one. Mark the old one `[<Obsolete>]`.

## ObsoleteFunction

```fsharp
[<System.Obsolete("Use scaleBy.")>]
let scale (factor: float) (point: Point) = ...
let scaleBy (factor: float) (point: Point) = ...
```

This is the safe way to retire a function. F# callers get warning FS0044, and C# callers get warning CS0618. A consumer with `TreatWarningsAsErrors` fails, so name the change in the release notes. Old binaries still run.

## AddOverload

```fsharp
member _.Total(values: int list) : int = List.sum values
member _.Total(values: seq<int>) : int = Seq.sum values
member _.Send(message: string) : string = ...
member this.Send(message: string, urgent: bool) : string = ...
```

No consumer breaks, and package validation reports nothing. Use this pattern to add a parameter to a type member or to accept a wider parameter type.
