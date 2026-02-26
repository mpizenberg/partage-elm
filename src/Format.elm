module Format exposing (formatCents, formatCentsWithCurrency)

{-| Formatting helpers for currency amounts stored as integer cents.
-}

import Domain.Currency exposing (Currency(..))


{-| Format an integer cents amount as a decimal string.
e.g., 1050 -> "10.50", -300 -> "-3.00", 0 -> "0.00"
-}
formatCents : Int -> String
formatCents cents =
    let
        abs_ =
            abs cents

        sign =
            if cents < 0 then
                "-"

            else
                ""

        whole =
            abs_ // 100

        frac =
            remainderBy 100 abs_
    in
    sign ++ String.fromInt whole ++ "." ++ String.padLeft 2 '0' (String.fromInt frac)


{-| Format cents with a currency code suffix.
e.g., 1050, EUR -> "10.50 EUR"
-}
formatCentsWithCurrency : Int -> Currency -> String
formatCentsWithCurrency cents currency =
    formatCents cents ++ " " ++ currencyCode currency


currencyCode : Currency -> String
currencyCode currency =
    case currency of
        USD ->
            "USD"

        EUR ->
            "EUR"

        GBP ->
            "GBP"

        CHF ->
            "CHF"
