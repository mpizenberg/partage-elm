module Domain.Entry exposing
    ( Beneficiary(..)
    , Category(..)
    , Entry
    , ExpenseData
    , Id
    , Kind(..)
    , Metadata
    , Payer
    , TransferData
    , newMetadata
    , replace
    )

{-| Ledger entries (expenses and transfers) with versioning metadata.
-}

import Domain.Currency exposing (Currency)
import Domain.Date exposing (Date)
import Domain.Member as Member
import Time


{-| Unique identifier for an entry (expense or transfer).
-}
type alias Id =
    String


{-| An entry in the group ledger, combining version metadata with its content.
-}
type alias Entry =
    { meta : Metadata
    , kind : Kind
    }


{-| Helper function to link a new entry to the previous one it replaces.
-}
replace : Metadata -> Id -> Kind -> Entry
replace previousMetadata newId modified =
    { meta = { previousMetadata | id = newId, previousVersionId = Just previousMetadata.id }
    , kind = modified
    }


{-| Version metadata for an entry. Entries form a version chain via rootId
and previousVersionId for conflict resolution.
-}
type alias Metadata =
    { id : Id
    , rootId : Id
    , previousVersionId : Maybe Id
    , isDeleted : Bool
    , createdBy : Member.Id
    , createdAt : Time.Posix
    }


{-| Create metadata for a new entry. Sets rootId equal to id
and previousVersionId to Nothing.
-}
newMetadata : Id -> Member.Id -> Time.Posix -> Metadata
newMetadata id memberId creationTime =
    { id = id
    , rootId = id
    , previousVersionId = Nothing
    , isDeleted = False
    , createdBy = memberId
    , createdAt = creationTime
    }


{-| The content of an entry: either a shared expense or a direct transfer.
-}
type Kind
    = Expense ExpenseData
    | Transfer TransferData


{-| Data for a shared expense: who paid, how much, and how it is split.
Amounts are in the smallest currency unit (e.g. cents).
-}
type alias ExpenseData =
    { description : String
    , amount : Int
    , currency : Currency
    , defaultCurrencyAmount : Maybe Int
    , date : Date
    , payers : List Payer
    , beneficiaries : List Beneficiary
    , category : Maybe Category
    , location : Maybe String
    , notes : Maybe String
    }


{-| Data for a direct money transfer between two members.
-}
type alias TransferData =
    { amount : Int
    , currency : Currency
    , defaultCurrencyAmount : Maybe Int
    , date : Date
    , from : Member.Id
    , to : Member.Id
    , notes : Maybe String
    }


{-| A member who paid part (or all) of an expense.
-}
type alias Payer =
    { memberId : Member.Id
    , amount : Int
    }


{-| How a member benefits from an expense.
ShareBeneficiary splits proportionally by share count.
ExactBeneficiary assigns a fixed amount.
-}
type Beneficiary
    = ShareBeneficiary { memberId : Member.Id, shares : Int }
    | ExactBeneficiary { memberId : Member.Id, amount : Int }


{-| Expense category for filtering and reporting.
-}
type Category
    = Food
    | Transport
    | Accommodation
    | Entertainment
    | Shopping
    | Groceries
    | Utilities
    | Healthcare
    | Other
