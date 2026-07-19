module Page.Group.MergeMember exposing
    ( Model
    , Msg
    , Output(..)
    , init
    , update
    , view
    )

{-| Page for merging one group member into another. Step 1 picks the target
member; step 2 previews the effects of the merge and requires type-to-confirm
before committing the events.
-}

import Dict
import Domain.Entry as Entry
import Domain.GroupState exposing (GroupState)
import Domain.Member as Member
import Domain.MemberMerge as Merge
import FeatherIcons
import Translations as T exposing (I18n)
import UI.Components
import UI.Theme as Theme
import Ui
import Ui.Font
import Ui.Input


{-| Page-level model: holds the source (always known from URL), the optional
target, and the confirmation input string for step 2.
-}
type Model
    = Model ModelData


type alias ModelData =
    { sourceRootId : Member.Id
    , targetRootId : Maybe Member.Id
    , confirmInput : String
    , showEntriesDetails : Bool
    , showSelfTransfersDetails : Bool
    , showPrefsDetails : Bool
    }


{-| Outputs produced by user interaction. Navigation outputs let the parent
update the URL; CommitMerge submits all the planned events at once.

The `Member.Id` arguments are root ids in every variant.

-}
type Output
    = NavigateToStep1 Member.Id
    | NavigateToStep2 Member.Id Member.Id
    | CommitMerge { sourceRootId : Member.Id, targetRootId : Member.Id, plan : Merge.Plan }


type Msg
    = PickTarget Member.Id
    | Swap
    | BackToPick
    | InputConfirm String
    | ToggleEntriesDetails
    | ToggleSelfTransfersDetails
    | TogglePrefsDetails
    | Submit


{-| Initialize from the URL parameters. Resets the confirmation input.
Both ids are member root ids.
-}
init : Member.Id -> Maybe Member.Id -> Model
init sourceRootId targetRootId =
    Model
        { sourceRootId = sourceRootId
        , targetRootId = targetRootId
        , confirmInput = ""
        , showEntriesDetails = False
        , showSelfTransfersDetails = False
        , showPrefsDetails = False
        }


{-| Handle a message. The submit branch needs the live GroupState to compute
the merge plan, so the caller passes it in.
-}
update : GroupState -> Msg -> Model -> ( Model, Maybe Output )
update state msg (Model data) =
    case msg of
        PickTarget targetId ->
            ( Model data, Just (NavigateToStep2 data.sourceRootId targetId) )

        Swap ->
            case data.targetRootId of
                Just targetId ->
                    ( Model data, Just (NavigateToStep2 targetId data.sourceRootId) )

                Nothing ->
                    ( Model data, Nothing )

        BackToPick ->
            ( Model data, Just (NavigateToStep1 data.sourceRootId) )

        InputConfirm s ->
            ( Model { data | confirmInput = s }, Nothing )

        ToggleEntriesDetails ->
            ( Model { data | showEntriesDetails = not data.showEntriesDetails }, Nothing )

        ToggleSelfTransfersDetails ->
            ( Model { data | showSelfTransfersDetails = not data.showSelfTransfersDetails }, Nothing )

        TogglePrefsDetails ->
            ( Model { data | showPrefsDetails = not data.showPrefsDetails }, Nothing )

        Submit ->
            case data.targetRootId of
                Just targetId ->
                    let
                        sourceMember : Maybe Member.ChainState
                        sourceMember =
                            Dict.get data.sourceRootId state.members

                        expectedConfirm : String
                        expectedConfirm =
                            sourceMember |> Maybe.map .name |> Maybe.withDefault ""
                    in
                    if String.trim data.confirmInput /= expectedConfirm || expectedConfirm == "" then
                        ( Model data, Nothing )

                    else
                        ( Model data
                        , Just
                            (CommitMerge
                                { sourceRootId = data.sourceRootId
                                , targetRootId = targetId
                                , plan = Merge.plan data.sourceRootId targetId state
                                }
                            )
                        )

                Nothing ->
                    ( Model data, Nothing )


