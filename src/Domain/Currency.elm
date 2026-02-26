module Domain.Currency exposing (Currency(..), precision)


type Currency
    = USD
    | EUR
    | GBP
    | CHF


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
