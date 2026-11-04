#r "nuget: PublicApiGenerator, 11.4.6"

open System.IO
open System.Runtime.Loader

for pair in fsi.CommandLineArgs |> Array.skip 1 do
    let assemblyPath, outFile =
        match pair.Split '|' with
        | [| a; o |] -> Path.GetFullPath a, o
        | _ -> failwith $"Expected <assembly>|<output>: {pair}"
    let context = AssemblyLoadContext(assemblyPath, true)
    try
        let assembly = context.LoadFromAssemblyPath assemblyPath
        File.WriteAllText(outFile, PublicApiGenerator.ApiGenerator.GeneratePublicApi assembly)
    finally
        context.Unload()
