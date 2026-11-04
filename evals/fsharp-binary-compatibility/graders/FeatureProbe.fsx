open System
open System.Reflection
open Microsoft.FSharp.Reflection

let assemblyPath = fsi.CommandLineArgs.[1]
let shipping = Assembly.LoadFrom assemblyPath
let parcelType = shipping.GetExportedTypes() |> Array.find (fun t -> t.FullName = "Shipping+Parcel")

let rec candidates (depth: int) (parcel: obj) (t: Type) : obj list =
    if t = parcelType then
        [ parcel ]
    elif t = typeof<decimal> then
        [ box 300.00M ]
    elif t = typeof<bool> then
        [ box true; box false ]
    elif t = typeof<string> then
        [ box "express"; box "Express" ]
    elif depth > 2 then
        []
    elif t.IsGenericType && t.GetGenericTypeDefinition() = typedefof<option<_>> then
        let none = FSharpType.GetUnionCases t |> Array.find (fun c -> c.Name = "None")
        let some = FSharpType.GetUnionCases t |> Array.find (fun c -> c.Name = "Some")
        FSharpValue.MakeUnion(none, [||])
        :: (candidates (depth + 1) parcel (t.GetGenericArguments().[0])
            |> List.map (fun v -> FSharpValue.MakeUnion(some, [| v |])))
    elif FSharpType.IsUnion t then
        [ for case in FSharpType.GetUnionCases t do
              for fields in combinations (depth + 1) parcel (case.GetFields() |> Array.map (fun f -> f.PropertyType)) do
                  FSharpValue.MakeUnion(case, fields) ]
    elif FSharpType.IsRecord t then
        [ for fields in combinations (depth + 1) parcel (FSharpType.GetRecordFields t |> Array.map (fun f -> f.PropertyType)) do
              FSharpValue.MakeRecord(t, fields) ]
    else
        []

and combinations (depth: int) (parcel: obj) (types: Type[]) : obj[] list =
    types
    |> Array.fold
        (fun acc t -> [ for prefix in acc do for v in candidates depth parcel t -> Array.append prefix [| v |] ] |> List.truncate 200)
        [ [||] ]

let decimalOf (value: obj) : decimal option =
    match value with
    | :? decimal as d -> Some d
    | null -> None
    | v when FSharpType.IsUnion(v.GetType()) ->
        let case, fields = FSharpValue.GetUnionFields(v, v.GetType())
        match case.Name, fields with
        | ("Ok" | "Some"), [| :? decimal as d |] -> Some d
        | _ -> None
    | _ -> None

let parcels (id: string) (weight: decimal) : obj list =
    let choices (f: PropertyInfo) : obj list =
        match f.Name with
        | "Id" -> [ box id ]
        | "WeightKg" -> [ box weight ]
        | _ when f.PropertyType = typeof<string> -> [ box "" ]
        | _ when f.PropertyType = typeof<decimal> -> [ box 0M; box 300.00M ]
        | _ when f.PropertyType = typeof<bool> -> [ box false ]
        | _ when f.PropertyType = typeof<option<decimal>> -> [ null; box (Some 300.00M) ]
        | _ -> [ null ]
    FSharpType.GetRecordFields parcelType
    |> Array.fold (fun acc f -> [ for prefix in acc do for v in choices f -> Array.append prefix [| v |] ]) [ [||] ]
    |> List.map (fun values -> FSharpValue.MakeRecord(parcelType, values))

let exported =
    shipping.GetExportedTypes() |> Array.filter (fun t -> not t.ContainsGenericParameters)

let declared (scope: BindingFlags) (t: Type) =
    t.GetMethods(BindingFlags.Public ||| BindingFlags.DeclaredOnly ||| scope)
    |> Array.filter (fun m -> not m.ContainsGenericParameters && not m.IsSpecialName)

let staticCalls : (obj * MethodInfo) list =
    [ for t in exported do
          for m in declared BindingFlags.Static t -> null, m ]

let serviceCalls : (obj * MethodInfo) list =
    [ for t in exported do
          if not t.IsAbstract && t.IsClass && not (isNull (t.GetConstructor Type.EmptyTypes)) then
              match (try Some(Activator.CreateInstance t) with _ -> None) with
              | Some receiver ->
                  for m in declared BindingFlags.Instance t -> receiver, m
              | None -> () ]

let parcelMembers =
    parcelType.GetMethods(BindingFlags.Public ||| BindingFlags.DeclaredOnly ||| BindingFlags.Instance)
    |> Array.filter (fun m ->
        not m.ContainsGenericParameters
        && (not m.IsSpecialName || (m.Name.StartsWith "get_" && m.GetParameters().Length = 0)))

let invoke (receiver: obj) (m: MethodInfo) (args: obj[]) =
    try m.Invoke(receiver, args) with _ -> null

let rec containsParcel (depth: int) (t: Type) : bool =
    t = parcelType
    || (depth < 3
        && ((t.IsGenericType && t.GetGenericArguments() |> Array.exists (containsParcel (depth + 1)))
            || (FSharpType.IsRecord t && FSharpType.GetRecordFields t |> Array.exists (fun f -> containsParcel (depth + 1) f.PropertyType))
            || (FSharpType.IsUnion t
                && FSharpType.GetUnionCases t |> Array.exists (fun c -> c.GetFields() |> Array.exists (fun f -> containsParcel (depth + 1) f.PropertyType)))))

let parameterTypes (m: MethodInfo) =
    m.GetParameters() |> Array.map (fun p -> p.ParameterType)

let parcelCalls =
    staticCalls @ serviceCalls
    |> List.filter (fun (_, m) -> parameterTypes m |> Array.exists (containsParcel 0))

let results (all: obj list) : decimal list =
    [ for parcel in all do
        let calls = parcelCalls @ [ for m in parcelMembers -> parcel, m ]
        for receiver, m in calls do
            for args in combinations 0 parcel (parameterTypes m) do
                match decimalOf (invoke receiver m args) with
                | Some d -> d
                | None -> () ]

let report name passed =
    printfn "%s %s" (if passed then "PASS" else "FAIL") name

report "express" (results (parcels "P1" 2.0M) |> List.contains 13.80M)
report "insured" (results (parcels "P4" 5.0M) |> List.contains 13.50M)

let readsHeld =
    staticCalls @ serviceCalls
    |> List.exists (fun (receiver, m) ->
        match m.GetParameters() with
        | [| p |] when p.ParameterType = typeof<string> ->
            match invoke receiver m [| box "HD" |] with
            | null -> false
            | v when FSharpType.IsUnion(v.GetType()) ->
                let case, fields = FSharpValue.GetUnionFields(v, v.GetType())
                case.Name = "Held"
                || ((case.Name = "Some" || case.Name = "Ok")
                    && fields.Length = 1
                    && not (isNull fields.[0])
                    && FSharpType.IsUnion(fields.[0].GetType())
                    && (fst (FSharpValue.GetUnionFields(fields.[0], fields.[0].GetType()))).Name = "Held")
            | _ -> false
        | _ -> false)

report "reads HD as Held" readsHeld
