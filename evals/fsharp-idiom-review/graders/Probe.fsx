#load "OrderReport.fsx"

open Domain

// OrderReport.cs formats with InvariantCulture, so a comma-decimal culture must not change the text.
// A cloned culture also works when .NET runs in globalization invariant mode, where "de-DE" throws.
let commaCulture = System.Globalization.CultureInfo.InvariantCulture.Clone() :?> System.Globalization.CultureInfo
commaCulture.NumberFormat.NumberDecimalSeparator <- ","
System.Globalization.CultureInfo.CurrentCulture <- commaCulture

let line sku qty price inStock =
    { Sku = sku; Quantity = qty; UnitPrice = price; InStock = inStock }

let order id customer code lines =
    { Id = id; Customer = customer; DiscountCode = code; Lines = lines }

let normalize (text: string) = text.Replace("\r\n", "\n").TrimEnd('\n')

let check name (o: Order) (expected: string list) =
    let expectedText = String.concat "\n" expected
    let actual =
        try normalize (OrderReport.render o) with ex -> "exception: " + ex.GetType().Name + ": " + ex.Message
    if actual = expectedText then
        System.Console.WriteLine("PASS " + name)
    else
        System.Console.WriteLine("FAIL " + name + " [" + actual.Replace("\n", " | ") + "]")

check "render: discount, three lines, and a backordered line"
    (order "A-1" "Ada" "SAVE10" [ line "W-1" 2 150.00m true; line "G-7" 1 30.50m false; line "B-2" 3 9.99m true ])
    [ "Order A-1 for Ada"
      "1. W-1 x2 @ 150.00"
      "2. G-7 x1 @ 30.50"
      "3. B-2 x3 @ 9.99"
      "Items: 6"
      "Subtotal: 360.47"
      "Discount: -36.05"
      "Total: 324.42 (silver)"
      "Backordered: G-7" ]

check "render: discount rounds a midpoint to even"
    (order "B-2" "Bo" "SAVE25" [ line "P-9" 1 1000.10m true ])
    [ "Order B-2 for Bo"
      "1. P-9 x1 @ 1000.10"
      "Items: 1"
      "Subtotal: 1000.10"
      "Discount: -250.02"
      "Total: 750.08 (silver)" ]

check "render: an order with no lines"
    (order "C-3" "Cy" "" [])
    [ "Order C-3 for Cy"; "Items: 0"; "Subtotal: 0.00"; "Total: 0.00 (bronze)" ]

check "render: a known code with a zero discount prints no discount line"
    (order "F-6" "Fe" "SAVE10" [])
    [ "Order F-6 for Fe"; "Items: 0"; "Subtotal: 0.00"; "Total: 0.00 (bronze)" ]

check "render: a total of exactly 1000 is gold"
    (order "G-7" "Gu" "" [ line "Z-1" 4 250.00m true ])
    [ "Order G-7 for Gu"; "1. Z-1 x4 @ 250.00"; "Items: 4"; "Subtotal: 1000.00"; "Total: 1000.00 (gold)" ]

check "render: an unknown code gives no discount, and 250 is silver"
    (order "D-4" "Di" "BOGUS" [ line "K-1" 1 250.00m true ])
    [ "Order D-4 for Di"; "1. K-1 x1 @ 250.00"; "Items: 1"; "Subtotal: 250.00"; "Total: 250.00 (silver)" ]

check "render: the first backordered line of two, and gold"
    (order "E-5" "Ed" "STAFF" [ line "M-1" 1 1000.00m true; line "M-2" 2 333.33m false; line "M-3" 1 100.00m false ])
    [ "Order E-5 for Ed"
      "1. M-1 x1 @ 1000.00"
      "2. M-2 x2 @ 333.33"
      "3. M-3 x1 @ 100.00"
      "Items: 4"
      "Subtotal: 1766.66"
      "Discount: -706.66"
      "Total: 1060.00 (gold)"
      "Backordered: M-2" ]
