module Page.Group.BalanceTab exposing (view)

{-| Balance tab showing per-member balances and settlement plan.
-}

import Dict
import Domain.GroupState exposing (GroupState)
import Domain.Member as Member
import Domain.Settlement as Settlement
import UI.Components
import UI.Theme as Theme
import Ui
import Ui.Font


view : GroupState -> Member.Id -> (Member.Id -> String) -> Ui.Element msg
view state currentUser resolveName =
    Ui.column [ Ui.spacing Theme.spacing.lg, Ui.width Ui.fill ]
        [ balancesSection state currentUser resolveName
        , settlementSection state resolveName
        ]


balancesSection : GroupState -> Member.Id -> (Member.Id -> String) -> Ui.Element msg
balancesSection state currentUser resolveName =
    let
        balances =
            Dict.values state.balances

        -- Current user first, then sorted by name
        sorted =
            balances
                |> List.sortBy (\b -> ( boolToInt (b.memberRootId /= currentUser), resolveName b.memberRootId ))

        boolToInt : Bool -> Int
        boolToInt b =
            if b then
                1

            else
                0
    in
    Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
        [ Ui.el [ Ui.Font.size 18, Ui.Font.bold ] (Ui.text "Balances")
        , Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
            (List.map
                (\b ->
                    UI.Components.balanceCard
                        { name = resolveName b.memberRootId
                        , balance = b
                        , isCurrentUser = b.memberRootId == currentUser
                        }
                )
                sorted
            )
        ]


settlementSection : GroupState -> (Member.Id -> String) -> Ui.Element msg
settlementSection state resolveName =
    let
        transactions =
            Settlement.computeSettlement state.balances []
    in
    Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
        [ Ui.el [ Ui.Font.size 18, Ui.Font.bold ] (Ui.text "Settlement Plan")
        , if List.isEmpty transactions then
            Ui.el [ Ui.Font.size 14, Ui.Font.color Theme.neutral500 ]
                (Ui.text "All settled up!")

          else
            Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
                (List.map
                    (\t ->
                        UI.Components.settlementRow
                            { transaction = t
                            , resolveName = resolveName
                            }
                    )
                    transactions
                )
        ]
