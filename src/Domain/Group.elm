module Domain.Group exposing (Group, Id, Link, UserId)

import Domain.Currency exposing (Currency)
import Time


type alias Id =
    String


type alias UserId =
    String


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


type alias Link =
    { label : String
    , url : String
    }
