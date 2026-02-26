module Domain.Currency exposing (Currency(..), precision)

{-| Supported currencies and their precision.
-}


{-| Supported currencies for expenses and transfers.
-}
type Currency
    = USD
    | EUR
    | GBP
    | CHF


{-| Number of decimal digits for a currency (e.g. 2 for cents).
-}
precision : Currency -> Int
precision currency =
    case currency of
        USD ->
            2

        EUR ->
            2

        GBP ->
            2

        CHF ->
            2
