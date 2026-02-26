module Domain.Member exposing (Id, Member, Metadata, PaymentInfo, Type(..))


type Id
    = Id String


type Type
    = Real
    | Virtual


type alias Member =
    { id : Id
    , rootId : Id
    , previousId : Maybe Id
    , name : String
    , memberType : Type
    , isRetired : Bool
    , isReplaced : Bool
    , isActive : Bool
    , metadata : Metadata
    }


type alias Metadata =
    { phone : Maybe String
    , email : Maybe String
    , payment : Maybe PaymentInfo
    , notes : Maybe String
    }


type alias PaymentInfo =
    { iban : Maybe String
    , wero : Maybe String
    , lydia : Maybe String
    , revolut : Maybe String
    , paypal : Maybe String
    , venmo : Maybe String
    , btcAddress : Maybe String
    , adaAddress : Maybe String
    }
