module Page.Group.Migrate exposing (view)

{-| The migration confirmation screen (spec §11.7). Static: it explains what
migrating a compromised group does and does not do, then confirms. The minting
and re-homing happen in Page.Group on confirm.
-}

import Translations as T exposing (I18n)
import UI.Components
import UI.Theme as Theme
import Ui
import Ui.Font


view : I18n -> { onConfirm : msg, onCancel : msg } -> Ui.Element msg
view i18n { onConfirm, onCancel } =
    Ui.column [ Ui.spacing Theme.spacing.lg, Ui.width Ui.fill, Ui.paddingXY 0 Theme.spacing.md ]
        [ UI.Components.card [ Ui.padding Theme.spacing.lg ]
            [ Ui.column [ Ui.spacing Theme.spacing.md, Ui.width Ui.fill ]
                (List.map body
                    [ T.migrateIntro i18n
                    , T.migrateCarries i18n
                    , T.migrateReinvite i18n
                    , T.migrateReadonly i18n
                    , T.migrateExposure i18n
                    ]
                )
            ]
        , UI.Components.btnPrimary [ Ui.width Ui.fill ] { label = T.migrateConfirm i18n, onPress = onConfirm }
        , UI.Components.btnOutline [ Ui.width Ui.fill ] { label = T.migrateCancel i18n, icon = Nothing, onPress = onCancel }
        ]


body : String -> Ui.Element msg
body text =
    Ui.el [ Ui.Font.size Theme.font.sm, Ui.Font.color Theme.base.text ] (Ui.text text)
