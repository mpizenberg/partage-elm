module Domain.Currency exposing (Currency(..), allCurrencies, currencyCode, currencyDecoder, encodeCurrency, precision)

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
    | CNY
    | SEK
    | NZD
    | MXN
    | SGD
    | HKD
    | NOK
    | KRW
    | TRY
    | INR
    | RUB
    | BRL
    | ZAR


allCurrencies : List Currency
allCurrencies =
    [ EUR, USD, GBP, CHF, JPY, AUD, CAD, CNY, SEK, NZD, MXN, SGD, HKD, NOK, KRW, TRY, INR, RUB, BRL, ZAR ]


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

        CNY ->
            "CNY"

        SEK ->
            "SEK"

        NZD ->
            "NZD"

        MXN ->
            "MXN"

        SGD ->
            "SGD"

        HKD ->
            "HKD"

        NOK ->
            "NOK"

        KRW ->
            "KRW"

        TRY ->
            "TRY"

        INR ->
            "INR"

        RUB ->
            "RUB"

        BRL ->
            "BRL"

        ZAR ->
            "ZAR"


{-| Number of decimal digits for a currency (e.g. 2 for cents).
-}
precision : Currency -> Int
precision currency =
    case currency of
        JPY ->
            0

        KRW ->
            0

        _ ->
            2


encodeCurrency : Currency -> Encode.Value
encodeCurrency currency =
    Encode.string (String.toLower (currencyCode currency))


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

                    "cny" ->
                        Decode.succeed CNY

                    "sek" ->
                        Decode.succeed SEK

                    "nzd" ->
                        Decode.succeed NZD

                    "mxn" ->
                        Decode.succeed MXN

                    "sgd" ->
                        Decode.succeed SGD

                    "hkd" ->
                        Decode.succeed HKD

                    "nok" ->
                        Decode.succeed NOK

                    "krw" ->
                        Decode.succeed KRW

                    "try" ->
                        Decode.succeed TRY

                    "inr" ->
                        Decode.succeed INR

                    "rub" ->
                        Decode.succeed RUB

                    "brl" ->
                        Decode.succeed BRL

                    "zar" ->
                        Decode.succeed ZAR

                    _ ->
                        Decode.fail ("Unknown currency: " ++ s)
            )
