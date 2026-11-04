module Lib

type IPricer =
    abstract Price: quantity: int -> decimal

let total (pricer: IPricer) (quantities: int list) : decimal =
    quantities |> List.sumBy pricer.Price
