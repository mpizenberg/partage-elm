module Page.NewGroup exposing (view)

import UI.Theme as Theme
import Ui
import Ui.Font


view : Ui.Element msg
view =
    Ui.column [ Ui.spacing Theme.spacing.md, Ui.width Ui.fill ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.xxl, Ui.Font.bold ] (Ui.text "Create a Group")
        , Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ]
            (Ui.text "Group creation form will be available in Phase 5.")
        ]
