namespace Shop.Reports

open Shop.Customers

module Report =
    let customers (cs: Customer list) = cs |> List.map Customer.display |> String.concat "\n"
