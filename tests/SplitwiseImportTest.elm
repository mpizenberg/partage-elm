module SplitwiseImportTest exposing (suite)

import Dict
import Domain.Balance as Balance
import Domain.Currency exposing (Currency(..))
import Domain.Entry as Entry exposing (Beneficiary(..), Category(..), Entry, Kind(..))
import Domain.Member as Member
import Expect
import SplitwiseImport
import Test exposing (Test, describe, test)
import Time


{-| The sample export provided by the user (EUR + GBP, 3 members),
including the blank lines and trailing "Total balance" rows.
-}
sampleCsv : String
sampleCsv =
    """Date,Description,Category,Cost,Currency,Louis Viot,Matthieu Pizenberg,Simon Prieul

2020-03-05,Navette aéroport,Plane,16.00,EUR,0.00,8.00,-8.00
2020-03-06,Whiskey,Liquor,33.99,GBP,0.00,-33.99,33.99
2020-03-06,Air BnB,Rent,285.00,EUR,-95.00,190.00,-95.00
2020-03-08,Tickets car Oxford,Car,45.00,GBP,30.00,-15.00,-15.00
2020-03-08,Tagine Louis Oxford,Dining out,15.00,GBP,-15.00,0.00,15.00
2020-03-08,Tagine Matthieu Oxford,Dining out,20.20,GBP,0.00,-20.20,20.20
2020-03-09,Viet,Dining out,12.00,GBP,12.00,-12.00,0.00
2020-04-02,Conversion £ -> €,General,62.00,EUR,0.00,-62.00,62.00
2020-04-02,Matthieu P. paid Simon P.,Payment,54.19,GBP,0.00,54.19,-54.19
2020-04-16,Simon P. paid Matthieu P.,Payment,41.00,EUR,0.00,-41.00,41.00
2020-08-02,Louis V. paid Matthieu P.,Payment,95.00,EUR,95.00,-95.00,0.00
2020-08-02,Matthieu P. paid Louis V.,Payment,27.00,GBP,-27.00,27.00,0.00

2026-05-30,Total balance, , ,EUR,0.00,0.00,0.00
2026-05-30,Total balance, , ,GBP,0.00,0.00,0.00

"""


parsed : Result String SplitwiseImport.Parsed
parsed =
    SplitwiseImport.parse sampleCsv


config : List String -> { memberIds : List Member.Id, defaultCurrency : Currency, rate : Currency -> Float }
config names =
    { memberIds = names
    , defaultCurrency = EUR
    , rate = always 1.0
    }


entryFromKind : Kind -> Entry
entryFromKind kind =
    { meta = Entry.newMetadata "e" "creator" (Time.millisToPosix 0)
    , kind = kind
    }


netOf : List Entry -> Member.Id -> Int
netOf entries memberId =
    Balance.computeBalances entries
        |> Dict.get memberId
        |> Maybe.map .netBalance
        |> Maybe.withDefault 0


suite : Test
suite =
    describe "SplitwiseImport"
        [ parseTests
        , decimalTests
        , reconstructStructureTests
        , faithfulnessTests
        ]


parseTests : Test
parseTests =
    describe "parse"
        [ test "reads the member columns from the header" <|
            \_ ->
                Result.map .memberNames parsed
                    |> Expect.equal (Ok [ "Louis Viot", "Matthieu Pizenberg", "Simon Prieul" ])
        , test "skips blank lines and the Total balance summary rows" <|
            \_ ->
                Result.map (.rows >> List.length) parsed
                    |> Expect.equal (Ok 12)
        , test "detects used currencies in first-seen order" <|
            \_ ->
                Result.map SplitwiseImport.usedCurrencies parsed
                    |> Expect.equal (Ok [ EUR, GBP ])
        , test "errors on an empty file" <|
            \_ ->
                SplitwiseImport.parse ""
                    |> Expect.err
        ]


