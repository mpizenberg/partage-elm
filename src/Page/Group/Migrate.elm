module Page.Group.Migrate exposing (view)

{-| The migration confirmation screen (spec §11.7). It explains what migrating a
compromised group does and does not do, lets the migrator exclude injected
identities — wholly, or only what they authored after a server-order boundary —
previews the resulting group, then confirms. The minting and re-homing happen in
Page.Group on confirm.
-}

import Dict exposing (Dict)
import Domain.Currency exposing (Currency)
import Domain.Member as Member
import Domain.MigrationCuration exposing (Bound(..), Identity, Preview)
import Domain.SuspicionAudit exposing (Finding, Kind(..))
import Format
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
        , selection : Dict Member.Id Bound
        , findings : List Finding
        , resolveName : Member.Id -> String
        , preview : Maybe Preview
        , onToggle : Member.Id -> msg
        , onSetBound : Member.Id -> Bound -> msg
        , onDismissFinding : Finding -> msg
        , onExcludeFinding : Finding -> msg
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
        , findingsCard i18n config
        , UI.Components.card [ Ui.padding Theme.spacing.lg ]
            [ Ui.column [ Ui.spacing Theme.spacing.md, Ui.width Ui.fill ]
                (UI.Components.sectionLabel (T.migrateReviewTitle i18n)
                    :: body (T.migrateReviewIntro i18n)
                    :: List.map (identityRow i18n config) config.identities
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


findingsCard :
    I18n
    -> { c | findings : List Finding, resolveName : Member.Id -> String, onDismissFinding : Finding -> msg, onExcludeFinding : Finding -> msg }
    -> Ui.Element msg
findingsCard i18n config =
    if List.isEmpty config.findings then
        Ui.none

    else
        UI.Components.card [ Ui.padding Theme.spacing.lg ]
            [ Ui.column [ Ui.spacing Theme.spacing.md, Ui.width Ui.fill ]
                (UI.Components.sectionLabel (T.migrateSuspicionTitle i18n)
                    :: List.map (findingRow i18n config) config.findings
                )
            ]


findingRow :
    I18n
    -> { c | resolveName : Member.Id -> String, onDismissFinding : Finding -> msg, onExcludeFinding : Finding -> msg }
    -> Finding
    -> Ui.Element msg
findingRow i18n config finding =
    Ui.column [ Ui.width Ui.fill, Ui.spacing Theme.spacing.sm ]
        [ body (findingText i18n config.resolveName finding)
        , Ui.row [ Ui.spacing Theme.spacing.sm ]
            [ UI.Components.btnOutline []
                { label = T.migrateSuspicionExclude i18n, icon = Nothing, onPress = config.onExcludeFinding finding }
            , UI.Components.btnOutline []
                { label = T.migrateSuspicionDismiss i18n, icon = Nothing, onPress = config.onDismissFinding finding }
            ]
        ]


findingText : I18n -> (Member.Id -> String) -> Finding -> String
findingText i18n resolveName finding =
    case finding.kind of
        ForeignPaymentEdit { target } ->
            T.migrateSuspicionForeignPayment { culprit = finding.culpritLabel, target = resolveName target } i18n

        GraftedDeviceTamper _ ->
            T.migrateSuspicionGraftedDevice finding.culpritLabel i18n


identityRow :
    I18n
    -> { c | onToggle : Member.Id -> msg, onSetBound : Member.Id -> Bound -> msg, selection : Dict Member.Id Bound }
    -> Identity
    -> Ui.Element msg
identityRow i18n config identity =
    let
        bound : Maybe Bound
        bound =
            Dict.get identity.id config.selection

        mainRow : Ui.Element msg
        mainRow =
            Ui.row [ Ui.width Ui.fill, Ui.spacing Theme.spacing.md, Ui.contentCenterY ]
                [ if identity.excludable then
                    Ui.row [ Ui.spacing Theme.spacing.sm, Ui.contentCenterY ]
                        [ UI.Components.toggle { isOn = bound == Nothing, onPress = config.onToggle identity.id }
                        , Ui.el [ Ui.Font.size Theme.font.xs, Ui.Font.color Theme.base.textSubtle ] (Ui.text (T.migrateToggleKeep i18n))
                        ]

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
    in
    case bound of
        Just current ->
            if List.isEmpty identity.boundaries then
                mainRow

            else
                Ui.column [ Ui.width Ui.fill, Ui.spacing Theme.spacing.sm ]
                    [ mainRow, boundChips i18n config.onSetBound identity current ]

        Nothing ->
            mainRow


boundChips : I18n -> (Member.Id -> Bound -> msg) -> Identity -> Bound -> Ui.Element msg
boundChips i18n onSetBound identity current =
    Ui.row [ Ui.wrap, Ui.spacing Theme.spacing.xs, Ui.paddingWith { top = 0, bottom = 0, left = 52, right = 0 } ]
        (UI.Components.chip
            { label = T.migrateBoundAll i18n
            , selected = current == All
            , onPress = onSetBound identity.id All
            }
            :: List.map
                (\b ->
                    UI.Components.chip
                        { label = T.migrateBoundKeep { kept = String.fromInt b.kept, dropped = String.fromInt (identity.eventCount - b.kept) } i18n
                        , selected = current == After b.seq
                        , onPress = onSetBound identity.id (After b.seq)
                        }
                )
                identity.boundaries
        )


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
