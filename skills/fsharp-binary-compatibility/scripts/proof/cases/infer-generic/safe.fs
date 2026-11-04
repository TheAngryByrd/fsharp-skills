module Lib

let firstOr (fallback: int) (items: int list) : int =
    match items with
    | [] -> fallback
    | first :: _ -> first
