module Orders

type OrderLine =
    { Sku: string
      Quantity: int
      UnitPrice: decimal }

let total (lines: OrderLine list) =
    lines |> List.sumBy (fun line -> decimal line.Quantity * line.UnitPrice)
