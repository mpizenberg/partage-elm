module Domain.Currency exposing (Currency(..), allCurrencies, currencyCode, currencyDecoder, currencyFromCode, currencySymbol, encodeCurrency, precision)

{-| Supported currencies and their precision.
-}

import Json.Decode as Decode
import Json.Encode as Encode


{-| Supported currencies for expenses and transfers.
-}
type Currency
    = USD
    | EUR
    | GBP
    | CHF
    | JPY
    | AUD
    | CAD
    | NZD
    | BRL
    | ARS


{-| All supported currencies, ordered with EUR first.
-}
allCurrencies : List Currency
allCurrencies =
    [ EUR, USD, GBP, CHF, JPY, AUD, CAD, NZD, BRL, ARS ]


{-| Get the uppercase ISO 4217 code for a currency.
-}
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

        JPY ->
            "JPY"

        AUD ->
            "AUD"

        CAD ->
            "CAD"

        NZD ->
            "NZD"

        BRL ->
            "BRL"

        ARS ->
            "ARS"


{-| Get the symbol for a currency (e.g. "€", "$", "£").
-}
currencySymbol : Currency -> String
currencySymbol currency =
    case currency of
        USD ->
            "$"

        EUR ->
            "€"

        GBP ->
            "£"

        CHF ->
            "CHF"

        JPY ->
            "¥"

        AUD ->
            "A$"

        CAD ->
            "C$"

        NZD ->
            "NZ$"

        BRL ->
            "R$"

        ARS ->
            "AR$"


{-| Parse a currency code string (case-insensitive) into a Currency.
-}
currencyFromCode : String -> Maybe Currency
currencyFromCode s =
    case String.toLower s of
        "usd" ->
            Just USD

        "eur" ->
            Just EUR

        "gbp" ->
            Just GBP

        "chf" ->
            Just CHF

        "jpy" ->
            Just JPY

        "aud" ->
            Just AUD

        "cad" ->
            Just CAD

        "nzd" ->
            Just NZD

        "brl" ->
            Just BRL

        "ars" ->
            Just ARS

        _ ->
            Nothing


{-| Number of decimal digits for a currency (e.g. 2 for cents).
-}
precision : Currency -> Int
precision currency =
    case currency of
        JPY ->
            0

        _ ->
            2


{-| Encode a Currency as a lowercase JSON string.
-}
encodeCurrency : Currency -> Encode.Value
encodeCurrency currency =
    Encode.string (String.toLower (currencyCode currency))


{-| Decode a Currency from a lowercase JSON string.
-}
currencyDecoder : Decode.Decoder Currency
currencyDecoder =
    Decode.string
        |> Decode.andThen
            (\s ->
                case s of
                    "usd" ->
                        Decode.succeed USD

                    "eur" ->
                        Decode.succeed EUR

                    "gbp" ->
                        Decode.succeed GBP

                    "chf" ->
                        Decode.succeed CHF

                    "jpy" ->
                        Decode.succeed JPY

                    "aud" ->
                        Decode.succeed AUD

                    "cad" ->
                        Decode.succeed CAD

                    "nzd" ->
                        Decode.succeed NZD

                    "brl" ->
                        Decode.succeed BRL

                    "ars" ->
                        Decode.succeed ARS

                    _ ->
                        Decode.fail ("Unknown currency: " ++ s)
            )
