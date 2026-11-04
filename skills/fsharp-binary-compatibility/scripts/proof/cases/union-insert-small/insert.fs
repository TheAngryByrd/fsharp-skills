module Lib

type OrderState =
    | Pending
    | Paid of amount: decimal
    | Refunded
    | Shipped
