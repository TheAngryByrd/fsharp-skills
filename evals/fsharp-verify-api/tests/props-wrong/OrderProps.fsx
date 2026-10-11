#r "nuget: FsCheck, 3.4.0"
#load "Orders.fsx"

open Orders
open FsCheck
open FsCheck.FSharp

let private line skus price =
    gen {
        let! sku = Gen.elements skus
        let! quantity = Gen.choose (1, 10)
        let! p = price
        return { Sku = sku; Quantity = quantity; UnitPrice = decimal p }
    }

let lineGen: Gen<OrderLine> = line [ "A1" ] (Gen.elements [ 0; 50 ])

let orderArb: Arbitrary<OrderLine list> =
    Arb.fromGen (Gen.oneof [ Gen.constant []; Gen.nonEmptyListOf (line [ "A1"; "B2"; "C3" ] (Gen.choose (1, 100))) ])

let sampleLines (count: int) : OrderLine list = Gen.sample count lineGen |> List.ofArray

let checkTotal (totalOf: OrderLine list -> decimal) : unit =
    let property =
        Prop.forAll (Arb.fromGen (Gen.nonEmptyListOf (line [ "A1"; "B2"; "C3" ] (Gen.choose (1, 100))))) (fun lines ->
            totalOf lines = (lines |> List.sumBy (fun l -> decimal l.Quantity * l.UnitPrice)))
    Check.One(Config.Quick.WithMaxTest 100, property)
