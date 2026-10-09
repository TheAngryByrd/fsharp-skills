namespace Shop.Products

type Product = { Sku: string; Price: decimal }

module Product =
    let display (p: Product) = $"{p.Sku} at {p.Price}"
