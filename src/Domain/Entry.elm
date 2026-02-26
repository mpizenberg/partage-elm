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
    )

import Domain.Currency exposing (Currency)
import Domain.Date exposing (Date)
import Domain.Member as Member
import Time


type alias Id =
    String


type alias Entry =
    { meta : Metadata
    , kind : Kind
    }


{-| Helper function to link a new entry to the previous one it replaces.
-}
replace : Entry -> Id -> Kind -> Entry
replace { meta, kind } newId modified =
    { meta = { meta | id = newId, previousVersionId = Just meta.id }
    , kind = modified
    }


type alias Metadata =
    { id : Id
    , rootId : Id
    , previousVersionId : Maybe Id
    , isDeleted : Bool
    , createdBy : Member.Id
    , createdAt : Time.Posix
    }


newMetadata : Id -> Member.Id -> Time.Posix -> Metadata
newMetadata id memberId creationTime =
    { id = id
    , rootId = id
    , previousVersionId = Nothing
    , isDeleted = False
    , createdBy = memberId
    , createdAt = creationTime
    }


type Kind
    = Expense ExpenseData
    | Transfer TransferData


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


type alias TransferData =
    { amount : Int
    , currency : Currency
    , defaultCurrencyAmount : Maybe Int
    , date : Date
    , from : Member.Id
    , to : Member.Id
    , notes : Maybe String
    }


type alias Payer =
    { memberId : Member.Id
    , amount : Int
    }


type Beneficiary
    = ShareBeneficiary { memberId : Member.Id, shares : Int }
    | ExactBeneficiary { memberId : Member.Id, amount : Int }


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
