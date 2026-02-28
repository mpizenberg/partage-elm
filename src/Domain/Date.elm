module Domain.Date exposing (Date, dateDecoder, encodeDate, posixToDate, toString)

{-| Simple calendar date type for entries.
-}

import Json.Decode as Decode
import Json.Encode as Encode
import Time


{-| A simple calendar date with year, month, and day components.
Amounts in entries are integers (cents), and dates use this plain record
rather than `Time.Posix` since only the calendar date matters for entries.
-}
type alias Date =
    { year : Int
    , month : Int
    , day : Int
    }


encodeDate : Date -> Encode.Value
encodeDate date =
    Encode.object
        [ ( "year", Encode.int date.year )
        , ( "month", Encode.int date.month )
        , ( "day", Encode.int date.day )
        ]


dateDecoder : Decode.Decoder Date
dateDecoder =
    Decode.map3 Date
        (Decode.field "year" Decode.int)
        (Decode.field "month" Decode.int)
        (Decode.field "day" Decode.int)


{-| Format a date as "YYYY-MM-DD".
-}
toString : Date -> String
toString date =
    String.fromInt date.year
        ++ "-"
        ++ String.padLeft 2 '0' (String.fromInt date.month)
        ++ "-"
        ++ String.padLeft 2 '0' (String.fromInt date.day)


posixToDate : Time.Posix -> Date
posixToDate posix =
    { year = Time.toYear Time.utc posix
    , month = monthToInt (Time.toMonth Time.utc posix)
    , day = Time.toDay Time.utc posix
    }


monthToInt : Time.Month -> Int
monthToInt month =
    case month of
        Time.Jan ->
            1

        Time.Feb ->
            2

        Time.Mar ->
            3

        Time.Apr ->
            4

        Time.May ->
            5

        Time.Jun ->
            6

        Time.Jul ->
            7

        Time.Aug ->
            8

        Time.Sep ->
            9

        Time.Oct ->
            10

        Time.Nov ->
            11

        Time.Dec ->
            12