{-| Render either step 1 (target picker) or step 2 (preview + confirm),
depending on whether the model has a target set.
-}
view : I18n -> (Msg -> msg) -> GroupState -> Model -> Ui.Element msg
view i18n toMsg state (Model data) =
    case data.targetRootId of
        Nothing ->
            viewStep1 i18n state data |> Ui.map toMsg

        Just targetId ->
            viewStep2 i18n state data targetId |> Ui.map toMsg



-- STEP 1


viewStep1 : I18n -> GroupState -> ModelData -> Ui.Element Msg
viewStep1 i18n state data =
    case Dict.get data.sourceRootId state.members of
        Nothing ->
            memberNotFoundView i18n

        Just sourceMember ->
            let
                activeCandidates : List Member.ChainState
                activeCandidates =
                    Dict.values state.members
                        |> List.filter (\m -> m.rootId /= data.sourceRootId && not m.isRetired)
                        |> List.sortBy (\m -> String.toLower m.name)
            in
            Ui.column [ Ui.spacing Theme.spacing.xl, Ui.width Ui.fill ]
                [ headingSection
                    (T.mergeStep1Title i18n)
                    (T.mergeStep1Subtitle i18n)
                , memberSlot
                    { label = T.mergeRetiringLabel i18n
                    , member = sourceMember
                    , tone = ToneRetiring
                    }
                , Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
                    [ UI.Components.sectionLabel (T.mergeStep1PickerLabel i18n)
                    , if List.isEmpty activeCandidates then
                        Ui.el [ Ui.Font.color Theme.base.textSubtle, Ui.Font.size Theme.font.sm ]
                            (Ui.text (T.mergeNoOtherMember i18n))

                      else
                        Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
                            (List.map (candidateRow i18n) activeCandidates)
                    ]
                ]


candidateRow : I18n -> Member.ChainState -> Ui.Element Msg
candidateRow i18n member =
    let
        isVirtual : Bool
        isVirtual =
            member.currentMember.memberType == Member.Virtual
    in
    UI.Components.card
        [ Ui.Input.button (PickTarget member.rootId)
        , Ui.paddingXY Theme.spacing.lg Theme.spacing.md
        , Ui.pointer
        ]
        [ Ui.row [ Ui.spacing Theme.spacing.md, Ui.contentCenterY, Ui.width Ui.fill ]
            [ UI.Components.avatar UI.Components.AvatarAccent (initialsOf member)
            , Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
                [ Ui.row [ Ui.spacing Theme.spacing.xs, Ui.contentCenterY ]
                    [ Ui.el
                        [ Ui.Font.weight Theme.fontWeight.semibold
                        , Ui.Font.size Theme.font.md
                        ]
                        (Ui.text member.name)
                    , if isVirtual then
                        smallTag (T.memberVirtualLabel i18n) Theme.base.tint Theme.base.textSubtle

                      else
                        Ui.none
                    ]
                ]
            , UI.Components.featherIcon 18 FeatherIcons.chevronRight
            ]
        ]



-- STEP 2


viewStep2 : I18n -> GroupState -> ModelData -> Member.Id -> Ui.Element Msg
viewStep2 i18n state data targetId =
    case ( Dict.get data.sourceRootId state.members, Dict.get targetId state.members ) of
        ( Just sourceMember, Just targetMember ) ->
            let
                planActions : Merge.Plan
                planActions =
                    Merge.plan data.sourceRootId targetId state

                modifyActions : List Merge.Action
                modifyActions =
                    List.filter isModify planActions

                deleteActions : List Merge.Action
                deleteActions =
                    List.filter isDelete planActions

                prefActions : List Merge.Action
                prefActions =
                    List.filter isPref planActions

                totalEvents : Int
                totalEvents =
                    List.length planActions
            in
            Ui.column [ Ui.spacing Theme.spacing.xl, Ui.width Ui.fill ]
                [ headingSection
                    (T.mergeStep2Title i18n)
                    (T.mergeStep2Subtitle i18n)
                , pairView i18n sourceMember targetMember
                , suggestionBanner i18n sourceMember targetMember
                , effectsSection i18n data state sourceMember targetMember modifyActions deleteActions prefActions
                , Ui.el
                    [ Ui.Font.size Theme.font.sm
                    , Ui.Font.color Theme.base.textSubtle
                    ]
                    (Ui.text (T.mergeAuthorshipNote i18n))
                , warningCallout (T.mergeIrreversibleWarning (String.fromInt totalEvents) i18n)
                , confirmSection i18n data sourceMember
                ]

        _ ->
            memberNotFoundView i18n


