module Domain.Date exposing (Date, addDays, dateDecoder, encodeDate, endOfMonth, posixToDate, previousMonth, startOfMonth, toComparable, toString)

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


{-| Encode a Date as a JSON value.
-}
encodeDate : Date -> Encode.Value
encodeDate date =
    Encode.object
        [ ( "year", Encode.int date.year )
        , ( "month", Encode.int date.month )
        , ( "day", Encode.int date.day )
        ]


{-| Decode a Date from JSON.
-}
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


{-| Convert a POSIX timestamp to a calendar Date using UTC.
-}
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


{-| Convert a Date to a comparable integer (YYYYMMDD).
-}
toComparable : Date -> Int
toComparable date =
    date.year * 10000 + date.month * 100 + date.day


{-| Add (or subtract) days from a date. Handles month/year boundaries.
-}
addDays : Int -> Date -> Date
addDays n date =
    if n == 0 then
        date

    else if n > 0 then
        let
            maxDay : Int
            maxDay =
                daysInMonth date.year date.month
        in
        if date.day + n <= maxDay then
            { date | day = date.day + n }

        else
            let
                remaining : Int
                remaining =
                    n - (maxDay - date.day) - 1

                nextMonth : Date
                nextMonth =
                    if date.month == 12 then
                        { year = date.year + 1, month = 1, day = 1 }

                    else
                        { year = date.year, month = date.month + 1, day = 1 }
            in
            addDays remaining nextMonth

    else if date.day + n >= 1 then
        { date | day = date.day + n }

    else
        let
            prevMonth : Date
            prevMonth =
                if date.month == 1 then
                    { year = date.year - 1, month = 12, day = daysInMonth (date.year - 1) 12 }

                else
                    { year = date.year, month = date.month - 1, day = daysInMonth date.year (date.month - 1) }

            remaining : Int
            remaining =
                n + date.day
        in
        addDays remaining prevMonth


{-| First day of the month.
-}
startOfMonth : Date -> Date
startOfMonth date =
    { date | day = 1 }


{-| Last day of the month.
-}
endOfMonth : Date -> Date
endOfMonth date =
    { date | day = daysInMonth date.year date.month }


{-| Start and end of the previous month.
-}
previousMonth : Date -> { from : Date, to : Date }
previousMonth date =
    let
        prev : Date
        prev =
            if date.month == 1 then
                { year = date.year - 1, month = 12, day = 1 }

            else
                { year = date.year, month = date.month - 1, day = 1 }
    in
    { from = prev, to = endOfMonth prev }


{-| Number of days in a given month, accounting for leap years.
-}
daysInMonth : Int -> Int -> Int
daysInMonth year month =
    case month of
        1 ->
            31

        2 ->
            if isLeapYear year then
                29

            else
                28

        3 ->
            31

        4 ->
            30

        5 ->
            31

        6 ->
            30

        7 ->
            31

        8 ->
            31

        9 ->
            30

        10 ->
            31

        11 ->
            30

        12 ->
            31

        _ ->
            30


isLeapYear : Int -> Bool
isLeapYear year =
    (modBy 4 year == 0) && (modBy 100 year /= 0 || modBy 400 year == 0)
