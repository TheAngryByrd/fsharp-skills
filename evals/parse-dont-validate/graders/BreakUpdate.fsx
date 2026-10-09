#load "Registration.fsx"
open Registration

let bypass (reg: Registration) = { reg with Age = 5 }
