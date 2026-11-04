module Domain

type Sku = Sku of string

type OrderStatus =
    | Pending
    | Shipped
    | OnHold

type Payment =
    | Card of last4: string * expiry: string
    | GiftCard of code: string
    | Cash

type Line =
    { Sku: Sku
      Quantity: int
      Note: string option }

type Order =
    { Id: string
      Status: OrderStatus
      Payment: Payment
      Lines: Line list
      Discount: decimal option
      CustomerRef: string option
      Reserved: Map<int, int> }

type Tier =
    | Basic
    | Gold

type Customer =
    { Name: string
      Tier: Tier
      Email: string option }
