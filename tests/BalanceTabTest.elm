module BalanceTabTest exposing (suite)

import Expect
import Page.Group.BalanceTab as BalanceTab
import Test exposing (Test, test)


suite : Test
suite =
    test "recording a settlement collapses it without collapsing member details" <|
        \_ ->
            let
                transaction =
                    { from = "alice", to = "bob", amount = 1200 }

                memberExpanded =
                    BalanceTab.update (BalanceTab.ToggleMember "alice") BalanceTab.init
                        |> Tuple.first

                settlementExpanded =
                    BalanceTab.update (BalanceTab.ToggleSettlement 0) memberExpanded
                        |> Tuple.first
            in
            BalanceTab.update (BalanceTab.RecordTransfer transaction) settlementExpanded
                |> Expect.equal
                    ( memberExpanded
                    , Just (BalanceTab.RecordTransferOutput transaction)
                    )
