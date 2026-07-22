module Page.Group.Migrate exposing (view)

{-| The migration confirmation screen (spec §11.7). It explains what migrating a
compromised group does and does not do, lets the migrator exclude injected
identities — wholly, or only what they authored after a server-order boundary —
previews the resulting group, then confirms. The minting and re-homing happen in
Page.Group on confirm.
-}

import Dict exposing (Dict)
import Domain.Currency exposing (Currency)
import Domain.Date as Date
import Domain.Member as Member
import Domain.MigrationCuration exposing (AnchorReason(..), BalanceRow, Bound(..), CutAnchor, Identity, Preview)
import Domain.SuspicionAudit exposing (Finding, Kind(..))
import Format
import Set exposing (Set)
import Time
import Translations as T exposing (I18n)
import UI.Components
import UI.Theme as Theme
import Ui
import Ui.Font
import Ui.Input


view :
    I18n
    -> Currency
    ->
        { identities : List Identity
        , selection : Dict Member.Id Bound
        , findings : List Finding
        , anchors : Member.Id -> List CutAnchor
        , expandedManual : Set Member.Id
        , resolveName : Member.Id -> String
        , preview : Maybe Preview
        , zone : Time.Zone
        , onToggle : Member.Id -> msg
        , onSetBound : Member.Id -> Bound -> msg
        , onToggleManual : Member.Id -> msg
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
                    :: List.map (identityCard i18n config) config.identities
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


identityCard :
    I18n
    ->
        { c
            | zone : Time.Zone
            , onToggle : Member.Id -> msg
            , onSetBound : Member.Id -> Bound -> msg
            , onToggleManual : Member.Id -> msg
            , selection : Dict Member.Id Bound
            , anchors : Member.Id -> List CutAnchor
            , expandedManual : Set Member.Id
            , resolveName : Member.Id -> String
        }
    -> Identity
    -> Ui.Element msg
identityCard i18n config identity =
    let
        bound : Maybe Bound
        bound =
            Dict.get identity.id config.selection

        cuttable : Bool
        cuttable =
            not (List.isEmpty identity.boundaries)

        interactive : Bool
        interactive =
            identity.removable || cuttable

        control : Ui.Element msg
        control =
            if identity.removable then
                keepToggle i18n (T.migrateActionRemove i18n) Theme.danger.solid config.onToggle identity.id (bound == Nothing)

            else if cuttable then
                keepToggle i18n (T.migrateActionCut i18n) Theme.warning.solid config.onToggle identity.id (bound == Nothing)

            else if identity.isSelf then
                pill Theme.success.bgSubtle Theme.success.text (T.migrateRoleYou i18n)

            else
                pill Theme.base.accent Theme.base.textSubtle (T.migrateKept i18n)

        metaLine : String
        metaLine =
            String.join " · "
                (case identity.linkedAt of
                    Just ts ->
                        [ T.memberDeviceLinkedDate (Date.toString (Date.posixToDate config.zone ts)) i18n
                        , eventCountText i18n identity
                        ]

                    Nothing ->
                        [ eventCountText i18n identity ]
                )

        refine : List (Ui.Element msg)
        refine =
            case bound of
                Just current ->
                    if cuttable then
                        [ curationBox i18n config identity current ]

                    else
                        []

                Nothing ->
                    []

        nameRow : Ui.Element msg
        nameRow =
            Ui.row [ Ui.spacing Theme.spacing.sm, Ui.contentCenterY, Ui.width Ui.shrink ]
                (Ui.el [ Ui.Font.size Theme.font.md, Ui.Font.color Theme.base.text ] (Ui.text identity.label)
                    :: (if identity.isDevice then
                            [ pill Theme.warning.bgSubtle Theme.warning.text (T.migrateDeviceTag i18n) ]

                        else
                            []
                       )
                )

        header : Ui.Element msg
        header =
            Ui.row [ Ui.width Ui.fill, Ui.spacing Theme.spacing.sm, Ui.contentCenterY ]
                [ Ui.column [ Ui.width Ui.fill, Ui.spacing Theme.spacing.xs ]
                    [ nameRow
                    , Ui.el [ Ui.Font.size Theme.font.xs, Ui.Font.color Theme.base.textSubtle ] (Ui.text (Member.shortId identity.id))
                    ]
                , control
                ]

        meta : Ui.Element msg
        meta =
            Ui.el [ Ui.Font.size Theme.font.xs, Ui.Font.color Theme.base.textSubtle ] (Ui.text metaLine)
    in
    Ui.column
        ([ Ui.width Ui.fill
         , Ui.spacing Theme.spacing.sm
         , Ui.padding Theme.spacing.md
         , Ui.rounded Theme.radius.md
         ]
            ++ (if interactive then
                    [ Ui.border Theme.border, Ui.borderColor Theme.base.accent ]

                else
                    [ Ui.background Theme.base.tint ]
               )
        )
        ([ header, meta ] ++ refine)


eventCountText : I18n -> Identity -> String
eventCountText i18n identity =
    String.fromInt identity.eventCount ++ " " ++ T.migrateEventsUnit i18n


{-| Two-segment Keep / action control (Remove for a removable identity, Cut for a
creator/self that can only be bound-cut). The active segment is inert; only the
other side carries the toggle, so a tap always flips the decision.
-}
keepToggle : I18n -> String -> Ui.Color -> (Member.Id -> msg) -> Member.Id -> Bool -> Ui.Element msg
keepToggle i18n actionLabel actionBg onToggle memberId keeping =
    Ui.row
        [ Ui.width Ui.shrink
        , Ui.alignRight
        , Ui.border Theme.border
        , Ui.borderColor Theme.base.accent
        , Ui.rounded Theme.radius.xxl
        , Ui.clip
        ]
        [ segment (T.migrateToggleKeep i18n) keeping Theme.primary.solid (onToggle memberId)
        , segment actionLabel (not keeping) actionBg (onToggle memberId)
        ]


segment : String -> Bool -> Ui.Color -> msg -> Ui.Element msg
segment label active activeBg onPress =
    Ui.el
        ([ Ui.paddingXY Theme.spacing.md Theme.spacing.sm
         , Ui.Font.size Theme.font.sm
         , Ui.Font.weight Theme.fontWeight.medium
         ]
            ++ (if active then
                    [ Ui.background activeBg, Ui.Font.color Theme.base.solidText ]

                else
                    [ Ui.Input.button onPress, Ui.pointer, Ui.Font.color Theme.base.textSubtle ]
               )
        )
        (Ui.text label)


{-| Refinement offered once an identity with multi-batch history is set to
Remove. Leads with the suspicious syncs as one-tap "cut before here" choices,
keeps a plain "remove everything", and hides the full server-order timeline
behind a collapsible for an arbitrary cut. Splits follow the server's arrival
order, which a tampered event can't back-date.
-}
curationBox :
    I18n
    -> { c | onSetBound : Member.Id -> Bound -> msg, onToggleManual : Member.Id -> msg, anchors : Member.Id -> List CutAnchor, expandedManual : Set Member.Id, resolveName : Member.Id -> String }
    -> Identity
    -> Bound
    -> Ui.Element msg
curationBox i18n config identity current =
    let
        anchors : List CutAnchor
        anchors =
            config.anchors identity.id

        expanded : Bool
        expanded =
            Set.member identity.id config.expandedManual

        keepDrop : Int -> Int -> String
        keepDrop kept dropped =
            T.migrateCurateKeep { kept = String.fromInt kept, dropped = String.fromInt dropped } i18n

        anchorOptions : List (Ui.Element msg)
        anchorOptions =
            List.map
                (\anchor ->
                    cutOption
                        (anchorTitle i18n config.resolveName anchor)
                        (Just (keepDrop anchor.kept anchor.dropped))
                        (current == anchor.bound)
                        (config.onSetBound identity.id anchor.bound)
                )
                anchors

        removeAllOption : List (Ui.Element msg)
        removeAllOption =
            if identity.removable then
                [ cutOption
                    (T.migrateCurateRemoveAll (String.fromInt identity.eventCount) i18n)
                    Nothing
                    (current == All)
                    (config.onSetBound identity.id All)
                ]

            else
                []

        manualToggle : Ui.Element msg
        manualToggle =
            Ui.row
                [ Ui.Input.button (config.onToggleManual identity.id)
                , Ui.pointer
                , Ui.spacing Theme.spacing.xs
                , Ui.contentCenterY
                , Ui.paddingXY Theme.spacing.sm Theme.spacing.xs
                ]
                [ Ui.el [ Ui.Font.size Theme.font.xs, Ui.Font.color Theme.warning.text ]
                    (Ui.text
                        (if expanded then
                            "▾"

                         else
                            "▸"
                        )
                    )
                , Ui.el [ Ui.Font.size Theme.font.xs, Ui.Font.weight Theme.fontWeight.medium, Ui.Font.color Theme.warning.text ]
                    (Ui.text (T.migrateCutManual i18n))
                ]

        manualOptions : List (Ui.Element msg)
        manualOptions =
            if expanded then
                List.map
                    (\b ->
                        cutOption
                            (keepDrop b.kept (identity.eventCount - b.kept))
                            Nothing
                            (current == After b.seq)
                            (config.onSetBound identity.id (After b.seq))
                    )
                    identity.boundaries

            else
                []
    in
    Ui.column
        [ Ui.width Ui.fill
        , Ui.spacing Theme.spacing.xs
        , Ui.padding Theme.spacing.sm
        , Ui.rounded Theme.radius.sm
        , Ui.background Theme.warning.bgSubtle
        , Ui.border Theme.border
        , Ui.borderColor Theme.warning.tintStrong
        ]
        (Ui.el [ Ui.Font.size Theme.font.xs, Ui.Font.weight Theme.fontWeight.semibold, Ui.Font.color Theme.warning.text ]
            (Ui.text (T.migrateCurateHeading i18n))
            :: anchorOptions
            ++ removeAllOption
            ++ [ manualToggle ]
            ++ manualOptions
            ++ [ Ui.el [ Ui.width Ui.fill, Ui.Font.size Theme.font.xs, Ui.Font.color Theme.warning.textSubtle ]
                    (Ui.text (T.migrateCurateOrderNote i18n))
               ]
        )


anchorTitle : I18n -> (Member.Id -> String) -> CutAnchor -> String
anchorTitle i18n resolveName anchor =
    case anchor.reason of
        FindingReason finding ->
            findingText i18n resolveName finding

        FloodReason count ->
            T.migrateAnchorFlood (String.fromInt count) i18n


cutOption : String -> Maybe String -> Bool -> msg -> Ui.Element msg
cutOption title maybeSubtitle selected onPress =
    Ui.row
        ([ Ui.Input.button onPress
         , Ui.pointer
         , Ui.spacing Theme.spacing.sm
         , Ui.contentCenterY
         , Ui.width Ui.fill
         , Ui.paddingXY Theme.spacing.sm Theme.spacing.xs
         , Ui.rounded Theme.radius.sm
         ]
            ++ (if selected then
                    [ Ui.background (Ui.rgb 255 255 255) ]

                else
                    []
               )
        )
        [ radioDot selected
        , Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
            (Ui.el [ Ui.Font.size Theme.font.sm, Ui.Font.color Theme.base.text ] (Ui.text title)
                :: (case maybeSubtitle of
                        Just subtitle ->
                            [ Ui.el [ Ui.Font.size Theme.font.xs, Ui.Font.color Theme.base.textSubtle ] (Ui.text subtitle) ]

                        Nothing ->
                            []
                   )
            )
        ]


radioDot : Bool -> Ui.Element msg
radioDot selected =
    Ui.el
        [ Ui.width (Ui.px 16)
        , Ui.height (Ui.px 16)
        , Ui.rounded Theme.radius.xxxl
        , Ui.border 2
        , Ui.borderColor Theme.warning.accent
        , Ui.contentCenterX
        , Ui.contentCenterY
        ]
        (if selected then
            Ui.el
                [ Ui.width (Ui.px 8)
                , Ui.height (Ui.px 8)
                , Ui.rounded Theme.radius.xxxl
                , Ui.background Theme.warning.accent
                ]
                Ui.none

         else
            Ui.none
        )


pill : Ui.Color -> Ui.Color -> String -> Ui.Element msg
pill bg fg text =
    Ui.el
        [ Ui.Font.size Theme.font.xs
        , Ui.Font.weight Theme.fontWeight.semibold
        , Ui.Font.color fg
        , Ui.background bg
        , Ui.paddingXY Theme.spacing.sm Theme.spacing.xs
        , Ui.rounded Theme.radius.xxxl
        , Ui.width Ui.shrink
        ]
        (Ui.text text)


previewBlock : I18n -> Currency -> Preview -> Ui.Element msg
previewBlock i18n currency result =
    UI.Components.card [ Ui.padding Theme.spacing.md ]
        [ Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
            ([ statRow (T.migrateStatCarried i18n) (String.fromInt result.carried)
             , statRow (T.migrateStatDropped i18n) (String.fromInt result.dropped)
             , statRow (T.migrateStatMembers i18n) (String.fromInt result.members)
             , statRow (T.migrateStatEntries i18n) (String.fromInt result.entries)
             , UI.Components.sectionLabel (T.migrateStatBalances i18n)
             ]
                ++ List.map (balanceRow i18n currency) result.balances
            )
        ]


statRow : String -> String -> Ui.Element msg
statRow label value =
    Ui.row [ Ui.width Ui.fill, Ui.spacing Theme.spacing.md ]
        [ Ui.el [ Ui.Font.size Theme.font.sm, Ui.Font.color Theme.base.textSubtle, Ui.width Ui.fill ] (Ui.text label)
        , Ui.el [ Ui.alignRight, Ui.Font.size Theme.font.sm, Ui.Font.color Theme.base.text ] (Ui.text value)
        ]


balanceRow : I18n -> Currency -> BalanceRow -> Ui.Element msg
balanceRow i18n currency row =
    let
        lang : T.Language
        lang =
            T.currentLanguage i18n

        label : String
        label =
            if row.isSelf then
                row.label ++ " (" ++ T.migrateRoleYou i18n ++ ")"

            else
                row.label
    in
    Ui.row [ Ui.width Ui.fill, Ui.spacing Theme.spacing.sm, Ui.contentCenterY ]
        [ Ui.el [ Ui.Font.size Theme.font.sm, Ui.Font.color Theme.base.text, Ui.width Ui.fill ] (Ui.text label)
        , Ui.el [ Ui.Font.size Theme.font.sm, Ui.Font.color (amountColor row.balanceCents) ]
            (Ui.text (Format.formatCentsSigned lang row.balanceCents currency))
        , if row.deltaCents == 0 then
            Ui.none

          else
            Ui.el [ Ui.Font.size Theme.font.xs, Ui.Font.color (amountColor row.deltaCents) ]
                (Ui.text ("Δ " ++ Format.formatCentsSigned lang row.deltaCents currency))
        ]


amountColor : Int -> Ui.Color
amountColor cents =
    if cents > 0 then
        Theme.success.text

    else if cents < 0 then
        Theme.danger.text

    else
        Theme.base.textSubtle
