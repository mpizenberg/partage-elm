module Page.Home exposing (view)

import Dict
import Domain.Balance as Balance
import Format
import Json.Decode
import Route exposing (Route)
import SampleData
import UI.Theme as Theme
import Ui
import Ui.Events
import Ui.Font


view : (Route -> msg) -> Ui.Element msg
view onNavigate =
    Ui.column [ Ui.spacing Theme.spacing.md, Ui.width Ui.fill ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.xl, Ui.Font.bold ] (Ui.text "Your Groups")
        , groupCard onNavigate
        ]


groupCard : (Route -> msg) -> Ui.Element msg
groupCard onNavigate =
    let
        state =
            SampleData.groupState

        memberCount =
            Dict.size state.members

        userBalance =
            Dict.get SampleData.currentUserId state.balances

        balanceText =
            case userBalance of
                Just b ->
                    Format.formatCents b.netBalance

                Nothing ->
                    "0.00"

        balanceStatus =
            userBalance
                |> Maybe.map Balance.status
                |> Maybe.withDefault Balance.Settled

        balanceCol =
            Theme.balanceColor balanceStatus

        groupRoute =
            Route.GroupRoute SampleData.groupId (Route.Tab Route.BalanceTab)
    in
    Ui.column
        [ Ui.width Ui.fill
        , Ui.padding Theme.spacing.md
        , Ui.rounded Theme.rounding.md
        , Ui.border Theme.borderWidth.sm
        , Ui.borderColor Theme.neutral200
        , Ui.spacing Theme.spacing.sm
        , Ui.pointer
        , Ui.link (Route.toPath groupRoute)
        , Ui.Events.preventDefaultOn "click"
            (Json.Decode.succeed ( onNavigate groupRoute, True ))
        ]
        [ Ui.el [ Ui.Font.bold, Ui.Font.size Theme.fontSize.lg ] (Ui.text state.groupMeta.name)
        , case state.groupMeta.subtitle of
            Just sub ->
                Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ] (Ui.text sub)

            Nothing ->
                Ui.none
        , Ui.row [ Ui.width Ui.fill, Ui.spacing Theme.spacing.sm ]
            [ Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ]
                (Ui.text (String.fromInt memberCount ++ " members"))
            , Ui.el [ Ui.alignRight, Ui.Font.bold, Ui.Font.color balanceCol ]
                (Ui.text balanceText)
            ]
        ]
