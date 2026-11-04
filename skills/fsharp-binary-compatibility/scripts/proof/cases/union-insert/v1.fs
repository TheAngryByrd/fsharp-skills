module Lib

type OrderState =
    | Pending
    | Paid
    | Shipped
    | Delivered
    | Cancelled
