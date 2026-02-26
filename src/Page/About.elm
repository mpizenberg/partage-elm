module Page.About exposing (view)

import UI.Theme as Theme
import Ui
import Ui.Font


view : Ui.Element msg
view =
    Ui.column [ Ui.spacing Theme.spacing.lg, Ui.width Ui.fill, Ui.paddingXY 0 Theme.spacing.md ]
        [ Ui.el [ Ui.Font.size 22, Ui.Font.bold ] (Ui.text "About Partage")
        , Ui.el [ Ui.Font.size 15, Ui.Font.color Theme.neutral700 ]
            (Ui.text "A fully encrypted, local-first bill-splitting application for trusted groups.")
        , Ui.el [ Ui.Font.size 15, Ui.Font.color Theme.neutral700 ]
            (Ui.text "Your data never leaves your device unencrypted.")
        ]