isModify : Merge.Action -> Bool
isModify action =
    case action of
        Merge.ModifyEntry _ ->
            True

        _ ->
            False


isDelete : Merge.Action -> Bool
isDelete action =
    case action of
        Merge.DeleteSelfTransfer _ ->
            True

        _ ->
            False


isPref : Merge.Action -> Bool
isPref action =
    case action of
        Merge.UpdateSettlementPref _ ->
            True

        _ ->
            False


pairView : I18n -> Member.ChainState -> Member.ChainState -> Ui.Element Msg
pairView i18n source target =
    Ui.column [ Ui.spacing Theme.spacing.md, Ui.width Ui.fill ]
        [ Ui.row [ Ui.spacing Theme.spacing.md, Ui.width Ui.fill, Ui.contentCenterY ]
            [ memberSlot
                { label = T.mergeRetiringLabel i18n
                , member = source
                , tone = ToneRetiring
                }
            , swapButton
            , memberSlot
                { label = T.mergeKeepingLabel i18n
                , member = target
                , tone = ToneKeeping
                }
            ]
        , UI.Components.btnOutline []
            { label = T.mergeBackButton i18n
            , icon = Just (UI.Components.featherIcon 16 FeatherIcons.arrowLeft)
            , onPress = BackToPick
            }
        ]


swapButton : Ui.Element Msg
swapButton =
    UI.Components.iconButton
        [ Ui.background Theme.base.bgSubtle
        , Ui.border Theme.border
        , Ui.borderColor Theme.base.accent
        , Ui.width Ui.shrink
        , Ui.width (Ui.px Theme.sizing.lg)
        ]
        { onPress = Swap
        , size = 18
        , icon = FeatherIcons.repeat
        }


suggestionBanner : I18n -> Member.ChainState -> Member.ChainState -> Ui.Element Msg
suggestionBanner i18n source target =
    let
        sourceIsReal : Bool
        sourceIsReal =
            source.currentMember.memberType == Member.Real

        targetIsReal : Bool
        targetIsReal =
            target.currentMember.memberType == Member.Real
    in
    case ( sourceIsReal, targetIsReal ) of
        ( False, True ) ->
            banner Theme.success
                (UI.Components.featherIcon 18 FeatherIcons.checkCircle)
                (T.mergeBannerRecommended i18n)
                Nothing

        ( True, False ) ->
            banner Theme.warning
                (UI.Components.featherIcon 18 FeatherIcons.alertTriangle)
                (T.mergeBannerSwapHint { source = source.name, target = target.name } i18n)
                (Just
                    { label = T.mergeSwapButton i18n
                    , onPress = Swap
                    }
                )

        ( True, True ) ->
            banner Theme.warning
                (UI.Components.featherIcon 18 FeatherIcons.alertTriangle)
                (T.mergeBannerBothReal source.name i18n)
                Nothing

        ( False, False ) ->
            Ui.none


banner :
    { a
        | bgSubtle : Ui.Color
        , accent : Ui.Color
        , text : Ui.Color
    }
    -> Ui.Element Msg
    -> String
    -> Maybe { label : String, onPress : Msg }
    -> Ui.Element Msg
banner colors icon message maybeAction =
    Ui.row
        [ Ui.spacing Theme.spacing.md
        , Ui.padding Theme.spacing.md
        , Ui.rounded Theme.radius.md
        , Ui.background colors.bgSubtle
        , Ui.border Theme.border
        , Ui.borderColor colors.accent
        , Ui.width Ui.fill
        , Ui.contentCenterY
        ]
        [ Ui.el [ Ui.Font.color colors.accent, Ui.width Ui.shrink ] icon
        , Ui.el
            [ Ui.Font.size Theme.font.sm
            , Ui.Font.color colors.text
            , Ui.width Ui.fill
            ]
            (Ui.text message)
        , case maybeAction of
            Just action ->
                Ui.el
                    [ Ui.Input.button action.onPress
                    , Ui.paddingXY Theme.spacing.md Theme.spacing.sm
                    , Ui.rounded Theme.radius.sm
                    , Ui.background colors.accent
                    , Ui.Font.color Theme.base.bg
                    , Ui.Font.size Theme.font.sm
                    , Ui.Font.weight Theme.fontWeight.semibold
                    , Ui.pointer
                    , Ui.width Ui.shrink
                    ]
                    (Ui.text action.label)

            Nothing ->
                Ui.none
        ]


