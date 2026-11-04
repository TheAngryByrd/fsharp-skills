module Lib

let firstOr fallback items =
    match items with
    | [] -> fallback + 0
    | first :: _ -> first
