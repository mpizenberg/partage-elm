module Page.NotFound exposing (view)

import Translations as T exposing (I18n)
import UI.Theme as Theme
import Ui
import Ui.Font


{-| Render the 404 not found page.
-}
view : I18n -> Ui.Element msg
view i18n =
    Ui.column [ Ui.spacing Theme.spacing.md, Ui.width Ui.fill, Ui.paddingXY 0 Theme.spacing.xxl ]
        [ Ui.el
            [ Ui.Font.size Theme.font.xxxl
            , Ui.Font.weight Theme.fontWeight.bold
            , Ui.Font.letterSpacing Theme.letterSpacing.tight
            , Ui.Font.color Theme.base.textSubtle
            , Ui.centerX
            ]
            (Ui.text (T.notFoundCode i18n))
        , Ui.el
            [ Ui.Font.size Theme.font.md
            , Ui.Font.color Theme.base.textSubtle
            , Ui.centerX
            ]
            (Ui.text (T.notFoundMessage i18n))
        ]
