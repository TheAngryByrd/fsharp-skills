module Greeter.Program

open System.CommandLine

let greet (name: string) (count: int) =
    for _ in 1..count do
        printfn "Hello, %s!" name

[<EntryPoint>]
let main argv =
    let name = Option<string>("--name", "Who to greet", IsRequired = true)
    let count = Option<int>("--count", (fun () -> 1), "How many greetings")
    count.AddValidator(fun result ->
        if result.GetValueOrDefault<int>() < 1 then
            result.ErrorMessage <- "--count must be at least 1")
    let root = RootCommand("Greets a person")
    root.AddOption name
    root.AddOption count
    root.SetHandler((fun n c -> greet n c), name, count)
    root.Invoke argv
