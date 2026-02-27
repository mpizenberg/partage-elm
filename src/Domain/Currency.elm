module Domain.Currency exposing (Currency(..), currencyDecoder, encodeCurrency, precision)

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


encodeCurrency : Currency -> Encode.Value
encodeCurrency currency =
    Encode.string
        (case currency of
            USD ->
                "usd"

            EUR ->
                "eur"

            GBP ->
                "gbp"

            CHF ->
                "chf"
        )


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

                    _ ->
                        Decode.fail ("Unknown currency: " ++ s)
            )
