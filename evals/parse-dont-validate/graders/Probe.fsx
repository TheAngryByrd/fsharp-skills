#load "Registration.fsx"

open Microsoft.FSharp.Reflection
open Registration

let caseOf (value: obj) =
    if isNull value then "null"
    elif value :? exn then "exception"
    elif FSharpType.IsUnion(value.GetType(), true) && value.GetType().Name.StartsWith "FSharpResult" then
        (fst (FSharpValue.GetUnionFields(value, value.GetType(), true))).Name
    else "value"

let payload (value: obj) = (snd (FSharpValue.GetUnionFields(value, value.GetType(), true))).[0]

let attempt f = try box (f ()) with ex -> box ex

let dto email age name : RegistrationDto = { Email = email; Age = age; Username = name }

let report name (passed: bool) (detail: string) =
    System.Console.WriteLine((if passed then "PASS " else "FAIL ") + name + (if passed then "" else " [" + detail + "]"))

let valid = attempt (fun () -> fromDto (dto "ann@example.com" 30 "ann"))
report "fromDto accepts a valid registration" (caseOf valid = "Ok") (caseOf valid)

for (name, email, age, user) in
    [ "fromDto rejects a bad email", "ann", 30, "ann"
      "fromDto rejects age 12", "ann@example.com", 12, "ann"
      "fromDto rejects age 121", "ann@example.com", 121, "ann"
      "fromDto rejects a short username", "ann@example.com", 30, "an"
      "fromDto rejects a username with symbols", "ann@example.com", 30, "ann!" ] do
    let r = attempt (fun () -> fromDto (dto email age user))
    report name (caseOf r = "Error") (caseOf r)

for (name, age) in [ "fromDto accepts age 13", 13; "fromDto accepts age 120", 120 ] do
    let r = attempt (fun () -> fromDto (dto "ann@example.com" age "ann"))
    report name (caseOf r = "Ok") (caseOf r)

if caseOf valid = "Ok" then
    let reg = payload valid
    let bad = attempt (fun () -> changeEmail (unbox reg) "not-an-email")
    report "changeEmail rejects an invalid email" (caseOf bad = "Error") (caseOf bad)
    let good = attempt (fun () -> changeEmail (unbox reg) "bob@example.com")
    report "changeEmail accepts a valid email" (caseOf good = "Ok" || caseOf good = "value") (caseOf good)
    let mail = attempt (fun () -> register (unbox reg))
    let text = if caseOf mail = "Ok" then string (payload mail) else string mail
    report "register sends the welcome mail" (text = "welcome mail to ann@example.com") text
