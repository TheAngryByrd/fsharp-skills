namespace Shop.Inventory

open Shop.Products

module Stock =
    let available (onHand: Map<string, int>) (p: Product) = Map.tryFind p.Sku onHand |> Option.defaultValue 0
