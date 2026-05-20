module FormatTest exposing (suite)

import Domain.Currency exposing (Currency(..))
import Expect
import Format
import Test exposing (Test, describe, test)
import Translations exposing (Language(..))


nbsp : String
nbsp =
    "\u{00A0}"


nnbsp : String
nnbsp =
    "\u{202F}"


suite : Test
suite =
    describe "Format"
        [ describe "formatCents (no currency, assumes precision 2)"
            [ test "English: simple positive" <|
                \_ -> Format.formatCents En 1050 |> Expect.equal "10.50"
            , test "English: large number with grouping" <|
                \_ -> Format.formatCents En 1234567 |> Expect.equal "12,345.67"
            , test "English: very large number with multiple groups" <|
                \_ -> Format.formatCents En 1234567890 |> Expect.equal "12,345,678.90"
            , test "English: negative" <|
                \_ -> Format.formatCents En -1050 |> Expect.equal "-10.50"
            , test "English: zero" <|
                \_ -> Format.formatCents En 0 |> Expect.equal "0.00"
            , test "French: simple positive" <|
                \_ -> Format.formatCents Fr 1050 |> Expect.equal "10,50"
            , test "French: large number with NNBSP grouping" <|
                \_ -> Format.formatCents Fr 1234567 |> Expect.equal ("12" ++ nnbsp ++ "345,67")
            , test "French: negative" <|
                \_ -> Format.formatCents Fr -1050 |> Expect.equal "-10,50"
            ]
        , describe "formatCentsWithCurrency"
            [ test "English EUR: symbol prefix" <|
                \_ -> Format.formatCentsWithCurrency En 1050 EUR |> Expect.equal "€10.50"
            , test "English USD: symbol prefix" <|
                \_ -> Format.formatCentsWithCurrency En 2000 USD |> Expect.equal "$20.00"
            , test "English JPY: no decimals" <|
                \_ -> Format.formatCentsWithCurrency En 1050 JPY |> Expect.equal "¥1,050"
            , test "English EUR: negative keeps minus before symbol" <|
                \_ -> Format.formatCentsWithCurrency En -500 EUR |> Expect.equal "-€5.00"
            , test "French EUR: symbol suffix with NBSP" <|
                \_ -> Format.formatCentsWithCurrency Fr 2000 EUR |> Expect.equal ("20,00" ++ nbsp ++ "€")
            , test "French USD: symbol suffix" <|
                \_ -> Format.formatCentsWithCurrency Fr 2000 USD |> Expect.equal ("20,00" ++ nbsp ++ "$")
            , test "French JPY: no decimals, suffix" <|
                \_ -> Format.formatCentsWithCurrency Fr 1050 JPY |> Expect.equal ("1" ++ nnbsp ++ "050" ++ nbsp ++ "¥")
            , test "French EUR: large amount with grouping" <|
                \_ ->
                    Format.formatCentsWithCurrency Fr 1234567 EUR
                        |> Expect.equal ("12" ++ nnbsp ++ "345,67" ++ nbsp ++ "€")
            , test "French EUR: negative keeps minus before number" <|
                \_ ->
                    Format.formatCentsWithCurrency Fr -500 EUR
                        |> Expect.equal ("-5,00" ++ nbsp ++ "€")
            , test "English CHF: multi-char symbol prefix" <|
                \_ -> Format.formatCentsWithCurrency En 2000 CHF |> Expect.equal "CHF20.00"
            ]
        , describe "formatCentsSigned"
            [ test "English EUR: positive gets explicit +" <|
                \_ -> Format.formatCentsSigned En 1050 EUR |> Expect.equal "+€10.50"
            , test "English EUR: negative keeps locale - prefix, no extra" <|
                \_ -> Format.formatCentsSigned En -500 EUR |> Expect.equal "-€5.00"
            , test "English EUR: zero gets no sign" <|
                \_ -> Format.formatCentsSigned En 0 EUR |> Expect.equal "€0.00"
            , test "French EUR: positive +" <|
                \_ -> Format.formatCentsSigned Fr 1050 EUR |> Expect.equal ("+10,50" ++ nbsp ++ "€")
            , test "French EUR: negative -" <|
                \_ -> Format.formatCentsSigned Fr -500 EUR |> Expect.equal ("-5,00" ++ nbsp ++ "€")
            , test "French EUR: zero" <|
                \_ -> Format.formatCentsSigned Fr 0 EUR |> Expect.equal ("0,00" ++ nbsp ++ "€")
            ]
        ]
