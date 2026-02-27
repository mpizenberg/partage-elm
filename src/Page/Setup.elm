module Page.Setup exposing (view)

import Translations as T exposing (I18n)
import UI.Theme as Theme
import Ui
import Ui.Events
import Ui.Font


view : I18n -> { onGenerate : msg, isGenerating : Bool } -> Ui.Element msg
view i18n config =
    Ui.column [ Ui.spacing Theme.spacing.lg, Ui.width Ui.fill, Ui.paddingXY 0 Theme.spacing.xl ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.hero, Ui.Font.bold, Ui.centerX ] (Ui.text (T.setupWelcome i18n))
        , Ui.el [ Ui.Font.size Theme.fontSize.md, Ui.Font.color Theme.neutral700, Ui.centerX, Ui.Font.center ]
            (Ui.text (T.setupTagline i18n))
        , generateButton i18n config
        ]


generateButton : I18n -> { onGenerate : msg, isGenerating : Bool } -> Ui.Element msg
generateButton i18n config =
    let
        label =
            if config.isGenerating then
                T.setupGenerating i18n

            else
                T.setupGenerateButton i18n
    in
    Ui.el
        ([ Ui.centerX
         , Ui.paddingXY Theme.spacing.lg Theme.spacing.sm
         , Ui.rounded Theme.rounding.md
         , Ui.Font.color Theme.white
         , Ui.Font.size Theme.fontSize.md
         , Ui.Font.bold
         , Ui.Font.center
         ]
            ++ (if config.isGenerating then
                    [ Ui.background Theme.neutral500 ]

                else
                    [ Ui.background Theme.primary
                    , Ui.pointer
                    , Ui.Events.onClick config.onGenerate
                    ]
               )
        )
        (Ui.text label)