decimalTests : Test
decimalTests =
    describe "parseDecimal"
        [ test "whole and fractional EUR amounts" <|
            \_ ->
                List.map (SplitwiseImport.parseDecimal 2)
                    [ "16.00", "33.99", "-8.00", "0.00", "8" ]
                    |> Expect.equal [ Just 1600, Just 3399, Just -800, Just 0, Just 800 ]
        , test "pads and truncates fractional digits to precision" <|
            \_ ->
                List.map (SplitwiseImport.parseDecimal 2) [ "1.5", "1.005" ]
                    |> Expect.equal [ Just 150, Just 100 ]
        , test "JPY has no minor units" <|
            \_ ->
                List.map (SplitwiseImport.parseDecimal 0) [ "1000", "1000.50" ]
                    |> Expect.equal [ Just 1000, Just 1000 ]
        , test "rejects non-numeric input" <|
            \_ ->
                SplitwiseImport.parseDecimal 2 "abc"
                    |> Expect.equal Nothing
        ]


{-| Find a row by description in the parsed sample, then reconstruct it.
-}
reconstructByDescription : String -> Maybe Kind
reconstructByDescription desc =
    case parsed of
        Ok p ->
            p.rows
                |> List.filter (\r -> r.description == desc)
                |> List.head
                |> Maybe.andThen (SplitwiseImport.reconstruct (config p.memberNames))

        Err _ ->
            Nothing


reconstructStructureTests : Test
reconstructStructureTests =
    describe "reconstruct (tier structure)"
        [ test "equal split is rebuilt as a 3-way ShareBeneficiary expense (Air BnB)" <|
            \_ ->
                case reconstructByDescription "Air BnB" of
                    Just (Expense data) ->
                        Expect.all
                            [ \d -> Expect.equal 28500 d.amount
                            , \d -> Expect.equal [ { memberId = "Matthieu Pizenberg", amount = 28500 } ] d.payers
                            , \d ->
                                Expect.equal
                                    [ ShareBeneficiary { memberId = "Matthieu Pizenberg", shares = 1 }
                                    , ShareBeneficiary { memberId = "Louis Viot", shares = 1 }
                                    , ShareBeneficiary { memberId = "Simon Prieul", shares = 1 }
                                    ]
                                    d.beneficiaries
                            , \d -> Expect.equal (Just Accommodation) d.category
                            ]
                            data

                    _ ->
                        Expect.fail "expected an Expense"
        , test "uneven single-payer expense uses ExactBeneficiary (Whiskey)" <|
            \_ ->
                case reconstructByDescription "Whiskey" of
                    Just (Expense data) ->
                        Expect.all
                            [ \d -> Expect.equal 3399 d.amount
                            , \d -> Expect.equal [ { memberId = "Simon Prieul", amount = 3399 } ] d.payers
                            , \d ->
                                Expect.equal
                                    [ ExactBeneficiary { memberId = "Matthieu Pizenberg", amount = 3399 } ]
                                    d.beneficiaries
                            ]
                            data

                    _ ->
                        Expect.fail "expected an Expense"
        , test "Payment rows become Transfers (Matthieu paid Simon)" <|
            \_ ->
                case reconstructByDescription "Matthieu P. paid Simon P." of
                    Just (Transfer data) ->
                        Expect.all
                            [ \d -> Expect.equal "Matthieu Pizenberg" d.from
                            , \d -> Expect.equal "Simon Prieul" d.to
                            , \d -> Expect.equal 5419 d.amount
                            ]
                            data

                    _ ->
                        Expect.fail "expected a Transfer"
        ]


faithfulnessTests : Test
faithfulnessTests =
    describe "reconstruct (balance faithfulness)"
        [ test "every row's reconstruction reproduces the Splitwise nets" <|
            \_ ->
                case parsed of
                    Ok p ->
                        let
                            mismatches : List String
                            mismatches =
                                p.rows
                                    |> List.filterMap
                                        (\row ->
                                            case SplitwiseImport.reconstruct (config p.memberNames) row of
                                                Just kind ->
                                                    let
                                                        actual : List Int
                                                        actual =
                                                            List.map (netOf [ entryFromKind kind ]) p.memberNames
                                                    in
                                                    if actual == row.nets then
                                                        Nothing

                                                    else
                                                        Just (row.description ++ ": expected " ++ Debug.toString row.nets ++ " got " ++ Debug.toString actual)

                                                Nothing ->
                                                    Just (row.description ++ ": no reconstruction")
                                        )
                        in
                        Expect.equal [] mismatches

                    Err e ->
                        Expect.fail e
        ]
