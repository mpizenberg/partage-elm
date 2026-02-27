module BalanceTest exposing (suite)

import Dict
import Domain.Balance as Balance exposing (MemberBalance, Status(..))
import Domain.Currency exposing (Currency(..))
import Domain.Entry as Entry exposing (Beneficiary(..), Kind(..))
import Expect
import Fuzz
import Test exposing (..)
import TestHelpers exposing (..)


suite : Test
suite =
    describe "Balance"
        [ statusTests
        , simpleSplitTests
        , sharesRemainderTests
        , transferTests
        , multiCurrencyTests
        , invariantTests
        ]


statusTests : Test
statusTests =
    describe "status"
        [ test "positive balance is Creditor" <|
            \_ ->
                Balance.status { memberRootId = "a", totalPaid = 100, totalOwed = 50, netBalance = 50 }
                    |> Expect.equal Creditor
        , test "negative balance is Debtor" <|
            \_ ->
                Balance.status { memberRootId = "a", totalPaid = 50, totalOwed = 100, netBalance = -50 }
                    |> Expect.equal Debtor
        , test "zero balance is Settled" <|
            \_ ->
                Balance.status { memberRootId = "a", totalPaid = 100, totalOwed = 100, netBalance = 0 }
                    |> Expect.equal Settled
        ]


equalSplitEntry : Entry.Entry
equalSplitEntry =
    makeExpenseEntry "entry1"
        1000
        { defaultExpenseData
            | amount = 1000
            , payers = [ { memberId = "alice", amount = 1000 } ]
            , beneficiaries =
                [ ShareBeneficiary { memberId = "alice", shares = 1 }
                , ShareBeneficiary { memberId = "bob", shares = 1 }
                ]
        }


equalSplitBalances : Dict.Dict String MemberBalance
equalSplitBalances =
    Balance.computeBalances identity [ equalSplitEntry ]


simpleSplitTests : Test
simpleSplitTests =
    describe "Simple splits"
        [ describe "equal split between two members"
            [ test "alice paid 1000" <|
                \_ ->
                    Dict.get "alice" equalSplitBalances
                        |> Maybe.map .totalPaid
                        |> Expect.equal (Just 1000)
            , test "alice owes 500" <|
                \_ ->
                    Dict.get "alice" equalSplitBalances
                        |> Maybe.map .totalOwed
                        |> Expect.equal (Just 500)
            , test "alice net balance is 500" <|
                \_ ->
                    Dict.get "alice" equalSplitBalances
                        |> Maybe.map .netBalance
                        |> Expect.equal (Just 500)
            , test "bob paid 0" <|
                \_ ->
                    Dict.get "bob" equalSplitBalances
                        |> Maybe.map .totalPaid
                        |> Expect.equal (Just 0)
            , test "bob owes 500" <|
                \_ ->
                    Dict.get "bob" equalSplitBalances
                        |> Maybe.map .totalOwed
                        |> Expect.equal (Just 500)
            , test "bob net balance is -500" <|
                \_ ->
                    Dict.get "bob" equalSplitBalances
                        |> Maybe.map .netBalance
                        |> Expect.equal (Just -500)
            ]
        , test "exact split assigns correct amounts" <|
            \_ ->
                let
                    entry =
                        makeExpenseEntry "entry1"
                            1000
                            { defaultExpenseData
                                | amount = 1000
                                , payers = [ { memberId = "alice", amount = 1000 } ]
                                , beneficiaries =
                                    [ ExactBeneficiary { memberId = "alice", amount = 300 }
                                    , ExactBeneficiary { memberId = "bob", amount = 700 }
                                    ]
                            }

                    balances =
                        Balance.computeBalances identity [ entry ]
                in
                Dict.get "bob" balances
                    |> Maybe.map .totalOwed
                    |> Expect.equal (Just 700)
        , describe "multiple payers"
            (let
                entry =
                    makeExpenseEntry "entry1"
                        1000
                        { defaultExpenseData
                            | amount = 1000
                            , payers =
                                [ { memberId = "alice", amount = 600 }
                                , { memberId = "bob", amount = 400 }
                                ]
                            , beneficiaries =
                                [ ShareBeneficiary { memberId = "alice", shares = 1 }
                                , ShareBeneficiary { memberId = "bob", shares = 1 }
                                ]
                        }

                balances =
                    Balance.computeBalances identity [ entry ]
             in
             [ test "alice paid 600" <|
                \_ ->
                    Dict.get "alice" balances
                        |> Maybe.map .totalPaid
                        |> Expect.equal (Just 600)
             , test "alice owes 500" <|
                \_ ->
                    Dict.get "alice" balances
                        |> Maybe.map .totalOwed
                        |> Expect.equal (Just 500)
             , test "alice net balance is 100" <|
                \_ ->
                    Dict.get "alice" balances
                        |> Maybe.map .netBalance
                        |> Expect.equal (Just 100)
             ]
            )
        ]


