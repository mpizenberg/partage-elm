module Page.Group.BalanceTab exposing (view)

{-| Balance tab showing per-member balances and settlement plan.
-}

import Dict
import Domain.GroupState as GroupState exposing (GroupState)
import Domain.Member as Member
import Domain.Settlement as Settlement
import Translations as T exposing (I18n)
import UI.Components
import UI.Theme as Theme
import Ui
import Ui.Font


view : I18n -> Member.Id -> GroupState -> Ui.Element msg
view i18n currentUserRootId state =
    if Dict.isEmpty state.entries then
        Ui.column [ Ui.spacing Theme.spacing.lg, Ui.width Ui.fill ]
            [ Ui.el [ Ui.Font.size Theme.fontSize.lg, Ui.Font.bold ] (Ui.text (T.balanceTabTitle i18n))
            , Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ]
                (Ui.text (T.balanceNoEntries i18n))
            ]

    else
        Ui.column [ Ui.spacing Theme.spacing.lg, Ui.width Ui.fill ]
            [ balancesSection i18n state currentUserRootId
            , settlementSection i18n state
            ]


balancesSection : I18n -> GroupState -> Member.Id -> Ui.Element msg
balancesSection i18n state currentUserRootId =
    let
        resolveName =
            GroupState.resolveMemberName state

        balances =
            Dict.values state.balances

        -- Current user first, then sorted by name
        sorted =
            balances
                |> List.sortBy (\b -> ( boolToInt (b.memberRootId /= currentUserRootId), resolveName b.memberRootId ))

        boolToInt : Bool -> Int
        boolToInt b =
            if b then
                1

            else
                0
    in
    Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.lg, Ui.Font.bold ] (Ui.text (T.balanceTabTitle i18n))
        , Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
            (List.map
                (\b ->
                    UI.Components.balanceCard i18n
                        { name = resolveName b.memberRootId
                        , balance = b
                        , isCurrentUser = b.memberRootId == currentUserRootId
                        }
                )
                sorted
            )
        ]


settlementSection : I18n -> GroupState -> Ui.Element msg
settlementSection i18n state =
    let
        resolveName =
            GroupState.resolveMemberName state

        transactions =
            Settlement.computeSettlement state.balances []
    in
    Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.lg, Ui.Font.bold ] (Ui.text (T.balanceSettlementPlan i18n))
        , if List.isEmpty transactions then
            Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ]
                (Ui.text (T.balanceAllSettled i18n))

          else
            let
                settleTx =
                    UI.Components.settlementRow i18n resolveName
            in
            Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
                (List.map settleTx transactions)
        ]
