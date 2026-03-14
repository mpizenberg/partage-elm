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
    , createdAt : Time.Posix
    , memberCount : Int
    , myBalanceCents : Int
    }


encodeSummary : Summary -> Encode.Value
encodeSummary summary =
    Encode.object
        [ ( "id", Encode.string summary.id )
        , ( "n", Encode.string summary.name )
        , ( "dc", Currency.encodeCurrency summary.defaultCurrency )
        , ( "sub", Encode.bool summary.isSubscribed )
        , ( "ca", Encode.int <| Time.posixToMillis summary.createdAt )
        , ( "mc", Encode.int summary.memberCount )
        , ( "mb", Encode.int summary.myBalanceCents )
        ]


summaryDecoder : Decode.Decoder Summary
summaryDecoder =
    Decode.succeed (\id name dc sub ca mc mb -> { id = id, name = name, defaultCurrency = dc, isSubscribed = sub, createdAt = ca, memberCount = mc, myBalanceCents = mb })
        |> andMap (Decode.field "id" Decode.string)
        |> andMap (Decode.field "n" Decode.string)
        |> andMap (Decode.field "dc" Currency.currencyDecoder)
        |> andMap (Decode.field "sub" Decode.bool)
        |> andMap (Decode.field "ca" Decode.int |> Decode.map Time.millisToPosix)
        |> andMap (Decode.field "mc" Decode.int)
        |> andMap (Decode.field "mb" Decode.int)


andMap : Decode.Decoder a -> Decode.Decoder (a -> b) -> Decode.Decoder b
andMap =
    Decode.map2 (|>)
