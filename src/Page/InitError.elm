module Page.InitError exposing (view)

import UI.Components
import UI.Theme as Theme
import Ui
import Ui.Font


{-| Render an initialization error page with the given error message.
-}
view : String -> Ui.Element msg
view errorMsg =
    Ui.column [ Ui.spacing Theme.spacing.lg, Ui.centerX, Ui.paddingXY 0 Theme.spacing.xxl ]
        [ Ui.el
            [ Ui.Font.size Theme.font.xxl
            , Ui.Font.weight Theme.fontWeight.bold
            , Ui.Font.color Theme.danger.text
            , Ui.centerX
            ]
            (Ui.text "Error")
        , UI.Components.card [ Ui.padding Theme.spacing.lg ]
            [ Ui.el
                [ Ui.Font.size Theme.font.md
                , Ui.Font.color Theme.base.text
                ]
                (Ui.text errorMsg)
            ]
        ]
