module Greeter.Program

open System.CommandLine

let greet (name: string) (count: int) =
    for _ in 1..count do
        printfn "Hello, %s!" name

[<EntryPoint>]
let main argv =
    let name = Option<string>("--name", Description = "Who to greet", Required = true)
    let count = Option<int>("--count", Description = "How many greetings", DefaultValueFactory = (fun _ -> 1))
    count.Validators.Add(fun result ->
        if result.GetValueOrDefault<int>() < 1 then
            result.AddError "--count must be at least 1")
    let root = RootCommand("Greets a person")
    root.Options.Add name
    root.Options.Add count
    root.SetAction(fun (parseResult: ParseResult) ->
        printfn "DEBUG parsed"
        greet (parseResult.GetValue name) (parseResult.GetValue count))
    root.Parse(argv).Invoke()

