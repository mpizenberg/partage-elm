module Page.NotFound exposing (view)

import Translations as T exposing (I18n)
import UI.Theme as Theme
import Ui
import Ui.Font


view : I18n -> Ui.Element msg
view i18n =
    Ui.column [ Ui.spacing Theme.spacing.md, Ui.width Ui.fill, Ui.paddingXY 0 Theme.spacing.xl ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.hero, Ui.Font.bold, Ui.centerX ] (Ui.text (T.notFoundCode i18n))
        , Ui.el [ Ui.Font.size Theme.fontSize.md, Ui.Font.color Theme.neutral500, Ui.centerX ]
            (Ui.text (T.notFoundMessage i18n))
        ]
