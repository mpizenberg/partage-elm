module Domain.Member exposing (DeviceLink, Id, JoinAction(..), Metadata, State, Type(..), emptyMetadata, encodeMetadata, encodeType, metadataDecoder, pickLink, shortId, typeDecoder)

{-| Group members, their lifecycle, and contact metadata.
-}

import Dict
import Domain.PaymentMethod as PaymentMethod exposing (PaymentInfo)
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


{-| How a device becomes a member of an existing group.
-}
type JoinAction
    = ClaimMember Id
    | JoinAsNewMember


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


{-| A device/author id abbreviated for display — enough of the hash to tell two
of a member's devices apart and to match against an id someone read out.
-}
shortId : Id -> String
shortId id =
    String.left 12 id


{-| Optional contact and payment information for a member.
-}
type alias Metadata =
    { phone : Maybe String
    , email : Maybe String
    , payment : PaymentInfo
    , notes : Maybe String
    }


{-| A Metadata with nothing provided.
-}
emptyMetadata : Metadata
emptyMetadata =
    { phone = Nothing
    , email = Nothing
    , payment = PaymentMethod.empty
    , notes = Nothing
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


{-| Encode member Metadata as a JSON object, omitting what is not provided.
-}
encodeMetadata : Metadata -> Encode.Value
encodeMetadata meta =
    Encode.object
        (List.filterMap identity
            [ Maybe.map (\v -> ( "ph", Encode.string v )) meta.phone
            , Maybe.map (\v -> ( "em", Encode.string v )) meta.email
            , if Dict.isEmpty meta.payment then
                Nothing

              else
                Just ( "pm", PaymentMethod.encode meta.payment )
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
        (Decode.oneOf [ Decode.field "pm" PaymentMethod.decoder, Decode.succeed PaymentMethod.empty ])
        (Decode.maybe (Decode.field "nt" Decode.string))
