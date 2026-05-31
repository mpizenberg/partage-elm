module SplitwiseImport exposing
    ( Parsed
    , Row
    , parse
    , parseDecimal
    , reconstruct
    , usedCurrencies
    )

{-| Parse a Splitwise group CSV export and reconstruct it into the app's
ledger model.

Splitwise exports only each member's **net** per row (`paid − owed`), not the
underlying payers and beneficiaries, so the original split is not recoverable.
We synthesize a faithful reconstruction in three tiers (most specific first):

1.  **Equal split** — a single payer and equal owed amounts that sum to the
    cost: rebuilt as an equal `ShareBeneficiary` split (recovers the intent).
2.  **Exact single payer** — a single payer with uneven shares: the payer pays
    the full cost and beneficiaries get `ExactBeneficiary` owed amounts.
3.  **Net only** — genuine multiple payers (ambiguous): payers and exact
    beneficiaries mirror the positive/negative nets. Balances stay exact, but
    the expense amount reflects money moved rather than the gross cost.

`Payment` rows become `Transfer`s.

Reconstruction works in the row's own currency; an optional rate per non-default
currency only fills `defaultCurrencyAmount`, matching the app's multi-currency
model (the balance engine distributes proportionally from there).

-}

import Domain.Currency as Currency exposing (Currency)
import Domain.Date exposing (Date)
import Domain.Entry exposing (Beneficiary(..), Category(..), Kind(..), Payer)
import Domain.Member as Member


{-| A parsed Splitwise file: member column names and the data rows.
-}
type alias Parsed =
    { memberNames : List String
    , rows : List Row
    }


{-| One transaction row. `nets` is aligned to `Parsed.memberNames`; each value
is that member's signed net (`paid − owed`) in the currency's minor units.
-}
type alias Row =
    { date : Date
    , description : String
    , category : String
    , currency : Currency
    , cost : Int
    , nets : List Int
    }


{-| The distinct currencies that appear across the parsed rows, in first-seen
order. Useful for picking a group default and prompting for rates.
-}
usedCurrencies : Parsed -> List Currency
usedCurrencies parsed =
    List.foldr
        (\row acc ->
            if List.member row.currency acc then
                acc

            else
                row.currency :: acc
        )
        []
        parsed.rows



-- PARSING


{-| Parse the CSV text. Returns an error string describing the first structural
problem, or the parsed members and rows. Blank lines and the trailing
"Total balance" summary rows are skipped.
-}
parse : String -> Result String Parsed
parse text =
    case splitRows text of
        [] ->
            Err "The file is empty."

        header :: dataRows ->
            case List.drop 5 header of
                [] ->
                    Err "No member columns found in the CSV header."

                memberNames ->
                    Ok
                        { memberNames = memberNames
                        , rows = List.filterMap (parseRow (List.length memberNames)) dataRows
                        }


{-| Parse a single data row, returning Nothing for rows to skip: blank rows,
"Total balance" summaries, rows with an empty/invalid cost or currency, and rows
whose member-column count does not match the header.
-}
parseRow : Int -> List String -> Maybe Row
parseRow memberCount fields =
    case fields of
        dateStr :: description :: category :: costStr :: currencyStr :: netFields ->
            if description == "Total balance" || String.trim costStr == "" then
                Nothing

            else
                case ( parseDate dateStr, Currency.currencyFromCode (String.trim currencyStr) ) of
                    ( Just date, Just currency ) ->
                        let
                            prec : Int
                            prec =
                                Currency.precision currency

                            maybeNets : Maybe (List Int)
                            maybeNets =
                                if List.length netFields == memberCount then
                                    allJust (List.map (parseDecimal prec) netFields)

                                else
                                    Nothing
                        in
                        Maybe.map2 (Row date description category currency)
                            (parseDecimal prec costStr)
                            maybeNets

                    _ ->
                        Nothing

        _ ->
            Nothing


{-| Parse "YYYY-MM-DD" into a Date.
-}
parseDate : String -> Maybe Date
parseDate str =
    case String.split "-" (String.trim str) of
        [ y, m, d ] ->
            Maybe.map3 Date (String.toInt y) (String.toInt m) (String.toInt d)

        _ ->
            Nothing


