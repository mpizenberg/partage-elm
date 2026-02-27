module Domain.Date exposing (Date, dateDecoder, encodeDate)

{-| Simple calendar date type for entries.
-}

import Json.Decode as Decode
import Json.Encode as Encode


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
