namespace Shop.Pricing

open Shop.Products

module Discount =
    let apply (percent: decimal) (p: Product) = clamp 0m p.Price (p.Price * (1m - percent / 100m))