{-| Parse a decimal amount (e.g. "16.00", "-8.5", "33.99") into minor units for
a currency with the given decimal `precision`. Fractional digits beyond the
precision are truncated; missing ones are padded with zeros.
-}
parseDecimal : Int -> String -> Maybe Int
parseDecimal prec raw =
    let
        trimmed : String
        trimmed =
            String.trim raw
    in
    if trimmed == "" then
        Nothing

    else
        let
            ( sign, body ) =
                case String.uncons trimmed of
                    Just ( '-', rest ) ->
                        ( -1, rest )

                    Just ( '+', rest ) ->
                        ( 1, rest )

                    _ ->
                        ( 1, trimmed )

            scale : Int
            scale =
                10 ^ prec
        in
        case String.split "." body of
            [ intStr ] ->
                String.toInt (orZero intStr)
                    |> Maybe.map (\i -> sign * i * scale)

            [ intStr, fracStr ] ->
                if prec == 0 then
                    String.toInt (orZero intStr)
                        |> Maybe.map (\i -> sign * i)

                else
                    Maybe.map2 (\i f -> sign * (i * scale + f))
                        (String.toInt (orZero intStr))
                        (String.toInt (String.left prec (String.padRight prec '0' fracStr)))

            _ ->
                Nothing


orZero : String -> String
orZero s =
    if s == "" then
        "0"

    else
        s


allJust : List (Maybe a) -> Maybe (List a)
allJust =
    List.foldr (\m acc -> Maybe.map2 (::) m acc) (Just [])



-- CSV TOKENIZER (RFC 4180-ish: quoted fields with embedded commas/quotes)


type alias CsvState =
    { rows : List (List String)
    , row : List String
    , field : String
    , quoted : Bool
    }


splitRows : String -> List (List String)
splitRows text =
    let
        final : CsvState
        final =
            consume (String.toList text) { rows = [], row = [], field = "", quoted = False }
    in
    flush final
        |> List.filter (List.any (\f -> String.trim f /= ""))


consume : List Char -> CsvState -> CsvState
consume chars st =
    case chars of
        [] ->
            st

        c :: rest ->
            if st.quoted then
                case ( c, rest ) of
                    ( '"', '"' :: rest2 ) ->
                        consume rest2 { st | field = st.field ++ "\"" }

                    ( '"', _ ) ->
                        consume rest { st | quoted = False }

                    _ ->
                        consume rest { st | field = st.field ++ String.fromChar c }

            else
                case c of
                    '"' ->
                        consume rest { st | quoted = True }

                    ',' ->
                        consume rest { st | row = st.row ++ [ st.field ], field = "" }

                    '\n' ->
                        consume rest { st | rows = st.rows ++ [ st.row ++ [ st.field ] ], row = [], field = "" }

                    '\u{000D}' ->
                        consume rest st

                    _ ->
                        consume rest { st | field = st.field ++ String.fromChar c }


flush : CsvState -> List (List String)
flush st =
    if st.field == "" && List.isEmpty st.row then
        st.rows

    else
        st.rows ++ [ st.row ++ [ st.field ] ]



-- RECONSTRUCTION


{-| Reconstruct a row into a ledger `Kind`, or Nothing if it carries no balance
effect (all-zero nets) or is an unmappable payment. `memberIds` must align with
`Parsed.memberNames`. `rate c` gives the value of one unit of currency `c` in
the default currency; it is consulted only for non-default-currency rows, where
it always fills `defaultCurrencyAmount`.
-}
reconstruct :
    { memberIds : List Member.Id
    , defaultCurrency : Currency
    , rate : Currency -> Float
    }
    -> Row
    -> Maybe Kind
reconstruct config row =
    let
        pairs : List ( Member.Id, Int )
        pairs =
            List.map2 Tuple.pair config.memberIds row.nets

        positives : List ( Member.Id, Int )
        positives =
            List.filter (\( _, n ) -> n > 0) pairs

        negatives : List ( Member.Id, Int )
        negatives =
            List.filter (\( _, n ) -> n < 0) pairs

        dcaFor : Int -> Maybe Int
        dcaFor amount =
            if row.currency == config.defaultCurrency then
                Nothing

            else
                Just (Currency.convertCents (config.rate row.currency) amount row.currency config.defaultCurrency)
    in
    if isPayment row.category then
        case ( positives, negatives ) of
            ( [ ( fromId, amt ) ], [ ( toId, _ ) ] ) ->
                Just
                    (Transfer
                        { amount = amt
                        , currency = row.currency
                        , defaultCurrencyAmount = dcaFor amt
                        , date = row.date
                        , from = fromId
                        , to = toId
                        , notes = Nothing
                        }
                    )

            _ ->
                Nothing

    else
        case positives of
            [ ( payerId, payerNet ) ] ->
                Just (singlePayerExpense row payerId payerNet negatives dcaFor)

            _ ->
                netOnlyExpense row positives negatives dcaFor


