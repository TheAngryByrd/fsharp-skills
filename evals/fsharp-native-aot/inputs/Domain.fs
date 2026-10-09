module Domain

// Representative sample. The real library has about 60 record types like these.

type Address =
    { Street: string
      City: string
      PostCode: string option }

type Contact =
    { Name: string
      Email: string option
      Age: int option
      Addresses: Address list }

type Account =
    { Id: int
      Owner: Contact
      Tags: string list
      Balance: decimal
      ParentId: int option }
