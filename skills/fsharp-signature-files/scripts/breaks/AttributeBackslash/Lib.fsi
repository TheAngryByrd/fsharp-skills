// expect: FS1200
// expect-exit: 0
// expect-text: the attribute arguments differ
module Lib

[<System.ComponentModel.Description ("C:\temp\orders")>]
val ordersFolder: int
