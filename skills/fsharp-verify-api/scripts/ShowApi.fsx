module ShowApi

open System
open System.Reflection

let rec typeName (t: Type) =
    if t.IsGenericParameter then
        "'" + t.Name
    elif t.IsArray then
        typeName (t.GetElementType()) + "[" + String(',', t.GetArrayRank() - 1) + "]"
    elif t.IsByRef then
        "byref<" + typeName (t.GetElementType()) + ">"
    elif t.IsGenericType then
        let tick = t.Name.IndexOf '`'
        let name = if tick < 0 then t.Name else t.Name.Substring(0, tick)
        let args = t.GetGenericArguments() |> Array.map typeName |> String.concat ", "
        $"{name}<{args}>"
    else
        t.Name

let private parameters (ps: ParameterInfo array) =
    ps |> Array.map (fun p -> $"{p.Name}: {typeName p.ParameterType}") |> String.concat ", "

let private genericSuffix (m: MethodInfo) =
    if m.IsGenericMethodDefinition then
        "<" + (m.GetGenericArguments() |> Array.map typeName |> String.concat ", ") + ">"
    else
        ""

let private sourceName (m: MemberInfo) =
    m.GetCustomAttributesData()
    |> Seq.tryFind (fun a -> a.AttributeType.Name = "CompilationSourceNameAttribute")
    |> Option.map (fun a -> string a.ConstructorArguments[0].Value)
    |> Option.defaultValue m.Name

let private isExtension (m: MethodInfo) =
    m.GetCustomAttributesData() |> Seq.exists (fun a -> a.AttributeType.Name = "ExtensionAttribute")

let private describe (t: Type) (m: MemberInfo) =
    try
        match m with
        | :? ConstructorInfo as c -> Some $"new {typeName t}({parameters (c.GetParameters())})"
        | :? MethodInfo as mi when isExtension mi && mi.DeclaringType <> t ->
            let ps = mi.GetParameters() |> Array.skip 1
            Some $"extension {mi.Name}{genericSuffix mi}({parameters ps}) : {typeName mi.ReturnType}  (from {mi.DeclaringType.Name})"
        | :? MethodInfo as mi when not mi.IsSpecialName ->
            let kind = if mi.IsStatic then "static " else ""
            Some $"{kind}{sourceName mi}{genericSuffix mi}({parameters (mi.GetParameters())}) : {typeName mi.ReturnType}"
        | :? PropertyInfo as p ->
            let access = if p.CanWrite && not (isNull (p.GetSetMethod())) then "get, set" else "get"
            let index =
                match p.GetIndexParameters() with
                | [||] -> ""
                | ps -> $"[{parameters ps}]"
            Some $"{p.Name}{index} : {typeName p.PropertyType} with {access}"
        | :? EventInfo as e -> Some $"event {e.Name} : {typeName e.EventHandlerType}"
        | _ -> None
    with ex ->
        Some $"{m.Name} (signature not loaded: {ex.GetType().Name})"

let private loadableTypes (a: Assembly) =
    try a.GetExportedTypes() with :? ReflectionTypeLoadException as ex -> ex.Types |> Array.filter (isNull >> not)

let print (assemblyName: string) (typeFilter: string) (memberFilter: string) =
    let assemblies =
        try [| Assembly.Load(AssemblyName assemblyName) |] with _ -> [||]
    match assemblies with
    | [||] -> printfn "NOT LOADED assembly %s. Check the #r line and the assembly name." assemblyName
    | _ ->
        let assembly = assemblies[0]
        printfn "ASSEMBLY %s %s" (assembly.GetName().Name) (string (assembly.GetName().Version))
        let allTypes = loadableTypes assembly
        let extensions =
            allTypes
            |> Array.collect (fun t -> try t.GetMethods(BindingFlags.Public ||| BindingFlags.Static) with _ -> [||])
            |> Array.filter (fun m -> isExtension m && m.GetParameters().Length > 0)
        let extends (t: Type) (m: MethodInfo) =
            try
                let target = (m.GetParameters()).[0].ParameterType
                let target = if target.IsGenericType then target.GetGenericTypeDefinition() else target
                let rec bases (x: Type) = seq {
                    if not (isNull x) then
                        yield (if x.IsGenericType then x.GetGenericTypeDefinition() else x)
                        yield! x.GetInterfaces() |> Seq.map (fun i -> if i.IsGenericType then i.GetGenericTypeDefinition() else i)
                        yield! bases x.BaseType }
                not target.IsGenericParameter && bases t |> Seq.contains target
            with _ -> false
        let matches (m: MemberInfo) =
            memberFilter = ""
            || m.Name.Contains(memberFilter, StringComparison.OrdinalIgnoreCase)
            || (sourceName m).Contains(memberFilter, StringComparison.OrdinalIgnoreCase)
        let types =
            allTypes
            |> Array.filter (fun t -> t.FullName.Contains(typeFilter, StringComparison.OrdinalIgnoreCase))
            |> Array.sortBy (fun t -> t.FullName)
        if types.Length = 0 then printfn "NO TYPE matches '%s'" typeFilter
        for t in types do
            printfn "TYPE %s" t.FullName
            let flags = BindingFlags.Public ||| BindingFlags.Instance ||| BindingFlags.Static ||| BindingFlags.FlattenHierarchy
            let lines =
                Seq.concat [ t.GetMembers flags; (if t.IsInterface then t.GetInterfaces() |> Array.collect (fun i -> i.GetMembers flags) else [||]); extensions |> Array.filter (extends t) |> Array.map (fun m -> m :> MemberInfo) ]
                |> Seq.filter (fun m -> m.DeclaringType <> typeof<obj> && matches m)
                |> Seq.choose (fun m ->
                    describe t m
                    |> Option.map (fun line ->
                        if isNull m.DeclaringType || m.DeclaringType = t || line.StartsWith "extension" then line
                        else $"{line}  (from {typeName m.DeclaringType})"))
                |> Seq.distinct
                |> Seq.sort
                |> Seq.toList
            if lines.IsEmpty then printfn "  NO MEMBER matches '%s'" memberFilter
            for line in lines do
                printfn "  %s" line
