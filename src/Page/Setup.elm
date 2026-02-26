module Page.Setup exposing (view)

import UI.Theme as Theme
import Ui
import Ui.Font


view : Ui.Element msg
view =
    Ui.column [ Ui.spacing Theme.spacing.lg, Ui.width Ui.fill, Ui.paddingXY 0 Theme.spacing.xl ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.hero, Ui.Font.bold, Ui.centerX ] (Ui.text "Welcome to Partage")
        , Ui.el [ Ui.Font.size Theme.fontSize.md, Ui.Font.color Theme.neutral700, Ui.centerX, Ui.Font.center ]
            (Ui.text "Your privacy-first, encrypted bill splitting app.")
        , Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500, Ui.centerX, Ui.Font.center ]
            (Ui.text "Identity generation will be available in Phase 3.")
        ]
