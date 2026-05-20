module Format exposing (formatCents, formatCentsSigned, formatCentsWithCurrency)

{-| Locale-aware formatting helpers for currency amounts stored as smallest currency units.

The active `Language` controls decimal separator, thousands grouping separator and
whether the currency symbol appears as a prefix or as a (space-separated) suffix.

-}

import Domain.Currency as Currency exposing (Currency)
import Translations exposing (Language(..))


type SymbolPosition
    = Prefix
    | SuffixWithSpace


type alias LocaleConfig =
    { decimal : String
    , group : String
    , symbolPosition : SymbolPosition
    }


localeConfig : Language -> LocaleConfig
localeConfig lang =
    case lang of
        En ->
            { decimal = "."
            , group = ","
            , symbolPosition = Prefix
            }

        Fr ->
            -- French CLDR: narrow no-break space (U+202F) for grouping,
            -- comma for decimal, symbol after the number with a NBSP.
            { decimal = ","
            , group = "\u{202F}"
            , symbolPosition = SuffixWithSpace
            }


{-| Format an integer cents amount as a decimal string (assumes precision 2).
e.g. (En, 1050) -> "10.50", (Fr, 1050) -> "10,50", (En, -1234567) -> "-12,345.67"
-}
formatCents : Language -> Int -> String
formatCents lang cents =
    formatMinorUnits (localeConfig lang) 2 cents


{-| Format cents with an explicit sign: "+" for positive, locale "-" for negative,
no sign for zero. Useful for balance / credit displays where direction matters.
-}
formatCentsSigned : Language -> Int -> Currency -> String
formatCentsSigned lang amount currency =
    if amount > 0 then
        "+" ++ formatCentsWithCurrency lang amount currency

    else
        formatCentsWithCurrency lang amount currency


{-| Format cents with a currency symbol, respecting the locale's symbol position.
e.g. (En, 1050, EUR) -> "€10.50", (Fr, 1050, EUR) -> "10,50 €",
(En, 1050, JPY) -> "¥1050", (Fr, 1050, JPY) -> "1 050 ¥".
-}
formatCentsWithCurrency : Language -> Int -> Currency -> String
formatCentsWithCurrency lang amount currency =
    let
        cfg : LocaleConfig
        cfg =
            localeConfig lang

        symbol : String
        symbol =
            Currency.currencySymbol currency

        number : String
        number =
            formatMinorUnits cfg (Currency.precision currency) amount
    in
    case cfg.symbolPosition of
        Prefix ->
            -- Keep the minus sign before the symbol: "-$5.00" rather than "$-5.00".
            if amount < 0 then
                "-" ++ symbol ++ String.dropLeft 1 number

            else
                symbol ++ number

        SuffixWithSpace ->
            number ++ "\u{00A0}" ++ symbol


formatMinorUnits : LocaleConfig -> Int -> Int -> String
formatMinorUnits cfg p amount =
    let
        sign : String
        sign =
            if amount < 0 then
                "-"

            else
                ""

        abs_ : Int
        abs_ =
            abs amount
    in
    if p == 0 then
        sign ++ addGrouping cfg.group (String.fromInt abs_)

    else
        let
            divisor : Int
            divisor =
                10 ^ p

            whole : Int
            whole =
                abs_ // divisor

            frac : Int
            frac =
                remainderBy divisor abs_
        in
        sign
            ++ addGrouping cfg.group (String.fromInt whole)
            ++ cfg.decimal
            ++ String.padLeft p '0' (String.fromInt frac)


addGrouping : String -> String -> String
addGrouping sep digits =
    chunksFromRight 3 digits []
        |> String.join sep


chunksFromRight : Int -> String -> List String -> List String
chunksFromRight size s acc =
    if String.length s <= size then
        s :: acc

    else
        chunksFromRight size (String.dropRight size s) (String.right size s :: acc)
