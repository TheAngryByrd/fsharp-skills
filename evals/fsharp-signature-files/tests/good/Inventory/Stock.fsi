namespace Inventory

/// How much stock is left for a SKU.
[<RequireQualifiedAccess>]
type StockLevel =
    | OutOfStock
    | Low
    | Healthy

/// One line of a stock file.
type StockItem = { Sku: Sku; OnHand: Quantity }

module Stock =
    /// Classifies a quantity: 0 is OutOfStock, 1 to 5 is Low, and more is Healthy.
    val classify: onHand: Quantity -> StockLevel

    /// Parses a stock line with the shape "SKU,count", for example "ABC-1234,12".
    val parseLine: line: string -> Result<StockItem, string>

/// Keeps the quantity on hand for each SKU while it is open.
type StockLedger =
    interface System.IDisposable

    new: unit -> StockLedger

    /// Adds received units to the quantity on hand.
    member Receive: sku: Sku * units: Quantity -> unit

    /// The quantity on hand. It is zero for a SKU that the ledger has not received.
    member OnHand: sku: Sku -> Quantity
