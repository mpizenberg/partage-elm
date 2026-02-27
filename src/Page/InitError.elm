module Page.InitError exposing (view)

import UI.Theme as Theme
import Ui
import Ui.Font


view : String -> Ui.Element msg
view errorMsg =
    Ui.column [ Ui.spacing Theme.spacing.md, Ui.centerX, Ui.paddingXY 0 Theme.spacing.xl ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.xl, Ui.Font.bold, Ui.Font.color Theme.danger ]
            (Ui.text "Error")
        , Ui.el [ Ui.Font.size Theme.fontSize.md, Ui.Font.color Theme.neutral700 ]
            (Ui.text errorMsg)
        ]
