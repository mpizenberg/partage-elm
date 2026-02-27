module Domain.Group exposing (Group, Id, Link, UserId, encodeLink, linkDecoder)

{-| Group identity, metadata, and configuration.
-}

import Domain.Currency exposing (Currency)
import Json.Decode as Decode
import Json.Encode as Encode
import Time


{-| Unique identifier for a group.
-}
type alias Id =
    String


{-| Unique identifier for an authenticated user (distinct from Member.Id).
-}
type alias UserId =
    String


{-| A shared expense group with its metadata and configuration.
-}
type alias Group =
    { id : Id
    , name : String
    , subtitle : Maybe String
    , description : Maybe String
    , links : List Link
    , defaultCurrency : Currency
    , createdAt : Time.Posix
    , createdBy : UserId
    }


{-| An external link attached to a group (e.g. shared document, planning page).
-}
type alias Link =
    { label : String
    , url : String
    }


encodeLink : Link -> Encode.Value
encodeLink link =
    Encode.object
        [ ( "label", Encode.string link.label )
        , ( "url", Encode.string link.url )
        ]


linkDecoder : Decode.Decoder Link
linkDecoder =
    Decode.map2 Link
        (Decode.field "label" Decode.string)
        (Decode.field "url" Decode.string)
