module SettlementTest exposing (suite)

import Dict exposing (Dict)
import Domain.Balance exposing (MemberBalance)
import Domain.Member as Member
import Domain.Settlement as Settlement exposing (Preference, Transaction)
import Expect
import Fuzz exposing (Fuzzer)
import Test exposing (..)


suite : Test
suite =
    describe "Settlement"
        [ simpleTests
        , preferenceTests
        , invariantTests
        ]


simpleTests : Test
simpleTests =
    describe "Simple settlement"
        [ test "no debts produces no transactions" <|
            \_ ->
                let
                    balances =
                        balancesFromList
                            [ { memberRootId = "alice", totalPaid = 500, totalOwed = 500, netBalance = 0 }
                            , { memberRootId = "bob", totalPaid = 500, totalOwed = 500, netBalance = 0 }
                            ]

                    transactions =
                        Settlement.computeSettlement balances []
                in
                Expect.equal [] transactions
        , test "simple two-person settlement" <|
            \_ ->
                let
                    balances =
                        balancesFromList
                            [ { memberRootId = "alice", totalPaid = 1000, totalOwed = 500, netBalance = 500 }
                            , { memberRootId = "bob", totalPaid = 0, totalOwed = 500, netBalance = -500 }
                            ]

                    transactions =
                        Settlement.computeSettlement balances []
                in
                Expect.equal
                    [ { from = "bob", to = "alice", amount = 500 } ]
                    transactions
        , test "three-person settlement" <|
            \_ ->
                let
                    balances =
                        balancesFromList
                            [ { memberRootId = "alice", totalPaid = 900, totalOwed = 300, netBalance = 600 }
                            , { memberRootId = "bob", totalPaid = 0, totalOwed = 300, netBalance = -300 }
                            , { memberRootId = "carol", totalPaid = 0, totalOwed = 300, netBalance = -300 }
                            ]

                    transactions =
                        Settlement.computeSettlement balances []

                    totalTransferred =
                        List.foldl (\t acc -> acc + t.amount) 0 transactions
                in
                -- Total transferred should equal total debt (600)
                Expect.equal 600 totalTransferred
        ]


preferenceTests : Test
preferenceTests =
    describe "Preference-aware settlement"
        [ test "debtor settles with preferred creditor first" <|
            \_ ->
                let
                    balances =
                        balancesFromList
                            [ { memberRootId = "alice", totalPaid = 600, totalOwed = 200, netBalance = 400 }
                            , { memberRootId = "bob", totalPaid = 400, totalOwed = 200, netBalance = 200 }
                            , { memberRootId = "carol", totalPaid = 0, totalOwed = 600, netBalance = -600 }
                            ]

                    preferences =
                        [ { memberRootId = "carol", preferredRecipients = [ "bob", "alice" ] } ]

                    transactions =
                        Settlement.computeSettlement balances preferences

                    carolToBob =
                        List.filter (\t -> t.from == "carol" && t.to == "bob") transactions
                            |> List.head
                in
                -- Carol should pay Bob first (up to Bob's credit of 200)
                case carolToBob of
                    Just t ->
                        Expect.equal 200 t.amount

                    Nothing ->
                        Expect.fail "Carol should have a transaction to Bob"
        ]


invariantTests : Test
invariantTests =
    describe "Settlement invariants"
        [ test "all amounts are positive" <|
            \_ ->
                let
                    balances =
                        balancesFromList
                            [ { memberRootId = "alice", totalPaid = 1000, totalOwed = 333, netBalance = 667 }
                            , { memberRootId = "bob", totalPaid = 0, totalOwed = 334, netBalance = -334 }
                            , { memberRootId = "carol", totalPaid = 0, totalOwed = 333, netBalance = -333 }
                            ]

                    transactions =
                        Settlement.computeSettlement balances []

                    allPositive =
                        List.all (\t -> t.amount > 0) transactions
                in
                Expect.equal True allPositive
        , test "total transferred equals total debt" <|
            \_ ->
                let
                    balances =
                        balancesFromList
                            [ { memberRootId = "alice", totalPaid = 1000, totalOwed = 250, netBalance = 750 }
                            , { memberRootId = "bob", totalPaid = 0, totalOwed = 250, netBalance = -250 }
                            , { memberRootId = "carol", totalPaid = 0, totalOwed = 250, netBalance = -250 }
                            , { memberRootId = "dave", totalPaid = 0, totalOwed = 250, netBalance = -250 }
                            ]

                    transactions =
                        Settlement.computeSettlement balances []

                    totalTransferred =
                        List.foldl (\t acc -> acc + t.amount) 0 transactions

                    totalDebt =
                        Dict.values balances
                            |> List.filter (\b -> b.netBalance < 0)
                            |> List.foldl (\b acc -> acc + abs b.netBalance) 0
                in
                Expect.equal totalDebt totalTransferred
        , fuzz balancesFuzzer "total transferred equals total debt (fuzz)" <|
            \balances ->
                let
                    transactions =
                        Settlement.computeSettlement balances []

                    totalTransferred =
                        List.foldl (\t acc -> acc + t.amount) 0 transactions

                    totalDebt =
                        Dict.values balances
                            |> List.filter (\b -> b.netBalance < 0)
                            |> List.foldl (\b acc -> acc + abs b.netBalance) 0
                in
                Expect.equal totalDebt totalTransferred
        , fuzz balancesFuzzer "all transaction amounts are positive (fuzz)" <|
            \balances ->
                let
                    transactions =
                        Settlement.computeSettlement balances []

                    allPositive =
                        List.all (\t -> t.amount > 0) transactions
                in
                Expect.equal True allPositive
        ]


balancesFromList : List MemberBalance -> Dict Member.Id MemberBalance
balancesFromList balances =
    balances
        |> List.map (\b -> ( b.memberRootId, b ))
        |> Dict.fromList


{-| Fuzzer that generates balanced member balances (sum of nets = 0).
Generates 2-4 members with random paid/owed amounts, then adjusts the last
member so that total net = 0.
-}
balancesFuzzer : Fuzzer (Dict Member.Id MemberBalance)
balancesFuzzer =
    Fuzz.map3
        (\a b c ->
            let
                aliceNet =
                    a

                bobNet =
                    b

                carolNet =
                    -(aliceNet + bobNet + c)

                daveNet =
                    c

                makeBalance id net =
                    if net >= 0 then
                        { memberRootId = id, totalPaid = net, totalOwed = 0, netBalance = net }

                    else
                        { memberRootId = id, totalPaid = 0, totalOwed = abs net, netBalance = net }
            in
            balancesFromList
                [ makeBalance "alice" aliceNet
                , makeBalance "bob" bobNet
                , makeBalance "carol" carolNet
                , makeBalance "dave" daveNet
                ]
        )
        (Fuzz.intRange -500 500)
        (Fuzz.intRange -500 500)
        (Fuzz.intRange -500 500)
