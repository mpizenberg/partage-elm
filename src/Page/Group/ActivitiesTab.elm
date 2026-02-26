module Page.Group.ActivitiesTab exposing (view)

{-| Activities tab - placeholder for Phase 2.
-}

import Translations as T exposing (I18n)
import UI.Theme as Theme
import Ui
import Ui.Font


view : I18n -> Ui.Element msg
view i18n =
    Ui.column [ Ui.spacing Theme.spacing.md, Ui.width Ui.fill, Ui.paddingXY 0 Theme.spacing.md ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.lg, Ui.Font.bold ] (Ui.text (T.activitiesTabTitle i18n))
        , Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ]
            (Ui.text (T.activitiesComingSoon i18n))
        ]
