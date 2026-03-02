module Page.Home exposing (Context, view)

import Domain.Group as Group
import Json.Decode
import Route exposing (Route)
import Storage exposing (GroupSummary)
import Translations as T exposing (I18n)
import UI.Theme as Theme
import Ui
import Ui.Events
import Ui.Font


{-| Callbacks for the home page.
-}
type alias Context msg =
    { onNavigate : Route -> msg
    , onExport : Group.Id -> msg
    , onImport : msg
    }


{-| Render the home page listing existing groups and a button to create a new one.
-}
view : I18n -> Context msg -> Maybe String -> List GroupSummary -> Ui.Element msg
view i18n ctx importError groups =
    Ui.column [ Ui.spacing Theme.spacing.md, Ui.width Ui.fill ]
        (Ui.el [ Ui.Font.size Theme.fontSize.xl, Ui.Font.bold ] (Ui.text (T.homeYourGroups i18n))
            :: (case importError of
                    Just error ->
                        [ Ui.el
                            [ Ui.Font.size Theme.fontSize.sm
                            , Ui.Font.color Theme.danger
                            , Ui.padding Theme.spacing.sm
                            ]
                            (Ui.text error)
                        ]

                    Nothing ->
                        []
               )
            ++ (if List.isEmpty groups then
                    [ Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ]
                        (Ui.text (T.homeNoGroups i18n))
                    ]

                else
                    List.map (groupCard i18n ctx) groups
               )
            ++ [ Ui.row [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
                    [ newGroupButton i18n ctx.onNavigate
                    , importButton i18n ctx.onImport
                    ]
               ]
        )


groupCard : I18n -> Context msg -> GroupSummary -> Ui.Element msg
groupCard i18n ctx summary =
    let
        groupRoute : Route
        groupRoute =
            Route.GroupRoute summary.id (Route.Tab Route.BalanceTab)
    in
    Ui.row
        [ Ui.width Ui.fill
        , Ui.padding Theme.spacing.md
        , Ui.rounded Theme.rounding.md
        , Ui.border Theme.borderWidth.sm
        , Ui.borderColor Theme.neutral200
        , Ui.spacing Theme.spacing.sm
        ]
        [ Ui.el
            [ Ui.Font.bold
            , Ui.Font.size Theme.fontSize.lg
            , Ui.width Ui.fill
            , Ui.pointer
            , Ui.link (Route.toPath groupRoute)
            , Ui.Events.preventDefaultOn "click"
                (Json.Decode.succeed ( ctx.onNavigate groupRoute, True ))
            ]
            (Ui.text summary.name)
        , Ui.el
            [ Ui.Font.size Theme.fontSize.sm
            , Ui.Font.color Theme.primary
            , Ui.pointer
            , Ui.Events.onClick (ctx.onExport summary.id)
            ]
            (Ui.text (T.homeExportGroup i18n))
        ]


newGroupButton : I18n -> (Route -> msg) -> Ui.Element msg
newGroupButton i18n onNavigate =
    let
        route : Route
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


importButton : I18n -> msg -> Ui.Element msg
importButton i18n onImport =
    Ui.el
        [ Ui.width Ui.fill
        , Ui.padding Theme.spacing.md
        , Ui.rounded Theme.rounding.md
        , Ui.border Theme.borderWidth.sm
        , Ui.borderColor Theme.primary
        , Ui.Font.color Theme.primary
        , Ui.Font.center
        , Ui.Font.bold
        , Ui.pointer
        , Ui.Events.onClick onImport
        ]
        (Ui.text (T.homeImportGroup i18n))
