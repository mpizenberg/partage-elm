module Page.Group.Migrate exposing (view)

{-| The migration confirmation screen (spec §11.7). It explains what migrating a
compromised group does and does not do, lets the migrator exclude injected
identities, previews the resulting group, then confirms. The minting and
re-homing happen in Page.Group on confirm.
-}

import Domain.Currency exposing (Currency)
import Domain.Member as Member
import Domain.MigrationCuration exposing (Identity, Preview)
import Format
import Set exposing (Set)
import Translations as T exposing (I18n)
import UI.Components
import UI.Theme as Theme
import Ui
import Ui.Font


view :
    I18n
    -> Currency
    ->
        { identities : List Identity
        , excluded : Set Member.Id
        , preview : Maybe Preview
        , onToggle : Member.Id -> msg
        , onPreview : msg
        , onConfirm : msg
        , onCancel : msg
        }
    -> Ui.Element msg
view i18n currency config =
    Ui.column [ Ui.spacing Theme.spacing.lg, Ui.width Ui.fill, Ui.paddingXY 0 Theme.spacing.md ]
        [ UI.Components.card [ Ui.padding Theme.spacing.lg ]
            [ Ui.column [ Ui.spacing Theme.spacing.md, Ui.width Ui.fill ]
                (List.map body
                    [ T.migrateIntro i18n
                    , T.migrateCarries i18n
                    , T.migrateCoordinate i18n
                    , T.migrateReinvite i18n
                    , T.migrateReadonly i18n
                    , T.migrateExposure i18n
                    ]
                )
            ]
        , UI.Components.card [ Ui.padding Theme.spacing.lg ]
            [ Ui.column [ Ui.spacing Theme.spacing.md, Ui.width Ui.fill ]
                (UI.Components.sectionLabel (T.migrateReviewTitle i18n)
                    :: body (T.migrateReviewIntro i18n)
                    :: List.map (identityRow i18n config.onToggle config.excluded) config.identities
                )
            ]
        , Ui.column [ Ui.spacing Theme.spacing.md, Ui.width Ui.fill ]
            [ UI.Components.btnOutline [ Ui.width Ui.fill ]
                { label = T.migratePreview i18n, icon = Nothing, onPress = config.onPreview }
            , case config.preview of
                Just result ->
                    previewBlock i18n currency result

                Nothing ->
                    Ui.none
            ]
        , UI.Components.btnPrimary [ Ui.width Ui.fill ] { label = T.migrateConfirm i18n, onPress = config.onConfirm }
        , UI.Components.btnOutline [ Ui.width Ui.fill ] { label = T.migrateCancel i18n, icon = Nothing, onPress = config.onCancel }
        ]


body : String -> Ui.Element msg
body text =
    Ui.el [ Ui.Font.size Theme.font.sm, Ui.Font.color Theme.base.text ] (Ui.text text)


identityRow : I18n -> (Member.Id -> msg) -> Set Member.Id -> Identity -> Ui.Element msg
identityRow i18n onToggle excluded identity =
    Ui.row [ Ui.width Ui.fill, Ui.spacing Theme.spacing.md, Ui.contentCenterY ]
        [ if identity.excludable then
            UI.Components.toggle { isOn = Set.member identity.id excluded, onPress = onToggle identity.id }

          else
            Ui.el [ Ui.width (Ui.px 42) ] Ui.none
        , Ui.row [ Ui.width Ui.fill, Ui.spacing Theme.spacing.sm, Ui.contentCenterY ]
            (Ui.el [ Ui.Font.size Theme.font.sm, Ui.Font.color Theme.base.text ] (Ui.text identity.label)
                :: List.filterMap (\( shown, element ) -> ifJust shown element)
                    [ ( identity.isDevice, badge Theme.warning.bgSubtle Theme.warning.text (T.migrateDeviceTag i18n) )
                    , ( not identity.excludable, badge Theme.base.tint Theme.base.textSubtle (T.migrateKept i18n) )
                    ]
            )
        , Ui.el [ Ui.alignRight, Ui.Font.size Theme.font.sm, Ui.Font.color Theme.base.textSubtle ]
            (Ui.text (String.fromInt identity.eventCount ++ " " ++ T.migrateEventsUnit i18n))
        ]


ifJust : Bool -> a -> Maybe a
ifJust shown value =
    if shown then
        Just value

    else
        Nothing


badge : Ui.Color -> Ui.Color -> String -> Ui.Element msg
badge bg fg text =
    Ui.el
        [ Ui.Font.size Theme.font.xs
        , Ui.Font.color fg
        , Ui.background bg
        , Ui.paddingXY Theme.spacing.sm Theme.spacing.xs
        , Ui.rounded 999
        ]
        (Ui.text text)


previewBlock : I18n -> Currency -> Preview -> Ui.Element msg
previewBlock i18n currency result =
    UI.Components.card [ Ui.padding Theme.spacing.md ]
        [ Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
            [ statRow (T.migrateStatCarried i18n) (String.fromInt result.carried)
            , statRow (T.migrateStatDropped i18n) (String.fromInt result.dropped)
            , statRow (T.migrateStatMembers i18n) (String.fromInt result.members)
            , statRow (T.migrateStatEntries i18n) (String.fromInt result.entries)
            , statRow (T.migrateStatBalance i18n) (Format.formatCentsSigned (T.currentLanguage i18n) result.myBalanceCents currency)
            ]
        ]


statRow : String -> String -> Ui.Element msg
statRow label value =
    Ui.row [ Ui.width Ui.fill, Ui.spacing Theme.spacing.md ]
        [ Ui.el [ Ui.Font.size Theme.font.sm, Ui.Font.color Theme.base.textSubtle, Ui.width Ui.fill ] (Ui.text label)
        , Ui.el [ Ui.alignRight, Ui.Font.size Theme.font.sm, Ui.Font.color Theme.base.text ] (Ui.text value)
        ]
