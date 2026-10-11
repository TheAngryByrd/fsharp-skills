#r "nuget: FsCheck, 3.4.0"
#load "Orders.fsx"

open Orders
open FsCheck
open FsCheck.FSharp

let lineGen: Gen<OrderLine> =
    gen {
        let! sku = Gen.elements [ "A1"; "B2"; "C3" ]
        let! quantity = Gen.frequency [ 9, Gen.constant 1; 1, Gen.constant 2 ]
        let! price = Gen.elements [ 1; 100 ]
        return { Sku = sku; Quantity = quantity; UnitPrice = decimal price }
    }

let orderArb: Arbitrary<OrderLine list> = Arb.fromGen (Gen.nonEmptyListOf lineGen)

let sampleLines (count: int) : OrderLine list = Gen.sample count lineGen |> List.ofArray

let checkTotal (totalOf: OrderLine list -> decimal) : unit =
    let property =
        Prop.forAll orderArb (fun lines ->
            totalOf lines = (lines |> List.sumBy (fun l -> decimal l.Quantity * l.UnitPrice)))
    Check.One(Config.QuickThrowOnFailure.WithMaxTest 250, property)

