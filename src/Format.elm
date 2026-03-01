module Format exposing (formatCents, formatCentsWithCurrency, formatMinorUnits)

{-| Formatting helpers for currency amounts stored as smallest currency units.
-}

import Domain.Currency as Currency exposing (Currency)


{-| Format an integer amount in smallest units as a decimal string
using the currency's precision.
e.g., formatMinorUnits EUR 1050 -> "10.50", formatMinorUnits JPY 1050 -> "1050"
-}
formatMinorUnits : Currency -> Int -> String
formatMinorUnits currency amount =
    let
        p =
            Currency.precision currency
    in
    if p == 0 then
        String.fromInt amount

    else
        let
            divisor =
                10 ^ p

            abs_ =
                abs amount

            sign =
                if amount < 0 then
                    "-"

                else
                    ""

            whole =
                abs_ // divisor

            frac =
                remainderBy divisor abs_
        in
        sign ++ String.fromInt whole ++ "." ++ String.padLeft p '0' (String.fromInt frac)


{-| Format an integer cents amount as a decimal string (assumes precision 2).
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
formatCentsWithCurrency amount currency =
    formatMinorUnits currency amount ++ " " ++ Currency.currencyCode currency
