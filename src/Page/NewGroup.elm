module Page.NewGroup exposing (view)

import Translations as T exposing (I18n)
import UI.Theme as Theme
import Ui
import Ui.Font


view : I18n -> Ui.Element msg
view i18n =
    Ui.column [ Ui.spacing Theme.spacing.md, Ui.width Ui.fill ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.xl, Ui.Font.bold ] (Ui.text (T.newGroupTitle i18n))
        , Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ]
            (Ui.text (T.newGroupNote i18n))
        ]
