module Domain.Date exposing (Date)

{-| Simple calendar date type for entries.
-}


{-| A simple calendar date with year, month, and day components.
Amounts in entries are integers (cents), and dates use this plain record
rather than `Time.Posix` since only the calendar date matters for entries.
-}
type alias Date =
    { year : Int
    , month : Int
    , day : Int
    }
