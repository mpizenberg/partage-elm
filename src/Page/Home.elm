module Page.Home exposing (view)

import Json.Decode
import Route exposing (Route)
import Storage exposing (GroupSummary)
import Translations as T exposing (I18n)
import UI.Theme as Theme
import Ui
import Ui.Events
import Ui.Font


view : I18n -> (Route -> msg) -> List GroupSummary -> Ui.Element msg
view i18n onNavigate groups =
    Ui.column [ Ui.spacing Theme.spacing.md, Ui.width Ui.fill ]
        ([ Ui.el [ Ui.Font.size Theme.fontSize.xl, Ui.Font.bold ] (Ui.text (T.homeYourGroups i18n)) ]
            ++ (if List.isEmpty groups then
                    [ Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ]
                        (Ui.text (T.homeNoGroups i18n))
                    ]

                else
                    List.map (groupCard i18n onNavigate) groups
               )
            ++ [ newGroupButton i18n onNavigate ]
        )


groupCard : I18n -> (Route -> msg) -> GroupSummary -> Ui.Element msg
groupCard i18n onNavigate summary =
    let
        groupRoute =
            Route.GroupRoute summary.id (Route.Tab Route.BalanceTab)
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
        [ Ui.el [ Ui.Font.bold, Ui.Font.size Theme.fontSize.lg ] (Ui.text summary.name)
        ]


newGroupButton : I18n -> (Route -> msg) -> Ui.Element msg
newGroupButton i18n onNavigate =
    let
        route =
            Route.NewGroup
    in
    Ui.el
        [ Ui.width Ui.fill
        , Ui.padding Theme.spacing.md
        , Ui.rounded Theme.rounding.md
        , Ui.background Theme.primary
        , Ui.Font.color Theme.white
        , Ui.Font.center
        , Ui.Font.bold
        , Ui.pointer
        , Ui.link (Route.toPath route)
        , Ui.Events.preventDefaultOn "click"
            (Json.Decode.succeed ( onNavigate route, True ))
        ]
        (Ui.text (T.homeNewGroup i18n))