effectsSection :
    I18n
    -> ModelData
    -> GroupState
    -> Member.ChainState
    -> Member.ChainState
    -> List Merge.Action
    -> List Merge.Action
    -> List Merge.Action
    -> Ui.Element Msg
effectsSection i18n data state sourceMember targetMember modifyActions deleteActions prefActions =
    let
        totalActions : Int
        totalActions =
            List.length modifyActions + List.length deleteActions + List.length prefActions
    in
    Ui.column [ Ui.spacing Theme.spacing.md, Ui.width Ui.fill ]
        [ UI.Components.sectionLabel (T.mergeEffectsTitle i18n)
        , if totalActions == 0 then
            Ui.el
                [ Ui.padding Theme.spacing.md
                , Ui.Font.size Theme.font.sm
                , Ui.Font.color Theme.base.textSubtle
                , Ui.background Theme.base.bgSubtle
                , Ui.rounded Theme.radius.sm
                , Ui.width Ui.fill
                ]
                (Ui.text (T.mergeNothingToRewrite sourceMember.name i18n))

          else
            Ui.none
        , if List.isEmpty modifyActions then
            Ui.none

          else
            collapsible
                { isOpen = data.showEntriesDetails
                , toggle = ToggleEntriesDetails
                , label = T.mergeEntriesRewrittenCount (String.fromInt (List.length modifyActions)) i18n
                , content =
                    Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
                        (List.map (entryActionRow i18n) modifyActions)
                }
        , if List.isEmpty deleteActions then
            Ui.none

          else
            collapsible
                { isOpen = data.showSelfTransfersDetails
                , toggle = ToggleSelfTransfersDetails
                , label = T.mergeSelfTransfersDeletedCount (String.fromInt (List.length deleteActions)) i18n
                , content =
                    Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
                        (List.map (entryActionRow i18n) deleteActions)
                }
        , if List.isEmpty prefActions then
            Ui.none

          else
            collapsible
                { isOpen = data.showPrefsDetails
                , toggle = TogglePrefsDetails
                , label = T.mergePrefsUpdatedCount (String.fromInt (List.length prefActions)) i18n
                , content =
                    Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
                        (List.map (prefActionRow i18n state) prefActions)
                }
        , retireLine i18n sourceMember targetMember
        ]


retireLine : I18n -> Member.ChainState -> Member.ChainState -> Ui.Element Msg
retireLine i18n source target =
    Ui.row
        [ Ui.spacing Theme.spacing.sm
        , Ui.padding Theme.spacing.md
        , Ui.background Theme.base.bgSubtle
        , Ui.rounded Theme.radius.sm
        , Ui.width Ui.fill
        , Ui.contentCenterY
        ]
        [ Ui.el [ Ui.Font.color Theme.base.textSubtle, Ui.width Ui.shrink ]
            (UI.Components.featherIcon 16 FeatherIcons.userMinus)
        , Ui.el [ Ui.Font.size Theme.font.sm, Ui.width Ui.fill ]
            (Ui.text (T.mergeRetireLine { source = source.name, target = target.name } i18n))
        ]


entryActionRow : I18n -> Merge.Action -> Ui.Element Msg
entryActionRow i18n action =
    case action of
        Merge.ModifyEntry { original } ->
            entryRow i18n original False

        Merge.DeleteSelfTransfer { original } ->
            entryRow i18n original True

        _ ->
            Ui.none


