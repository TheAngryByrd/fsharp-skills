module Lib

let firstOr fallback items =
    match items with
    | [] -> fallback
    | first :: _ -> first
