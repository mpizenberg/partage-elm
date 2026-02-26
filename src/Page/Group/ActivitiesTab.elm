module Page.Group.ActivitiesTab exposing (view)

{-| Activities tab - placeholder for Phase 2.
-}

import UI.Theme as Theme
import Ui
import Ui.Font


view : Ui.Element msg
view =
    Ui.column [ Ui.spacing Theme.spacing.md, Ui.width Ui.fill, Ui.paddingXY 0 Theme.spacing.md ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.lg, Ui.Font.bold ] (Ui.text "Activities")
        , Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ]
            (Ui.text "Activity feed coming soon.")
        ]
