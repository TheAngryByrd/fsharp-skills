module Greeter.Program

let greet (name: string) (count: int) =
    for _ in 1..count do
        printfn "Hello, %s!" name

[<EntryPoint>]
let main argv =
    greet "World" 1
    0
