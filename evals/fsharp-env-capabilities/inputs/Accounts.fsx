open System

type IUserStore =
    abstract Save: userId: int * salt: byte[] * hash: string -> unit

type IProvideUserStore =
    abstract Users: IUserStore

type ILogger =
    abstract Info: string -> unit

type IProvideLogger =
    abstract Logger: ILogger

type IProvideRandom =
    abstract Random: Random

type IProvideClock =
    abstract Now: unit -> DateTimeOffset

module Log =
    let info (env: #IProvideLogger) (message: string) = env.Logger.Info message

module Users =
    let save (env: #IProvideUserStore) userId salt hash = env.Users.Save(userId, salt, hash)

module Salt =
    let create (env: #IProvideRandom) (length: int) =
        let bytes = Array.zeroCreate<byte> length
        env.Random.NextBytes bytes
        bytes

let hashPassword (salt: byte[]) (password: string) =
    let bytes = Array.append salt (Text.Encoding.UTF8.GetBytes password)
    Convert.ToHexString(Security.Cryptography.SHA256.HashData bytes).Substring(0, 16)

let changePassword env (userId: int) (password: string) =
    let salt = Salt.create env 16
    let hash = hashPassword salt password
    Users.save env userId salt hash
    Log.info env $"password changed for {userId}"
    salt, hash

let stamp env = (env :> IProvideClock).Now()

type ProductionEnv() =
    let random = Random()

    interface IProvideUserStore with
        member _.Users =
            { new IUserStore with
                member _.Save(userId, _, _) = printfn "saved user %d" userId }

    interface IProvideLogger with
        member _.Logger =
            { new ILogger with
                member _.Info message = printfn "log: %s" message }

    interface IProvideRandom with
        member _.Random = random

    interface IProvideClock with
        member _.Now() = DateTimeOffset.UtcNow

let salt, _ = changePassword (ProductionEnv()) 7 "hunter2"
printfn "production salt length: %d" salt.Length
