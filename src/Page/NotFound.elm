module Page.NotFound exposing (view)

import UI.Theme as Theme
import Ui
import Ui.Font


view : Ui.Element msg
view =
    Ui.column [ Ui.spacing Theme.spacing.md, Ui.width Ui.fill, Ui.paddingXY 0 Theme.spacing.xl ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.hero, Ui.Font.bold, Ui.centerX ] (Ui.text "404")
        , Ui.el [ Ui.Font.size Theme.fontSize.md, Ui.Font.color Theme.neutral500, Ui.centerX ]
            (Ui.text "The page you are looking for does not exist.")
        ]
