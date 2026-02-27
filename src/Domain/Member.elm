module Domain.Member exposing (Id, Member, Metadata, PaymentInfo, Type(..), emptyMetadata, emptyPaymentInfo, encodeMetadata, encodePaymentInfo, encodeType, metadataDecoder, paymentInfoDecoder, typeDecoder)

{-| Group members, their lifecycle, and contact metadata.
-}

import Json.Decode as Decode
import Json.Encode as Encode


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


encodeType : Type -> Encode.Value
encodeType memberType =
    Encode.string
        (case memberType of
            Real ->
                "real"

            Virtual ->
                "virtual"
        )


typeDecoder : Decode.Decoder Type
typeDecoder =
    Decode.string
        |> Decode.andThen
            (\s ->
                case s of
                    "real" ->
                        Decode.succeed Real

                    "virtual" ->
                        Decode.succeed Virtual

                    _ ->
                        Decode.fail ("Unknown member type: " ++ s)
            )


encodePaymentInfo : PaymentInfo -> Encode.Value
encodePaymentInfo info =
    Encode.object
        (List.filterMap identity
            [ Maybe.map (\v -> ( "iban", Encode.string v )) info.iban
            , Maybe.map (\v -> ( "wero", Encode.string v )) info.wero
            , Maybe.map (\v -> ( "lydia", Encode.string v )) info.lydia
            , Maybe.map (\v -> ( "revolut", Encode.string v )) info.revolut
            , Maybe.map (\v -> ( "paypal", Encode.string v )) info.paypal
            , Maybe.map (\v -> ( "venmo", Encode.string v )) info.venmo
            , Maybe.map (\v -> ( "btcAddress", Encode.string v )) info.btcAddress
            , Maybe.map (\v -> ( "adaAddress", Encode.string v )) info.adaAddress
            ]
        )


paymentInfoDecoder : Decode.Decoder PaymentInfo
paymentInfoDecoder =
    Decode.map8 PaymentInfo
        (Decode.maybe (Decode.field "iban" Decode.string))
        (Decode.maybe (Decode.field "wero" Decode.string))
        (Decode.maybe (Decode.field "lydia" Decode.string))
        (Decode.maybe (Decode.field "revolut" Decode.string))
        (Decode.maybe (Decode.field "paypal" Decode.string))
        (Decode.maybe (Decode.field "venmo" Decode.string))
        (Decode.maybe (Decode.field "btcAddress" Decode.string))
        (Decode.maybe (Decode.field "adaAddress" Decode.string))


encodeMetadata : Metadata -> Encode.Value
encodeMetadata meta =
    Encode.object
        (List.filterMap identity
            [ Maybe.map (\v -> ( "phone", Encode.string v )) meta.phone
            , Maybe.map (\v -> ( "email", Encode.string v )) meta.email
            , Maybe.map (\v -> ( "payment", encodePaymentInfo v )) meta.payment
            , Maybe.map (\v -> ( "notes", Encode.string v )) meta.notes
            ]
        )


metadataDecoder : Decode.Decoder Metadata
metadataDecoder =
    Decode.map4 Metadata
        (Decode.maybe (Decode.field "phone" Decode.string))
        (Decode.maybe (Decode.field "email" Decode.string))
        (Decode.maybe (Decode.field "payment" paymentInfoDecoder))
        (Decode.maybe (Decode.field "notes" Decode.string))
