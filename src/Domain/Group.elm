module Domain.Group exposing (Group, Id, Link, UserId)

{-| Group identity, metadata, and configuration.
-}

import Domain.Currency exposing (Currency)
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
