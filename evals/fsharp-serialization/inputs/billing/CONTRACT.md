# Billing service order JSON

The billing service sends and accepts orders in this JSON shape.
The files in `samples/billing/` are orders that the billing service sent.

- Property names are camelCase: `id`, `status`, `payment`, `lines`, `discount`, `customerRef`, `reserved`, `sku`, `quantity`, `note`.
- `status` is a string: `"pending"`, `"shipped"`, or `"on_hold"`.
- `payment` is an object. Its `kind` property names the payment type: `"card"`, `"gift_card"`, or `"cash"`. The other properties hold the payment data:
  - card: `{"kind": "card", "last4": "4242", "expiry": "12/27"}`
  - gift card: `{"kind": "gift_card", "code": "GC-100"}`
  - cash: `{"kind": "cash"}`
- `sku` is a plain string.
- `reserved` is an object. Each key is a warehouse number as a string, and each value is a quantity: `{"12": 3}`.
- `discount`, `customerRef`, and `note` are optional. The billing service leaves out an optional property or sends `null` when it has no value. Both mean no value. When we send an order, we leave out each optional property that has no value. We never send `null`.
- All other properties are required. An order with a required property that is missing or `null` is not valid.
- The billing service adds new properties over time. Ignore properties that this contract does not name.
- A `status` or payment `kind` that this contract does not name is not valid.
