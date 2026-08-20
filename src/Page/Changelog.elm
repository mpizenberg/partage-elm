module Page.Changelog exposing (view)

{-| What's new — the changelog as the reader sees it.
-}

import Changelog exposing (Entry)
import Translations exposing (I18n)
import UI.Components
import UI.Theme as Theme
import Ui
import Ui.Font


view : I18n -> Ui.Element msg
view i18n =
    Ui.column
        [ Ui.spacing Theme.spacing.md
        , Ui.width Ui.fill
        , Ui.paddingXY 0 Theme.spacing.md
        ]
        (List.map (viewEntry i18n) Changelog.entries)


viewEntry : I18n -> Entry -> Ui.Element msg
viewEntry i18n entry =
    UI.Components.card [ Ui.padding Theme.spacing.lg ]
        [ Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
            [ Ui.el
                [ Ui.Font.size Theme.font.xs
                , Ui.Font.color Theme.base.textSubtle
                ]
                (Ui.text entry.date)
            , Ui.el
                [ Ui.Font.size Theme.font.md
                , Ui.Font.weight Theme.fontWeight.semibold
                ]
                (Ui.text (entry.title i18n))
            , Ui.el
                [ Ui.Font.size Theme.font.sm
                , Ui.Font.color Theme.base.text
                ]
                (Ui.text (entry.body i18n))
            ]
        ]
