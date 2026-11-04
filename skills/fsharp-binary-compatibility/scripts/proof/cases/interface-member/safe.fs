module Lib

type IPricer =
    abstract Price: quantity: int -> decimal

type ICurrencyPricer =
    inherit IPricer
    abstract Currency: string

let total (pricer: IPricer) (quantities: int list) : decimal =
    quantities |> List.sumBy pricer.Price

let currencyOf (pricer: IPricer) : string =
    match pricer with
    | :? ICurrencyPricer as p -> p.Currency
    | _ -> "USD"
