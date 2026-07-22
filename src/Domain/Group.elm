module Domain.Group exposing (Id, Link, Summary, SyncCursor, encodeLink, encodeSummary, linkDecoder, summaryDecoder)

{-| Group identity, metadata, and configuration.
-}

import Domain.Currency as Currency exposing (Currency)
import Json.Decode as Decode
import Json.Encode as Encode
import Time


{-| Unique identifier for a group.
-}
type alias Id =
    String


{-| A device's sync position within one relay-side incarnation of the group.
`seq` is only meaningful under `epoch` (the relay group row's creation stamp):
a purge-and-resurrection mints a new epoch, and any seq from an older epoch
must be discarded — new records can land above a stale seq, so seq arithmetic
alone cannot detect the loss. The two therefore travel as one value.
-}
type alias SyncCursor =
    { seq : Int
    , epoch : String
    }


{-| An external link attached to a group (e.g. shared document, planning page).
-}
type alias Link =
    { label : String
    , url : String
    }


{-| Encode a Link as a JSON value.
-}
encodeLink : Link -> Encode.Value
encodeLink link =
    Encode.object
        [ ( "l", Encode.string link.label )
        , ( "u", Encode.string link.url )
        ]


{-| Decode a Link from JSON.
-}
linkDecoder : Decode.Decoder Link
linkDecoder =
    Decode.map2 Link
        (Decode.field "l" Decode.string)
        (Decode.field "u" Decode.string)


{-| Summary of a group for the home page list.
-}
type alias Summary =
    { id : Id
    , name : String
    , defaultCurrency : Currency
    , isSubscribed : Bool
    , isArchived : Bool
    , createdAt : Time.Posix
    , memberCount : Int
    , myBalanceCents : Int

    -- When this client last synced/created/imported/joined the group. Drives
    -- the home-list "dormant" hint, a proxy for the relay's inactivity purge
    -- (docs/SPECIFICATION.md §14.8) that the home list can read without
    -- loading events.
    , lastSyncedAt : Time.Posix
    }


encodeSummary : Summary -> Encode.Value
encodeSummary summary =
    Encode.object
        [ ( "id", Encode.string summary.id )
        , ( "n", Encode.string summary.name )
        , ( "dc", Currency.encodeCurrency summary.defaultCurrency )
        , ( "sub", Encode.bool summary.isSubscribed )
        , ( "ar", Encode.bool summary.isArchived )
        , ( "ca", Encode.int <| Time.posixToMillis summary.createdAt )
        , ( "mc", Encode.int summary.memberCount )
        , ( "mb", Encode.int summary.myBalanceCents )
        , ( "ls", Encode.int <| Time.posixToMillis summary.lastSyncedAt )
        ]


summaryDecoder : Decode.Decoder Summary
summaryDecoder =
    Decode.succeed (\id name dc sub ar ca mc mb ls -> { id = id, name = name, defaultCurrency = dc, isSubscribed = sub, isArchived = ar, createdAt = ca, memberCount = mc, myBalanceCents = mb, lastSyncedAt = Maybe.withDefault ca ls })
        |> andMap (Decode.field "id" Decode.string)
        |> andMap (Decode.field "n" Decode.string)
        |> andMap (Decode.field "dc" Currency.currencyDecoder)
        |> andMap (Decode.field "sub" Decode.bool)
        |> andMap (Decode.field "ar" Decode.bool)
        |> andMap (Decode.field "ca" Decode.int |> Decode.map Time.millisToPosix)
        |> andMap (Decode.field "mc" Decode.int)
        |> andMap (Decode.field "mb" Decode.int)
        |> andMap (Decode.maybe (Decode.field "ls" Decode.int |> Decode.map Time.millisToPosix))


andMap : Decode.Decoder a -> Decode.Decoder (a -> b) -> Decode.Decoder b
andMap =
    Decode.map2 (|>)