singlePayerExpense : Row -> Member.Id -> Int -> List ( Member.Id, Int ) -> (Int -> Maybe Int) -> Kind
singlePayerExpense row payerId payerNet negatives dcaFor =
    let
        owed : List ( Member.Id, Int )
        owed =
            List.map (\( id, n ) -> ( id, negate n )) negatives

        owedAmounts : List Int
        owedAmounts =
            List.map Tuple.second owed

        involvedCount : Int
        involvedCount =
            1 + List.length owed

        payers : List Payer
        payers =
            [ { memberId = payerId, amount = row.cost } ]
    in
    if isEqualSplit row.cost owedAmounts involvedCount then
        makeExpense row
            row.cost
            payers
            ((payerId :: List.map Tuple.first owed)
                |> List.map (\id -> ShareBeneficiary { memberId = id, shares = 1 })
            )
            (dcaFor row.cost)

    else
        let
            payerOwed : Int
            payerOwed =
                row.cost - payerNet

            beneficiaries : List Beneficiary
            beneficiaries =
                List.map (\( id, a ) -> ExactBeneficiary { memberId = id, amount = a }) owed
                    ++ (if payerOwed > 0 then
                            [ ExactBeneficiary { memberId = payerId, amount = payerOwed } ]

                        else
                            []
                       )
        in
        makeExpense row row.cost payers beneficiaries (dcaFor row.cost)


netOnlyExpense : Row -> List ( Member.Id, Int ) -> List ( Member.Id, Int ) -> (Int -> Maybe Int) -> Maybe Kind
netOnlyExpense row positives negatives dcaFor =
    if List.isEmpty positives || List.isEmpty negatives then
        Nothing

    else
        let
            amount : Int
            amount =
                List.sum (List.map Tuple.second positives)
        in
        Just
            (makeExpense row
                amount
                (List.map (\( id, n ) -> { memberId = id, amount = n }) positives)
                (List.map (\( id, n ) -> ExactBeneficiary { memberId = id, amount = negate n }) negatives)
                (dcaFor amount)
            )


makeExpense : Row -> Int -> List Payer -> List Beneficiary -> Maybe Int -> Kind
makeExpense row amount payers beneficiaries dca =
    Expense
        { description = row.description
        , amount = amount
        , currency = row.currency
        , defaultCurrencyAmount = dca
        , date = row.date
        , payers = payers
        , beneficiaries = beneficiaries
        , category = mapCategory row.category
        , location = Nothing
        , notes = Nothing
        }


isEqualSplit : Int -> List Int -> Int -> Bool
isEqualSplit cost owedAmounts involvedCount =
    case owedAmounts of
        [] ->
            False

        x :: _ ->
            allEqual owedAmounts && cost == x * involvedCount


allEqual : List Int -> Bool
allEqual xs =
    case xs of
        [] ->
            True

        x :: rest ->
            List.all ((==) x) rest


isPayment : String -> Bool
isPayment category =
    String.toLower (String.trim category) == "payment"


{-| Map a Splitwise category label onto the app's categories. Returns Nothing
for unrecognized or generic ("General") labels so entries stay uncategorized
rather than mislabeled.
-}
mapCategory : String -> Maybe Category
mapCategory raw =
    let
        c : String
        c =
            String.toLower (String.trim raw)

        has : String -> Bool
        has needle =
            String.contains needle c
    in
    if has "grocer" then
        Just Groceries

    else if has "dining" || has "liquor" || has "restaurant" || has "food" || has "drink" then
        Just Food

    else if has "plane" || has "car" || has "bus" || has "train" || has "taxi" || has "fuel" || has "gas" || has "parking" || has "transport" || has "flight" then
        Just Transport

    else if has "rent" || has "hotel" || has "accommodation" || has "housing" || has "lodging" then
        Just Accommodation

    else if has "entertain" || has "movie" || has "game" || has "music" then
        Just Entertainment

    else if has "shop" || has "clothing" || has "electronic" then
        Just Shopping

    else if has "utilit" || has "electric" || has "water" || has "internet" || has "phone" || has "heat" then
        Just Utilities

    else if has "medical" || has "health" || has "doctor" || has "pharma" then
        Just Healthcare

    else
        Nothing
