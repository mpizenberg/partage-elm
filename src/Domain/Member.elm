module Domain.Member exposing (Id, Member, Metadata, PaymentInfo, Type(..), emptyMetadata, emptyPaymentInfo)

{-| Group members, their lifecycle, and contact metadata.
-}


{-| Unique identifier for a member within a group.
-}
type alias Id =
    String


{-| Whether a member is a real person or a virtual placeholder
(e.g. for someone not yet registered).
-}
type Type
    = Real
    | Virtual


{-| A group member with identity, lifecycle state, and contact metadata.
Members form replacement chains via rootId/previousId.
-}
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


{-| Optional contact and payment information for a member.
-}
type alias Metadata =
    { phone : Maybe String
    , email : Maybe String
    , payment : Maybe PaymentInfo
    , notes : Maybe String
    }


{-| Payment method details a member can share for receiving settlements.
-}
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


{-| A Metadata with all fields set to Nothing.
-}
emptyMetadata : Metadata
emptyMetadata =
    { phone = Nothing
    , email = Nothing
    , payment = Nothing
    , notes = Nothing
    }


{-| A PaymentInfo with all fields set to Nothing.
-}
emptyPaymentInfo : PaymentInfo
emptyPaymentInfo =
    { iban = Nothing
    , wero = Nothing
    , lydia = Nothing
    , revolut = Nothing
    , paypal = Nothing
    , venmo = Nothing
    , btcAddress = Nothing
    , adaAddress = Nothing
    }
