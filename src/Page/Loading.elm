module Page.Loading exposing (view)

import Translations as T exposing (I18n)
import UI.Theme as Theme
import Ui
import Ui.Font


{-| Render a centered loading indicator.
-}
view : I18n -> Ui.Element msg
view i18n =
    Ui.el
        [ Ui.width Ui.fill, Ui.height Ui.fill ]
        (Ui.el
            [ Ui.centerX
            , Ui.centerY
            , Ui.Font.size Theme.font.lg
            , Ui.Font.color Theme.base.textSubtle
            ]
            (Ui.text (T.loadingApp i18n))
        )
