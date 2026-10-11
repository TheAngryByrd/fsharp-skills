type OrderLine =
    { Sku: string
      Quantity: int
      UnitPrice: decimal
      InStock: bool }

type Order =
    { Id: string
      Customer: string
      DiscountCode: string
      Lines: OrderLine list }
