module FormatTest exposing (suite)

import Domain.Currency exposing (Currency(..))
import Expect
import Form.NewEntry as NewEntry
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
        [ describe "formatCents (no currency symbol, precision from currency)"
            [ test "English EUR: simple positive" <|
                \_ -> Format.formatCents En 1050 EUR |> Expect.equal "10.50"
            , test "English EUR: large number with grouping" <|
                \_ -> Format.formatCents En 1234567 EUR |> Expect.equal "12,345.67"
            , test "English EUR: very large number with multiple groups" <|
                \_ -> Format.formatCents En 1234567890 EUR |> Expect.equal "12,345,678.90"
            , test "English EUR: negative" <|
                \_ -> Format.formatCents En -1050 EUR |> Expect.equal "-10.50"
            , test "English EUR: zero" <|
                \_ -> Format.formatCents En 0 EUR |> Expect.equal "0.00"
            , test "French EUR: simple positive" <|
                \_ -> Format.formatCents Fr 1050 EUR |> Expect.equal "10,50"
            , test "French EUR: large number with NNBSP grouping" <|
                \_ -> Format.formatCents Fr 1234567 EUR |> Expect.equal ("12" ++ nnbsp ++ "345,67")
            , test "French EUR: negative" <|
                \_ -> Format.formatCents Fr -1050 EUR |> Expect.equal "-10,50"
            , test "English JPY: precision 0, no decimals" <|
                \_ -> Format.formatCents En 1050 JPY |> Expect.equal "1,050"
            , test "French JPY: precision 0 with grouping" <|
                \_ -> Format.formatCents Fr 1234567 JPY |> Expect.equal ("1" ++ nnbsp ++ "234" ++ nnbsp ++ "567")
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
        , describe "formatCentsForInput (no grouping, precision from currency)"
            [ test "English EUR: precision 2" <|
                \_ -> Format.formatCentsForInput En 1234567 EUR |> Expect.equal "12345.67"
            , test "French EUR: precision 2, comma decimal, no grouping" <|
                \_ -> Format.formatCentsForInput Fr 1234567 EUR |> Expect.equal "12345,67"
            , test "English JPY: precision 0, no decimal point" <|
                \_ -> Format.formatCentsForInput En 1050 JPY |> Expect.equal "1050"
            , test "EUR zero -> 0.00" <|
                \_ -> Format.formatCentsForInput En 0 EUR |> Expect.equal "0.00"
            , test "JPY zero -> 0" <|
                \_ -> Format.formatCentsForInput En 0 JPY |> Expect.equal "0"
            ]
        , describe "amount parse round-trip (formatCentsForInput >> amountFromString)"
            (let
                roundTrip : Language -> Currency -> Int -> Expect.Expectation
                roundTrip lang currency cents =
                    Format.formatCentsForInput lang cents currency
                        |> NewEntry.amountFromString currency
                        |> Expect.equal (Ok cents)
             in
             [ test "EUR (precision 2), English" <|
                \_ -> roundTrip En EUR 1234567
             , test "EUR (precision 2), French" <|
                \_ -> roundTrip Fr EUR 1234567
             , test "JPY (precision 0), English" <|
                \_ -> roundTrip En JPY 1050
             , test "JPY (precision 0), French" <|
                \_ -> roundTrip Fr JPY 1234567
             , test "JPY: plain integer parses to itself, not 100x" <|
                \_ -> NewEntry.amountFromString JPY "1000" |> Expect.equal (Ok 1000)
             , test "EUR: '10.50' parses to 1050 cents" <|
                \_ -> NewEntry.amountFromString EUR "10.50" |> Expect.equal (Ok 1050)
             ]
            )
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
