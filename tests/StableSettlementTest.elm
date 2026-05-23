module StableSettlementTest exposing (suite)

import Dict exposing (Dict)
import Domain.Balance exposing (MemberBalance)
import Domain.Member as Member
import Domain.Settlement as Settlement
import Domain.StableSettlement as StableSettlement
import Expect
import Fuzz exposing (Fuzzer)
import Test exposing (Test, describe, fuzz, test)


suite : Test
suite =
    describe "StableSettlement"
        [ anchorEquivalenceTests
        , compatibleTransferTests
        , rerouteTests
        , signFlipTests
        , fallbackTests
        , flowFeasibilityTests
        ]



-- TEST GROUPS


anchorEquivalenceTests : Test
anchorEquivalenceTests =
    describe "Equivalence at anchor (Δ = 0)"
        [ test "no transfers since anchor returns the greedy plan" <|
            \_ ->
                let
                    balances : Dict Member.Id MemberBalance
                    balances =
                        balancesFromNets [ ( "alice", 600 ), ( "bob", -300 ), ( "carol", -300 ) ]
                in
                StableSettlement.stablePlan balances [] balances
                    |> Expect.equalLists
                        (Settlement.computeSettlement balances [])
        , test "no transfers since anchor with preferences" <|
            \_ ->
                let
                    balances : Dict Member.Id MemberBalance
                    balances =
                        balancesFromNets [ ( "alice", 400 ), ( "bob", 200 ), ( "carol", -600 ) ]

                    prefs : List Settlement.Preference
                    prefs =
                        [ { memberRootId = "carol", preferredRecipients = [ "bob", "alice" ] } ]
                in
                StableSettlement.stablePlan balances prefs balances
                    |> Expect.equalLists
                        (Settlement.computeSettlement balances prefs)
        ]


compatibleTransferTests : Test
compatibleTransferTests =
    describe "Compatible transfer (consume along existing plan edge)"
        [ test "single existing edge reduced by transfer amount" <|
            \_ ->
                let
                    anchor : Dict Member.Id MemberBalance
                    anchor =
                        balancesFromNets [ ( "alice", 500 ), ( "bob", -500 ) ]

                    current : Dict Member.Id MemberBalance
                    current =
                        balancesFromNets [ ( "alice", 200 ), ( "bob", -200 ) ]
                in
                StableSettlement.stablePlan anchor [] current
                    |> Expect.equalLists
                        [ { from = "bob", to = "alice", amount = 200 } ]
        , test "exact-match transfer settles the edge" <|
            \_ ->
                let
                    anchor : Dict Member.Id MemberBalance
                    anchor =
                        balancesFromNets [ ( "alice", 100 ), ( "bob", -100 ) ]

                    current : Dict Member.Id MemberBalance
                    current =
                        balancesFromNets [ ( "alice", 0 ), ( "bob", 0 ) ]
                in
                StableSettlement.stablePlan anchor [] current
                    |> Expect.equalLists []
        , test "transfer along one edge does not move sibling edges" <|
            \_ ->
                let
                    anchor : Dict Member.Id MemberBalance
                    anchor =
                        balancesFromNets
                            [ ( "alice", 300 )
                            , ( "carol", 200 )
                            , ( "bob", -500 )
                            ]

                    -- bob paid alice 100
                    current : Dict Member.Id MemberBalance
                    current =
                        balancesFromNets
                            [ ( "alice", 200 )
                            , ( "carol", 200 )
                            , ( "bob", -400 )
                            ]

                    base : List Settlement.Transaction
                    base =
                        Settlement.computeSettlement anchor []

                    result : List Settlement.Transaction
                    result =
                        StableSettlement.stablePlan anchor [] current

                    -- carol's incoming should be untouched
                    carolEdges : List Settlement.Transaction -> List Settlement.Transaction
                    carolEdges =
                        List.filter (\t -> t.to == "carol")
                in
                Expect.equal (carolEdges base) (carolEdges result)
        ]


rerouteTests : Test
rerouteTests =
    describe "Case (a) reroute (transfer between two plan participants not directly connected)"
        [ test "transfer from one debtor to a creditor without direct edge produces bypass" <|
            \_ ->
                -- Anchor plan should be alice→carol (300), bob→carol (200) by the greedy pass
                let
                    anchor : Dict Member.Id MemberBalance
                    anchor =
                        balancesFromNets
                            [ ( "alice", -300 )
                            , ( "bob", -200 )
                            , ( "carol", 500 )
                            ]

                    anchorPlan : List Settlement.Transaction
                    anchorPlan =
                        Settlement.computeSettlement anchor []

                    -- alice transferred 100 directly to bob.
                    -- New balances: alice net = -200, bob = -300, carol = +500.
                    current : Dict Member.Id MemberBalance
                    current =
                        balancesFromNets
                            [ ( "alice", -200 )
                            , ( "bob", -300 )
                            , ( "carol", 500 )
                            ]

                    result : List Settlement.Transaction
                    result =
                        StableSettlement.stablePlan anchor [] current
                in
                Expect.all
                    [ \_ -> expectFeasible current result
                    , \_ -> expectTotalAmountUnchanged anchorPlan result
                    ]
                    ()
        ]


