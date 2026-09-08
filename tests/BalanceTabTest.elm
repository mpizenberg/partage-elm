module BalanceTabTest exposing (suite)

import Expect
import Page.Group.BalanceTab as BalanceTab
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "settlement selection"
        [ test "initially expands the first outgoing payment" <|
            \_ ->
                let
                    incoming =
                        { from = "carol", to = "alice", amount = 300 }

                    firstOutgoing =
                        { from = "alice", to = "bob", amount = 1200 }

                    secondOutgoing =
                        { from = "alice", to = "dave", amount = 500 }
                in
                BalanceTab.selectedSettlement
                    (Just "alice")
                    [ incoming, firstOutgoing, secondOutgoing ]
                    BalanceTab.init
                    |> Expect.equal (Just firstOutgoing)
        , test "an explicit collapse suppresses automatic expansion" <|
            \_ ->
                let
                    transaction =
                        { from = "alice", to = "bob", amount = 1200 }

                    collapsed =
                        BalanceTab.update BalanceTab.CollapseSettlements BalanceTab.init
                            |> Tuple.first
                in
                BalanceTab.selectedSettlement (Just "alice") [ transaction ] collapsed
                    |> Expect.equal Nothing
        , test "recording a settlement collapses it without collapsing member details" <|
            \_ ->
                let
                    transaction =
                        { from = "alice", to = "bob", amount = 1200 }

                    memberExpanded =
                        BalanceTab.update (BalanceTab.ToggleMember "alice") BalanceTab.init
                            |> Tuple.first

                    settlementExpanded =
                        BalanceTab.update (BalanceTab.SelectSettlement transaction) memberExpanded
                            |> Tuple.first

                    collapsedMember =
                        BalanceTab.update BalanceTab.CollapseSettlements memberExpanded
                            |> Tuple.first
                in
                BalanceTab.update (BalanceTab.RecordTransfer transaction) settlementExpanded
                    |> Expect.equal
                        ( collapsedMember
                        , Just (BalanceTab.RecordTransferOutput transaction)
                        )
        ]
