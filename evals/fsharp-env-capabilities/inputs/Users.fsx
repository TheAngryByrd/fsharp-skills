#nowarn "3535"

type IDatabase =
    abstract Query: id: int -> string option

type IProvideDatabase =
    abstract Database: IDatabase

type ILogger =
    abstract Info: string -> unit

type IProvideLogger =
    abstract Logger: ILogger

type UserError<'e> =
    static abstract UserNotFound: id: int -> 'e

module Log =
    let info (env: #IProvideLogger) (message: string) = env.Logger.Info message

module Db =
    let fetchUser<'e when UserError<'e>> (env: #IProvideDatabase) (id: int) : Result<string, 'e> =
        match env.Database.Query id with
        | Some name -> Ok name
        | None -> Error('e.UserNotFound id)

let greetUser env id =
    Db.fetchUser env id
    |> Result.map (fun name ->
        Log.info env $"greeted {id}"
        $"hello {name}")

type GreetError =
    | UserNotFound of id: int

    interface UserError<GreetError> with
        static member UserNotFound id = UserNotFound id

let users = Map.ofList [ (1, "ann"); (2, "bob") ]

let database =
    { new IDatabase with
        member _.Query id = Map.tryFind id users }

let consoleLogger =
    { new ILogger with
        member _.Info message = printfn "log: %s" message }

type AppEnv() =
    interface IProvideDatabase with
        member _.Database = database

    interface IProvideLogger with
        member _.Logger = consoleLogger

type TestEnv(logged: ResizeArray<string>) =
    interface IProvideDatabase with
        member _.Database = database

    interface IProvideLogger with
        member _.Logger =
            { new ILogger with
                member _.Info message = logged.Add message }

let show (outcome: Result<string, GreetError>) =
    match outcome with
    | Ok text -> text
    | Error(UserNotFound id) -> $"no user {id}"

let logged = ResizeArray<string>()
printfn "test: %s" (show (greetUser (TestEnv logged) 1))
printfn "test: %s" (show (greetUser (TestEnv logged) 9))
printfn "test log: %s" (String.concat "," logged)
printfn "app: %s" (show (greetUser (AppEnv()) 2))
