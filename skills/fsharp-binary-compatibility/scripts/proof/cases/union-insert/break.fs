module Lib

type OrderState =
    | Pending
    | Paid
    | Refunded
    | Shipped
    | Delivered
    | Cancelled
