module Page.Setup exposing (view)

import Translations as T exposing (I18n)
import UI.Theme as Theme
import Ui
import Ui.Font


view : I18n -> Ui.Element msg
view i18n =
    Ui.column [ Ui.spacing Theme.spacing.lg, Ui.width Ui.fill, Ui.paddingXY 0 Theme.spacing.xl ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.hero, Ui.Font.bold, Ui.centerX ] (Ui.text (T.setupWelcome i18n))
        , Ui.el [ Ui.Font.size Theme.fontSize.md, Ui.Font.color Theme.neutral700, Ui.centerX, Ui.Font.center ]
            (Ui.text (T.setupTagline i18n))
        , Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500, Ui.centerX, Ui.Font.center ]
            (Ui.text (T.setupIdentityNote i18n))
        ]
