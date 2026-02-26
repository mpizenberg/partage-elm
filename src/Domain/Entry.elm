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


type alias Metadata =
    { id : Id
    , rootId : Id
    , previousVersionId : Maybe Id
    , notes : Maybe String
    , isDeleted : Bool
    , createdBy : Member.Id
    , createdAt : Time.Posix
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
    }


type alias TransferData =
    { amount : Int
    , currency : Currency
    , defaultCurrencyAmount : Maybe Int
    , date : Date
    , from : Member.Id
    , to : Member.Id
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