entryRow : I18n -> Entry.Entry -> Bool -> Ui.Element Msg
entryRow i18n entry isSelfTransferDelete =
    let
        ( icon, label ) =
            case entry.kind of
                Entry.Expense data ->
                    ( FeatherIcons.shoppingBag, data.description )

                Entry.Transfer data ->
                    ( FeatherIcons.arrowRight, Maybe.withDefault (T.entryTransfer i18n) data.description )

                Entry.Income _ ->
                    ( FeatherIcons.gift, T.entryIncome i18n )

        suffix : Ui.Element Msg
        suffix =
            if isSelfTransferDelete then
                Ui.el
                    [ Ui.Font.size Theme.font.xs
                    , Ui.Font.color Theme.danger.text
                    , Ui.width Ui.shrink
                    ]
                    (Ui.text (T.mergeSelfTransferTag i18n))

            else
                Ui.none
    in
    Ui.row
        [ Ui.spacing Theme.spacing.sm
        , Ui.paddingXY Theme.spacing.md Theme.spacing.sm
        , Ui.background Theme.base.bg
        , Ui.border Theme.border
        , Ui.borderColor Theme.base.accent
        , Ui.rounded Theme.radius.sm
        , Ui.width Ui.fill
        , Ui.contentCenterY
        ]
        [ Ui.el [ Ui.Font.color Theme.base.textSubtle, Ui.width Ui.shrink ]
            (UI.Components.featherIcon 14 icon)
        , Ui.el [ Ui.Font.size Theme.font.sm, Ui.width Ui.fill ]
            (Ui.text label)
        , suffix
        ]


prefActionRow : I18n -> GroupState -> Merge.Action -> Ui.Element Msg
prefActionRow i18n state action =
    let
        nameOf : Member.Id -> String
        nameOf id =
            Dict.get id state.members
                |> Maybe.map .name
                |> Maybe.withDefault id

        text : String
        text =
            case action of
                Merge.UpdateSettlementPref pref ->
                    T.mergePrefUpdated (nameOf pref.memberRootId) i18n

                _ ->
                    ""
    in
    Ui.el
        [ Ui.paddingXY Theme.spacing.md Theme.spacing.sm
        , Ui.background Theme.base.bg
        , Ui.border Theme.border
        , Ui.borderColor Theme.base.accent
        , Ui.rounded Theme.radius.sm
        , Ui.width Ui.fill
        , Ui.Font.size Theme.font.sm
        ]
        (Ui.text text)


warningCallout : String -> Ui.Element Msg
warningCallout message =
    Ui.row
        [ Ui.spacing Theme.spacing.sm
        , Ui.padding Theme.spacing.md
        , Ui.rounded Theme.radius.md
        , Ui.background Theme.warning.bgSubtle
        , Ui.border Theme.border
        , Ui.borderColor Theme.warning.accent
        , Ui.width Ui.fill
        , Ui.contentCenterY
        ]
        [ Ui.el [ Ui.Font.color Theme.warning.accent, Ui.width Ui.shrink ]
            (UI.Components.featherIcon 18 FeatherIcons.alertTriangle)
        , Ui.el
            [ Ui.Font.size Theme.font.sm
            , Ui.Font.color Theme.warning.text
            , Ui.width Ui.fill
            ]
            (Ui.text message)
        ]


confirmSection : I18n -> ModelData -> Member.ChainState -> Ui.Element Msg
confirmSection i18n data sourceMember =
    let
        canSubmit : Bool
        canSubmit =
            String.trim data.confirmInput == sourceMember.name && sourceMember.name /= ""
    in
    Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
        [ Ui.el
            [ Ui.Font.size Theme.font.sm
            , Ui.Font.color Theme.base.text
            ]
            (Ui.text (T.mergeConfirmHint sourceMember.name i18n))
        , Ui.Input.text
            [ Ui.width Ui.fill
            , Ui.padding Theme.spacing.sm
            , Ui.rounded Theme.radius.sm
            , Ui.border Theme.border
            , Ui.borderColor Theme.base.accent
            ]
            { onChange = InputConfirm
            , text = data.confirmInput
            , placeholder = Just (T.mergeConfirmPlaceholder i18n)
            , label = Ui.Input.labelHidden (T.mergeConfirmHint sourceMember.name i18n)
            }
        , if canSubmit then
            UI.Components.btnDanger []
                { label = T.mergeSubmitButton sourceMember.name i18n
                , icon = FeatherIcons.alertTriangle
                , onPress = Submit
                }

          else
            Ui.row
                [ Ui.width Ui.fill
                , Ui.spacing Theme.spacing.sm
                , Ui.contentCenterX
                , Ui.contentCenterY
                , Ui.padding Theme.spacing.md
                , Ui.rounded Theme.radius.md
                , Ui.background Theme.base.bgSubtle
                , Ui.Font.color Theme.base.textSubtle
                , Ui.Font.weight Theme.fontWeight.semibold
                , Ui.Font.size Theme.font.md
                ]
                [ UI.Components.featherIcon 16 FeatherIcons.alertTriangle
                , Ui.text (T.mergeSubmitButton sourceMember.name i18n)
                ]
        ]



