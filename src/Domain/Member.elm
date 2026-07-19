module Domain.Member exposing (DeviceLink, Id, Metadata, PaymentInfo, State, Type(..), emptyMetadata, emptyPaymentInfo, encodeMetadata, encodePaymentInfo, encodeType, metadataDecoder, paymentInfoDecoder, pickLink, typeDecoder)

{-| Group members, their lifecycle, and contact metadata.
-}

import Json.Decode as Decode
import Json.Encode as Encode
import Time


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


{-| A member's computed state. The rootId identifies the person; the devices
claiming it live in the group-level device-link map. `memberType` is the
effective type: Real when created real or currently claimed by a device.
`publicKey` is the creating device's key, empty for virtual members.
-}
type alias State =
    { rootId : Id
    , name : String
    , memberType : Type
    , publicKey : String
    , isRetired : Bool
    , joinedAt : Time.Posix
    , metadata : Metadata
    }


{-| A device's claim on a member root. The group state keeps one per device:
its winning link, resolved by `pickLink`.
-}
type alias DeviceLink =
    { rootId : Id
    , publicKey : String
    , seq : Int
    , timestamp : Time.Posix
    , eventId : String
    }


{-| Pick the winning link between two claims by the same device.
Higher (seq, timestamp, event id) wins — seq keeps a device's own re-links
robust to its clock jumping backwards; the unique event id makes the order total.
-}
pickLink : DeviceLink -> DeviceLink -> DeviceLink
pickLink a b =
    if
        ( a.seq, Time.posixToMillis a.timestamp, a.eventId )
            >= ( b.seq, Time.posixToMillis b.timestamp, b.eventId )
    then
        a

    else
        b


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


{-| Encode a member Type as a JSON string.
-}
encodeType : Type -> Encode.Value
encodeType memberType =
    Encode.string
        (case memberType of
            Real ->
                "real"

            Virtual ->
                "virtual"
        )


{-| Decode a member Type from a JSON string.
-}
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


{-| Encode PaymentInfo as a JSON object, omitting Nothing fields.
-}
encodePaymentInfo : PaymentInfo -> Encode.Value
encodePaymentInfo info =
    Encode.object
        (List.filterMap identity
            [ Maybe.map (\v -> ( "ib", Encode.string v )) info.iban
            , Maybe.map (\v -> ( "we", Encode.string v )) info.wero
            , Maybe.map (\v -> ( "ly", Encode.string v )) info.lydia
            , Maybe.map (\v -> ( "rv", Encode.string v )) info.revolut
            , Maybe.map (\v -> ( "pp", Encode.string v )) info.paypal
            , Maybe.map (\v -> ( "vn", Encode.string v )) info.venmo
            , Maybe.map (\v -> ( "btc", Encode.string v )) info.btcAddress
            , Maybe.map (\v -> ( "ada", Encode.string v )) info.adaAddress
            ]
        )


{-| Decode PaymentInfo from JSON, with all fields optional.
-}
paymentInfoDecoder : Decode.Decoder PaymentInfo
paymentInfoDecoder =
    Decode.map8 PaymentInfo
        (Decode.maybe (Decode.field "ib" Decode.string))
        (Decode.maybe (Decode.field "we" Decode.string))
        (Decode.maybe (Decode.field "ly" Decode.string))
        (Decode.maybe (Decode.field "rv" Decode.string))
        (Decode.maybe (Decode.field "pp" Decode.string))
        (Decode.maybe (Decode.field "vn" Decode.string))
        (Decode.maybe (Decode.field "btc" Decode.string))
        (Decode.maybe (Decode.field "ada" Decode.string))


{-| Encode member Metadata as a JSON object, omitting Nothing fields.
-}
encodeMetadata : Metadata -> Encode.Value
encodeMetadata meta =
    Encode.object
        (List.filterMap identity
            [ Maybe.map (\v -> ( "ph", Encode.string v )) meta.phone
            , Maybe.map (\v -> ( "em", Encode.string v )) meta.email
            , Maybe.map (\v -> ( "pm", encodePaymentInfo v )) meta.payment
            , Maybe.map (\v -> ( "nt", Encode.string v )) meta.notes
            ]
        )


{-| Decode member Metadata from JSON, with all fields optional.
-}
metadataDecoder : Decode.Decoder Metadata
metadataDecoder =
    Decode.map4 Metadata
        (Decode.maybe (Decode.field "ph" Decode.string))
        (Decode.maybe (Decode.field "em" Decode.string))
        (Decode.maybe (Decode.field "pm" paymentInfoDecoder))
        (Decode.maybe (Decode.field "nt" Decode.string))
