open System

type RegistrationDto =
    { Email: string
      Age: int
      Username: string }

type Registration =
    { Email: string
      Age: int
      Username: string }

let isValidEmail (email: string) =
    match email.Split '@' with
    | [| local; domain |] -> local.Length > 0 && domain.Contains '.' && not (domain.StartsWith '.')
    | _ -> false

let isValidAge (age: int) = age >= 13 && age <= 120

let isValidUsername (name: string) =
    name.Length >= 3 && name.Length <= 20 && name |> Seq.forall Char.IsAsciiLetterOrDigit

let fromDto (dto: RegistrationDto) : Registration =
    { Email = dto.Email
      Age = dto.Age
      Username = dto.Username }

let validate (r: Registration) =
    [ if not (isValidEmail r.Email) then $"invalid email {r.Email}"
      if not (isValidAge r.Age) then $"invalid age {r.Age}"
      if not (isValidUsername r.Username) then $"invalid username {r.Username}" ]

let changeEmail (r: Registration) (newEmail: string) = { r with Email = newEmail }

let sendWelcome (email: string) =
    if not (isValidEmail email) then
        failwith $"cannot send to {email}"

    $"welcome mail to {email}"

let register (r: Registration) =
    match validate r with
    | [] -> sendWelcome r.Email
    | errors -> failwith (String.concat "; " errors)