-- SHARED HELPERS


type SlotTone
    = ToneRetiring
    | ToneKeeping


memberSlot :
    { label : String
    , member : Member.ChainState
    , tone : SlotTone
    }
    -> Ui.Element Msg
memberSlot config =
    let
        ( labelColor, borderColor, avatarColor ) =
            case config.tone of
                ToneRetiring ->
                    ( Theme.danger.text, Theme.danger.accent, UI.Components.AvatarRed )

                ToneKeeping ->
                    ( Theme.success.text, Theme.success.accent, UI.Components.AvatarAccent )
    in
    Ui.column
        [ Ui.spacing Theme.spacing.xs
        , Ui.padding Theme.spacing.md
        , Ui.background Theme.base.bg
        , Ui.border Theme.border
        , Ui.borderColor borderColor
        , Ui.rounded Theme.radius.md
        , Ui.width Ui.fill
        ]
        [ Ui.el
            [ Ui.Font.size Theme.font.xs
            , Ui.Font.weight Theme.fontWeight.semibold
            , Ui.Font.letterSpacing Theme.letterSpacing.wide
            , Ui.Font.color labelColor
            ]
            (Ui.text (String.toUpper config.label))
        , Ui.row [ Ui.spacing Theme.spacing.sm, Ui.contentCenterY, Ui.width Ui.fill ]
            [ UI.Components.avatar avatarColor (initialsOf config.member)
            , Ui.el
                [ Ui.Font.weight Theme.fontWeight.semibold
                , Ui.Font.size Theme.font.md
                , Ui.width Ui.fill
                ]
                (Ui.text config.member.name)
            ]
        ]


initialsOf : Member.ChainState -> String
initialsOf member =
    String.left 2 (String.toUpper member.name)


smallTag : String -> Ui.Color -> Ui.Color -> Ui.Element Msg
smallTag label bg fontColor =
    Ui.el
        [ Ui.Font.size Theme.font.xs
        , Ui.Font.weight Theme.fontWeight.semibold
        , Ui.paddingXY Theme.spacing.sm Theme.spacing.xs
        , Ui.rounded Theme.radius.sm
        , Ui.background bg
        , Ui.Font.color fontColor
        , Ui.width Ui.shrink
        ]
        (Ui.text label)


headingSection : String -> String -> Ui.Element Msg
headingSection title subtitle =
    Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
        [ Ui.el
            [ Ui.Font.size Theme.font.lg
            , Ui.Font.weight Theme.fontWeight.semibold
            ]
            (Ui.text title)
        , Ui.el
            [ Ui.Font.size Theme.font.sm
            , Ui.Font.color Theme.base.textSubtle
            ]
            (Ui.text subtitle)
        ]


collapsible :
    { isOpen : Bool
    , toggle : Msg
    , label : String
    , content : Ui.Element Msg
    }
    -> Ui.Element Msg
collapsible config =
    Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
        [ UI.Components.expandTrigger
            { label = config.label
            , isOpen = config.isOpen
            , onPress = config.toggle
            }
        , if config.isOpen then
            config.content

          else
            Ui.none
        ]


memberNotFoundView : I18n -> Ui.Element Msg
memberNotFoundView i18n =
    Ui.el
        [ Ui.padding Theme.spacing.lg
        , Ui.Font.color Theme.danger.text
        ]
        (Ui.text (T.mergeMemberNotFound i18n))
