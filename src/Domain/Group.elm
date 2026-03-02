module Domain.Group exposing (Id, Link, UserId, encodeLink, linkDecoder)

{-| Group identity, metadata, and configuration.
-}

import Json.Decode as Decode
import Json.Encode as Encode


{-| Unique identifier for a group.
-}
type alias Id =
    String


{-| Unique identifier for an authenticated user (distinct from Member.Id).
-}
type alias UserId =
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
        [ ( "label", Encode.string link.label )
        , ( "url", Encode.string link.url )
        ]


{-| Decode a Link from JSON.
-}
linkDecoder : Decode.Decoder Link
linkDecoder =
    Decode.map2 Link
        (Decode.field "label" Decode.string)
        (Decode.field "url" Decode.string)
