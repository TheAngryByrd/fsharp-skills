namespace Shop.Customers

type Customer = { Id: int; Name: string; Tier: int }

module Customer =
    let display (c: Customer) = $"{c.Name} (tier {c.Tier})"
