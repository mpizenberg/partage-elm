module GroupCsvExport exposing (encode, exportFilename)

{-| Snapshot CSV export of a group's active entries.

One row per active entry (expense, transfer, or income). Member IDs are
resolved to display names. Amounts are written as decimals in their native
currency. Payers and beneficiaries are encoded as semicolon-joined
`name:value` tokens; a `\`, `:`, or `;` inside a name is backslash-escaped so it
can't break the token structure. The file is UTF-8 with a leading BOM. This
export is one-way; it cannot be re-imported.

-}

import Domain.Currency as Currency exposing (Currency)
import Domain.Date as Date
import Domain.Entry as Entry exposing (Entry, Kind(..))
import Domain.Group as Group
import Domain.GroupState as GroupState exposing (GroupState)


{-| Encode the snapshot of active entries in a group state as a CSV string.
-}
encode : GroupState -> String
encode state =
    let
        rows : List String
        rows =
            GroupState.activeEntries state
                |> List.sortBy entrySortKey
                |> List.map (entryRow state)
    in
    "\u{FEFF}" ++ String.join "\n" (header :: rows) ++ "\n"


{-| Build the filename for the CSV download.
-}
exportFilename : Group.Summary -> String
exportFilename summary =
    "partage-" ++ sanitizeFilename summary.name ++ ".csv"


header : String
header =
    String.join ","
        [ "date"
        , "kind"
        , "description"
        , "amount"
        , "currency"
        , "default_currency_amount"
        , "payers"
        , "beneficiaries"
        , "category"
        , "location"
        , "notes"
        , "created_by"
        ]


entrySortKey : Entry -> ( Int, String )
entrySortKey entry =
    ( -(Date.toComparable (entryDate entry)), entry.meta.id )


entryDate : Entry -> Date.Date
entryDate entry =
    case entry.kind of
        Expense data ->
            data.date

        Transfer data ->
            data.date

        Income data ->
            data.date


type alias RowFields =
    { kind : String
    , description : String
    , amount : String
    , currency : String
    , defaultAmount : String
    , payers : String
    , beneficiaries : String
    , category : String
    , location : String
    , notes : String
    }


entryRow : GroupState -> Entry -> String
entryRow state entry =
    let
        memberName : String -> String
        memberName id =
            GroupState.resolveMemberName state id

        tokenName : String -> String
        tokenName id =
            escapeToken (memberName id)

        common : RowFields
        common =
            case entry.kind of
                Expense data ->
                    { kind = "expense"
                    , description = data.description
                    , amount = formatAmount data.currency data.amount
                    , currency = Currency.currencyCode data.currency
                    , defaultAmount = maybeFormatDefault state.groupMeta.defaultCurrency data.defaultCurrencyAmount
                    , payers = formatPayers tokenName data.payers data.currency
                    , beneficiaries = formatBeneficiaries tokenName data.beneficiaries data.currency
                    , category = data.category |> Maybe.map Entry.categoryToString |> Maybe.withDefault ""
                    , location = data.location |> Maybe.withDefault ""
                    , notes = data.notes |> Maybe.withDefault ""
                    }

                Transfer data ->
                    { kind = "transfer"
                    , description = data.description |> Maybe.withDefault ""
                    , amount = formatAmount data.currency data.amount
                    , currency = Currency.currencyCode data.currency
                    , defaultAmount = maybeFormatDefault state.groupMeta.defaultCurrency data.defaultCurrencyAmount
                    , payers = tokenName data.from ++ ":" ++ formatAmount data.currency data.amount
                    , beneficiaries = tokenName data.to ++ ":" ++ formatAmount data.currency data.amount
                    , category = ""
                    , location = ""
                    , notes = data.notes |> Maybe.withDefault ""
                    }

                Income data ->
                    { kind = "income"
                    , description = data.description
                    , amount = formatAmount data.currency data.amount
                    , currency = Currency.currencyCode data.currency
                    , defaultAmount = maybeFormatDefault state.groupMeta.defaultCurrency data.defaultCurrencyAmount
                    , payers = tokenName data.receivedBy ++ ":" ++ formatAmount data.currency data.amount
                    , beneficiaries = formatBeneficiaries tokenName data.beneficiaries data.currency
                    , category = ""
                    , location = ""
                    , notes = data.notes |> Maybe.withDefault ""
                    }
    in
    String.join ","
        [ csvField (Date.toString (entryDate entry))
        , csvField common.kind
        , csvField common.description
        , csvField common.amount
        , csvField common.currency
        , csvField common.defaultAmount
        , csvField common.payers
        , csvField common.beneficiaries
        , csvField common.category
        , csvField common.location
        , csvField common.notes
        , csvField (memberName entry.meta.createdBy)
        ]


formatPayers : (String -> String) -> List Entry.Payer -> Currency -> String
formatPayers tokenName payers currency =
    payers
        |> List.map (\p -> tokenName p.memberId ++ ":" ++ formatAmount currency p.amount)
        |> String.join ";"


formatBeneficiaries : (String -> String) -> List Entry.Beneficiary -> Currency -> String
formatBeneficiaries tokenName beneficiaries currency =
    beneficiaries
        |> List.map
            (\b ->
                case b of
                    Entry.ShareBeneficiary data ->
                        tokenName data.memberId ++ ":" ++ String.fromInt data.shares ++ "s"

                    Entry.ExactBeneficiary data ->
                        tokenName data.memberId ++ ":" ++ formatAmount currency data.amount
            )
        |> String.join ";"


{-| Backslash-escape the token delimiters so a member name can't break the
`name:value` / `;`-joined structure of the payers and beneficiaries columns.
-}
escapeToken : String -> String
escapeToken name =
    name
        |> String.replace "\\" "\\\\"
        |> String.replace ":" "\\:"
        |> String.replace ";" "\\;"


maybeFormatDefault : Currency -> Maybe Int -> String
maybeFormatDefault defaultCurrency maybeAmount =
    case maybeAmount of
        Just amount ->
            formatAmount defaultCurrency amount

        Nothing ->
            ""


formatAmount : Currency -> Int -> String
formatAmount currency minor =
    let
        digits : Int
        digits =
            Currency.precision currency

        sign : String
        sign =
            if minor < 0 then
                "-"

            else
                ""

        absMinor : Int
        absMinor =
            abs minor
    in
    if digits == 0 then
        sign ++ String.fromInt absMinor

    else
        let
            divisor : Int
            divisor =
                10 ^ digits

            major : Int
            major =
                absMinor // divisor

            remainder : Int
            remainder =
                modBy divisor absMinor
        in
        sign
            ++ String.fromInt major
            ++ "."
            ++ String.padLeft digits '0' (String.fromInt remainder)


{-| Quote a CSV field when needed (commas, quotes, newlines, carriage returns),
doubling embedded quotes per RFC 4180. A leading `=`, `+`, `@`, `-`, tab, or CR
is first prefixed with `'` so a spreadsheet treats the cell as text rather than a
formula (CSV injection defense).
-}
csvField : String -> String
csvField value =
    let
        guarded : String
        guarded =
            if startsWithFormulaChar value then
                "'" ++ value

            else
                value
    in
    if String.any needsQuoting guarded then
        "\"" ++ String.replace "\"" "\"\"" guarded ++ "\""

    else
        guarded


startsWithFormulaChar : String -> Bool
startsWithFormulaChar value =
    case String.uncons value of
        Just ( c, _ ) ->
            c == '=' || c == '+' || c == '@' || c == '-' || c == '\t' || c == '\u{000D}'

        Nothing ->
            False


needsQuoting : Char -> Bool
needsQuoting c =
    c == ',' || c == '"' || c == '\n' || c == '\u{000D}'


sanitizeFilename : String -> String
sanitizeFilename name =
    String.toList name
        |> List.map
            (\c ->
                if Char.isAlphaNum c then
                    c

                else
                    '-'
            )
        |> String.fromList
