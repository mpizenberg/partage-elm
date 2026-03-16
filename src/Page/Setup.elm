module Page.Setup exposing (view)

import Translations as T exposing (I18n, Language)
import UI.Components
import UI.Theme as Theme
import Ui
import Ui.Font


{-| Render the setup page with welcome message and key generation button.
-}
view : I18n -> { onGenerate : msg, onSwitchLanguage : Language -> msg, isGenerating : Bool } -> Ui.Element msg
view i18n config =
    Ui.column [ Ui.spacing Theme.spacing.xl, Ui.width Ui.fill, Ui.paddingXY 0 Theme.spacing.xxl ]
        [ Ui.el
            [ Ui.Font.size Theme.font.xxxl
            , Ui.Font.weight Theme.fontWeight.bold
            , Ui.Font.letterSpacing Theme.letterSpacing.tight
            , Ui.centerX
            ]
            (Ui.text (T.setupWelcome i18n))
        , Ui.el
            [ Ui.Font.size Theme.font.md
            , Ui.Font.color Theme.base.textSubtle
            , Ui.centerX
            , Ui.Font.center
            ]
            (Ui.text (T.setupTagline i18n))
        , if config.isGenerating then
            Ui.el
                [ Ui.centerX
                , Ui.Font.size Theme.font.md
                , Ui.Font.color Theme.base.textSubtle
                , Ui.Font.weight Theme.fontWeight.medium
                ]
                (Ui.text (T.setupGenerating i18n))

          else
            UI.Components.btnPrimary []
                { label = T.setupGenerateButton i18n
                , onPress = config.onGenerate
                }
        , Ui.el [ Ui.centerX ]
            (UI.Components.languageSelector config.onSwitchLanguage (T.currentLanguage i18n))
        ]