sharesRemainderTests : Test
sharesRemainderTests =
    describe "Shares remainder distribution"
        [ test "total owed equals total amount with 3-way split" <|
            \_ ->
                let
                    entry =
                        makeExpenseEntry "entry1"
                            1000
                            { defaultExpenseData
                                | amount = 1000
                                , payers = [ { memberId = "alice", amount = 1000 } ]
                                , beneficiaries =
                                    [ ShareBeneficiary { memberId = "alice", shares = 1 }
                                    , ShareBeneficiary { memberId = "bob", shares = 1 }
                                    , ShareBeneficiary { memberId = "carol", shares = 1 }
                                    ]
                            }

                    balances =
                        Balance.computeBalances identity [ entry ]

                    totalOwed =
                        Dict.foldl (\_ b acc -> acc + b.totalOwed) 0 balances
                in
                Expect.equal 1000 totalOwed
        , test "total owed equals total amount with unequal shares" <|
            \_ ->
                let
                    entry =
                        makeExpenseEntry "entry1"
                            1000
                            { defaultExpenseData
                                | amount = 1000
                                , payers = [ { memberId = "alice", amount = 1000 } ]
                                , beneficiaries =
                                    [ ShareBeneficiary { memberId = "alice", shares = 2 }
                                    , ShareBeneficiary { memberId = "bob", shares = 1 }
                                    ]
                            }

                    balances =
                        Balance.computeBalances identity [ entry ]

                    totalOwed =
                        Dict.foldl (\_ b acc -> acc + b.totalOwed) 0 balances
                in
                Expect.equal 1000 totalOwed
        ]


transferTests : Test
transferTests =
    let
        entry =
            makeTransferEntry "t1"
                1000
                { defaultTransferData
                    | amount = 500
                    , from = "alice"
                    , to = "bob"
                }

        balances =
            Balance.computeBalances identity [ entry ]
    in
    describe "Transfers"
        [ test "sender has positive net balance" <|
            \_ ->
                Dict.get "alice" balances
                    |> Maybe.map .netBalance
                    |> Expect.equal (Just 500)
        , test "receiver has negative net balance" <|
            \_ ->
                Dict.get "bob" balances
                    |> Maybe.map .netBalance
                    |> Expect.equal (Just -500)
        ]


multiCurrencyTests : Test
multiCurrencyTests =
    describe "Multi-currency"
        [ describe "expense with defaultCurrencyAmount"
            (let
                entry =
                    makeExpenseEntry "entry1"
                        1000
                        { defaultExpenseData
                            | amount = 1000
                            , currency = GBP
                            , defaultCurrencyAmount = Just 1200
                            , payers = [ { memberId = "alice", amount = 1000 } ]
                            , beneficiaries =
                                [ ShareBeneficiary { memberId = "alice", shares = 1 }
                                , ShareBeneficiary { memberId = "bob", shares = 1 }
                                ]
                        }

                balances =
                    Balance.computeBalances identity [ entry ]
             in
             [ test "payer amount is converted to default currency" <|
                \_ ->
                    Dict.get "alice" balances
                        |> Maybe.map .totalPaid
                        |> Expect.equal (Just 1200)
             , test "owed amount uses default currency total" <|
                \_ ->
                    Dict.get "alice" balances
                        |> Maybe.map .totalOwed
                        |> Expect.equal (Just 600)
             ]
            )
        , test "multi-currency transfer uses defaultCurrencyAmount" <|
            \_ ->
                let
                    entry =
                        makeTransferEntry "t1"
                            1000
                            { defaultTransferData
                                | amount = 100
                                , currency = GBP
                                , defaultCurrencyAmount = Just 120
                                , from = "alice"
                                , to = "bob"
                            }

                    balances =
                        Balance.computeBalances identity [ entry ]
                in
                Dict.get "alice" balances
                    |> Maybe.map .totalPaid
                    |> Expect.equal (Just 120)
        ]


invariantTests : Test
invariantTests =
    describe "Balance invariants"
        [ fuzz (Fuzz.intRange 1 10000) "sum of net balances is always zero" <|
            \amount ->
                let
                    entry =
                        makeExpenseEntry "entry1"
                            1000
                            { defaultExpenseData
                                | amount = amount
                                , payers = [ { memberId = "alice", amount = amount } ]
                                , beneficiaries =
                                    [ ShareBeneficiary { memberId = "alice", shares = 1 }
                                    , ShareBeneficiary { memberId = "bob", shares = 1 }
                                    , ShareBeneficiary { memberId = "carol", shares = 1 }
                                    ]
                            }

                    balances =
                        Balance.computeBalances identity [ entry ]

                    totalNet =
                        Dict.foldl (\_ b acc -> acc + b.netBalance) 0 balances
                in
                Expect.equal 0 totalNet
        , fuzz (Fuzz.intRange 1 10000) "netBalance equals totalPaid minus totalOwed for each member" <|
            \amount ->
                let
                    entry =
                        makeExpenseEntry "entry1"
                            1000
                            { defaultExpenseData
                                | amount = amount
                                , payers = [ { memberId = "alice", amount = amount } ]
                                , beneficiaries =
                                    [ ShareBeneficiary { memberId = "alice", shares = 1 }
                                    , ShareBeneficiary { memberId = "bob", shares = 1 }
                                    ]
                            }

                    balances =
                        Balance.computeBalances identity [ entry ]

                    allCorrect =
                        Dict.values balances
                            |> List.all (\b -> b.netBalance == b.totalPaid - b.totalOwed)
                in
                Expect.equal True allCorrect
        , fuzz (Fuzz.intRange 1 10000) "total paid equals total owed" <|
            \amount ->
                let
                    entry =
                        makeExpenseEntry "entry1"
                            1000
                            { defaultExpenseData
                                | amount = amount
                                , payers = [ { memberId = "alice", amount = amount } ]
                                , beneficiaries =
                                    [ ShareBeneficiary { memberId = "alice", shares = 1 }
                                    , ShareBeneficiary { memberId = "bob", shares = 1 }
                                    , ShareBeneficiary { memberId = "carol", shares = 1 }
                                    ]
                            }

                    balances =
                        Balance.computeBalances identity [ entry ]

                    totalPaid =
                        Dict.foldl (\_ b acc -> acc + b.totalPaid) 0 balances

                    totalOwed =
                        Dict.foldl (\_ b acc -> acc + b.totalOwed) 0 balances
                in
                Expect.equal totalPaid totalOwed
        ]
