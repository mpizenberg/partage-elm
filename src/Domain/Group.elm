module Domain.Group exposing (Id, Link, Summary, encodeLink, encodeSummary, linkDecoder, summaryDecoder)

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

    -- Set when this group was abandoned to a migration (spec §11.7): the id of
    -- the fresh group that replaced it. The old group is then read-only.
    , supersededBy : Maybe Id
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
        , ( "sup", Maybe.withDefault Encode.null (Maybe.map Encode.string summary.supersededBy) )
        ]


summaryDecoder : Decode.Decoder Summary
summaryDecoder =
    Decode.succeed (\id name dc sub ar ca mc mb ls sup -> { id = id, name = name, defaultCurrency = dc, isSubscribed = sub, isArchived = ar, createdAt = ca, memberCount = mc, myBalanceCents = mb, lastSyncedAt = Maybe.withDefault ca ls, supersededBy = sup })
        |> andMap (Decode.field "id" Decode.string)
        |> andMap (Decode.field "n" Decode.string)
        |> andMap (Decode.field "dc" Currency.currencyDecoder)
        |> andMap (Decode.field "sub" Decode.bool)
        |> andMap (Decode.field "ar" Decode.bool)
        |> andMap (Decode.field "ca" Decode.int |> Decode.map Time.millisToPosix)
        |> andMap (Decode.field "mc" Decode.int)
        |> andMap (Decode.field "mb" Decode.int)
        |> andMap (Decode.maybe (Decode.field "ls" Decode.int |> Decode.map Time.millisToPosix))
        |> andMap (Decode.maybe (Decode.field "sup" Decode.string))


andMap : Decode.Decoder a -> Decode.Decoder (a -> b) -> Decode.Decoder b
andMap =
    Decode.map2 (|>)
