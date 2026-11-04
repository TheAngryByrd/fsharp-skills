module Lib

type OrderState =
    | Pending
    | Paid
    | Shipped

let history (orderId: int) : OrderState list =
    if orderId > 0 then [ Pending; Paid; Shipped ] else []