signFlipTests : Test
signFlipTests =
    describe "Sign-flips"
        [ test "creditor over-receives and becomes debtor" <|
            \_ ->
                let
                    anchor : Dict Member.Id MemberBalance
                    anchor =
                        balancesFromNets
                            [ ( "alice", 100 )
                            , ( "bob", -100 )
                            ]

                    -- bob transferred 250 to alice; alice ends up debtor.
                    current : Dict Member.Id MemberBalance
                    current =
                        balancesFromNets
                            [ ( "alice", -150 )
                            , ( "bob", 150 )
                            ]

                    result : List Settlement.Transaction
                    result =
                        StableSettlement.stablePlan anchor [] current
                in
                Expect.all
                    [ \_ -> expectFeasible current result
                    , \_ ->
                        result
                            |> List.filter (\t -> t.amount > 0)
                            |> List.length
                            |> Expect.atLeast 1
                    ]
                    ()
        ]


fallbackTests : Test
fallbackTests =
    describe "Total residual fallback"
        [ test "transfer to outsider with single debtor and single creditor" <|
            \_ ->
                let
                    anchor : Dict Member.Id MemberBalance
                    anchor =
                        balancesFromNets
                            [ ( "alice", 500 )
                            , ( "bob", -500 )
                            ]

                    -- bob paid carol (not in plan) 100. New: alice +500, bob -400, carol -100.
                    current : Dict Member.Id MemberBalance
                    current =
                        balancesFromNets
                            [ ( "alice", 500 )
                            , ( "bob", -400 )
                            , ( "carol", -100 )
                            ]

                    result : List Settlement.Transaction
                    result =
                        StableSettlement.stablePlan anchor [] current
                in
                expectFeasible current result
        ]


flowFeasibilityTests : Test
flowFeasibilityTests =
    describe "Flow feasibility (property)"
        [ fuzz balancePairFuzzer "result satisfies per-node flow conservation" <|
            \( anchor, current ) ->
                let
                    plan : List Settlement.Transaction
                    plan =
                        StableSettlement.stablePlan anchor [] current
                in
                expectFeasible current plan
        , fuzz balancePairFuzzer "amounts are strictly positive" <|
            \( anchor, current ) ->
                StableSettlement.stablePlan anchor [] current
                    |> List.all (\t -> t.amount > 0)
                    |> Expect.equal True
        ]



-- HELPERS


balancesFromNets : List ( Member.Id, Int ) -> Dict Member.Id MemberBalance
balancesFromNets nets =
    nets
        |> List.map
            (\( id, net ) ->
                if net >= 0 then
                    ( id, { memberRootId = id, totalPaid = net, totalOwed = 0, netBalance = net } )

                else
                    ( id, { memberRootId = id, totalPaid = 0, totalOwed = -net, netBalance = net } )
            )
        |> Dict.fromList


{-| Verify per-node flow conservation: (Σ out − Σ in) = −netBalance.
-}
expectFeasible : Dict Member.Id MemberBalance -> List Settlement.Transaction -> Expect.Expectation
expectFeasible balances plan =
    let
        nodes : List Member.Id
        nodes =
            (Dict.keys balances
                ++ List.map .from plan
                ++ List.map .to plan
            )
                |> List.foldl
                    (\k acc ->
                        if List.member k acc then
                            acc

                        else
                            k :: acc
                    )
                    []

        netFlow : Member.Id -> Int
        netFlow n =
            let
                outgoing : Int
                outgoing =
                    plan
                        |> List.filter (\t -> t.from == n)
                        |> List.foldl (\t acc -> acc + t.amount) 0

                incoming : Int
                incoming =
                    plan
                        |> List.filter (\t -> t.to == n)
                        |> List.foldl (\t acc -> acc + t.amount) 0
            in
            outgoing - incoming

        netBalance : Member.Id -> Int
        netBalance n =
            Dict.get n balances
                |> Maybe.map .netBalance
                |> Maybe.withDefault 0

        violations : List ( Member.Id, Int, Int )
        violations =
            nodes
                |> List.filterMap
                    (\n ->
                        let
                            flow : Int
                            flow =
                                netFlow n

                            expected : Int
                            expected =
                                -(netBalance n)
                        in
                        if flow == expected then
                            Nothing

                        else
                            Just ( n, flow, expected )
                    )
    in
    Expect.equalLists [] violations


expectTotalAmountUnchanged : List Settlement.Transaction -> List Settlement.Transaction -> Expect.Expectation
expectTotalAmountUnchanged a b =
    let
        total : List Settlement.Transaction -> Int
        total =
            List.foldl (\t acc -> acc + t.amount) 0
    in
    Expect.equal (total a) (total b)



-- FUZZERS


{-| Produce a pair of balance dicts that share keys and individually sum to 0,
suitable for fuzzing the stable plan against any Δ vector that itself sums to 0.
-}
balancePairFuzzer : Fuzzer ( Dict Member.Id MemberBalance, Dict Member.Id MemberBalance )
balancePairFuzzer =
    Fuzz.map2
        (\anchorNets currentNets ->
            ( balancesFromNets (zeroSum anchorNets)
            , balancesFromNets (zeroSum currentNets)
            )
        )
        threeNetsFuzzer
        threeNetsFuzzer


threeNetsFuzzer : Fuzzer (List ( Member.Id, Int ))
threeNetsFuzzer =
    Fuzz.map3
        (\a b c ->
            [ ( "alice", a ), ( "bob", b ), ( "carol", c ) ]
        )
        (Fuzz.intRange -500 500)
        (Fuzz.intRange -500 500)
        (Fuzz.intRange -500 500)


zeroSum : List ( Member.Id, Int ) -> List ( Member.Id, Int )
zeroSum nets =
    case List.reverse nets of
        [] ->
            []

        ( lastId, _ ) :: restRev ->
            let
                rest : List ( Member.Id, Int )
                rest =
                    List.reverse restRev

                sumRest : Int
                sumRest =
                    List.foldl (\( _, v ) acc -> acc + v) 0 rest
            in
            rest ++ [ ( lastId, -sumRest ) ]
