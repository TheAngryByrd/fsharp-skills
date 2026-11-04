module Lib

let evens (limit: int) : seq<int> =
    [ for i in 0..limit do
          if i % 2 = 0 then
              yield i ]
