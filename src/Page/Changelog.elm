module Page.Changelog exposing (view)

{-| What's new — the changelog as the reader sees it.
-}

import Changelog exposing (Entry)
import Translations as T exposing (I18n)
import UI.Components
import UI.Theme as Theme
import Ui
import Ui.Font


view : { i18n : I18n, onSuggest : Maybe msg } -> Ui.Element msg
view { i18n, onSuggest } =
    Ui.column
        [ Ui.spacing Theme.spacing.md
        , Ui.width Ui.fill
        , Ui.paddingXY 0 Theme.spacing.md
        ]
        ((case onSuggest of
            Just onPress ->
                [ suggestCard i18n onPress ]

            Nothing ->
                []
         )
            ++ List.map (viewEntry i18n) Changelog.entries
        )


suggestCard : I18n -> msg -> Ui.Element msg
suggestCard i18n onPress =
    UI.Components.card [ Ui.padding Theme.spacing.lg ]
        [ Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
            [ Ui.el
                [ Ui.Font.size Theme.font.md
                , Ui.Font.weight Theme.fontWeight.semibold
                ]
                (Ui.text (T.changelogSuggestTitle i18n))
            , UI.Components.btnPrimary []
                { label = T.changelogSuggestButton i18n
                , onPress = onPress
                }
            ]
        ]


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
