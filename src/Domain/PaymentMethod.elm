module Domain.PaymentMethod exposing (Method(..), PaymentInfo, decoder, empty, encode, get, set)

{-| Payment handles a member shares for receiving settlements.

Storage is open — a flat map of wire key to handle — so a handle written by a
newer version survives a round trip through this one instead of being erased on
the next edit. The set of methods this version _knows_ is closed (`Method`), and
the wire keys naming them never leave this module.

-}

import Dict exposing (Dict)
import Json.Decode as Decode
import Json.Encode as Encode


type Method
    = Iban
    | Wero
    | Lydia
    | Revolut
    | Paypal
    | Venmo
    | Cashapp
    | Btc
    | Ada


type alias PaymentInfo =
    Dict String String


empty : PaymentInfo
empty =
    Dict.empty


get : Method -> PaymentInfo -> Maybe String
get method =
    Dict.get (toKey method)


{-| A blank handle is an absent one: no key ever holds an empty value, so
"unset" has a single representation and comparing two PaymentInfo means what it
looks like it means.
-}
set : Method -> Maybe String -> PaymentInfo -> PaymentInfo
set method value info =
    case Maybe.andThen normalize value of
        Just handle ->
            Dict.insert (toKey method) handle info

        Nothing ->
            Dict.remove (toKey method) info


encode : PaymentInfo -> Encode.Value
encode =
    Encode.dict identity Encode.string


{-| A handle whose shape this version cannot hold is dropped rather than failing
the whole object, so one unreadable method never costs the others.
-}
decoder : Decode.Decoder PaymentInfo
decoder =
    Decode.keyValuePairs (Decode.maybe Decode.string)
        |> Decode.map
            (List.filterMap (\( key, value ) -> Maybe.map (Tuple.pair key) (Maybe.andThen normalize value))
                >> Dict.fromList
            )


normalize : String -> Maybe String
normalize raw =
    case String.trim raw of
        "" ->
            Nothing

        handle ->
            Just handle


toKey : Method -> String
toKey method =
    case method of
        Iban ->
            "ib"

        Wero ->
            "we"

        Lydia ->
            "ly"

        Revolut ->
            "rv"

        Paypal ->
            "pp"

        Venmo ->
            "vn"

        Cashapp ->
            "ca"

        Btc ->
            "btc"

        Ada ->
            "ada"
