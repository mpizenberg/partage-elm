module Page.Group.ActivityTab exposing (Config, Model, Msg, init, update, view)

{-| Activity tab showing the group's event history with involvement markers,
expandable detail views, and filtering.
-}

import Domain.Activity exposing (Activity, Detail(..), GroupMetadataSnapshot)
import Domain.Currency as Currency exposing (Currency)
import Domain.Date as Date
import Domain.Entry as Entry exposing (Kind(..))
import Domain.Event as Event
import Domain.Filter as Filter exposing (ActivityFilters, ActivityType(..))
import Domain.Member as Member
import FeatherIcons
import Format
import List.Extra
import Set exposing (Set)
import Time
import Translations as T exposing (I18n)
import UI.Components
import UI.Theme as Theme
import Ui
import Ui.Anim as Anim
import Ui.Events
import Ui.Font
import Ui.Input


type Model
    = Model
        { filters : ActivityFilters
        , showFilters : Bool
        , expandedActivities : Set Event.Id
        }


type Msg
    = ToggleFilters
    | ToggleActivityType String
    | ToggleActor Member.Id
    | ToggleInvolvedMember Member.Id
    | ClearAllFilters
    | ToggleExpanded Event.Id


type alias Config msg =
    { resolveName : Member.Id -> String
    , currentUserRootId : Member.Id
    , groupDefaultCurrency : Currency
    , toMsg : Msg -> msg
    , allMembers : List ( Member.Id, String )
    }


init : Model
init =
    Model
        { filters = Filter.emptyActivityFilters
        , showFilters = False
        , expandedActivities = Set.empty
        }


update : Msg -> Model -> Model
update msg (Model data) =
    case msg of
        ToggleFilters ->
            Model { data | showFilters = not data.showFilters }

        ToggleActivityType typeStr ->
            Model (updateFilters (\f -> { f | activityTypes = toggleSet typeStr f.activityTypes }) data)

        ToggleActor memberId ->
            Model (updateFilters (\f -> { f | actors = toggleSet memberId f.actors }) data)

        ToggleInvolvedMember memberId ->
            Model (updateFilters (\f -> { f | involvedMembers = toggleSet memberId f.involvedMembers }) data)

        ClearAllFilters ->
            Model { data | filters = Filter.emptyActivityFilters }

        ToggleExpanded eventId ->
            Model
                { data
                    | expandedActivities =
                        if Set.member eventId data.expandedActivities then
                            Set.remove eventId data.expandedActivities

                        else
                            Set.insert eventId data.expandedActivities
                }


updateFilters : (ActivityFilters -> ActivityFilters) -> { a | filters : ActivityFilters } -> { a | filters : ActivityFilters }
updateFilters transform data =
    { data | filters = transform data.filters }


toggleSet : comparable -> Set comparable -> Set comparable
toggleSet item set =
    if Set.member item set then
        Set.remove item set

    else
        Set.insert item set


{-| Render the activity tab with filtering and a chronological list of group events.
-}
view : I18n -> Config msg -> Model -> List Activity -> Ui.Element msg
view i18n config (Model data) activities =
    let
        filteredActivities : List Activity
        filteredActivities =
            List.filter (Filter.matchesActivityFilters data.filters) activities
    in
    Ui.column [ Ui.spacing Theme.spacing.md, Ui.width Ui.fill ]
        [ filterToggleRow config.toMsg data.showFilters data.filters
        , if data.showFilters then
            filterPanel i18n config data.filters

          else if Filter.isActivityFilterActive data.filters then
            activeFilterSummary i18n config data.filters

          else
            Ui.none
        , if List.isEmpty filteredActivities then
            Ui.el
                [ Ui.Font.size Theme.font.sm
                , Ui.Font.color Theme.base.textSubtle
                , Ui.paddingXY 0 Theme.spacing.lg
                ]
                (Ui.text (T.activityComingSoon i18n))

          else
            Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
                (groupedByDate i18n config data.expandedActivities filteredActivities)
        ]


filterToggleRow : (Msg -> msg) -> Bool -> ActivityFilters -> Ui.Element msg
filterToggleRow toMsg showFilters filters =
    let
        ( bg, border, fontColor ) =
            if showFilters || Filter.isActivityFilterActive filters then
                ( Theme.primary.solid, Theme.primary.solid, Theme.primary.solidText )

            else
                ( Theme.base.bgSubtle, Theme.base.accent, Theme.base.textSubtle )
    in
    Ui.row [ Ui.spacing Theme.spacing.sm, Ui.contentCenterY, Ui.width Ui.fill ]
        [ Ui.el
            [ Ui.Input.button (toMsg ToggleFilters)
            , Ui.alignRight
            , Ui.width (Ui.px Theme.sizing.lg)
            , Ui.height (Ui.px Theme.sizing.lg)
            , Ui.rounded Theme.radius.md
            , Ui.border Theme.border
            , Ui.contentCenterX
            , Ui.contentCenterY
            , Ui.pointer
            , Anim.transition (Anim.ms 200)
                [ Anim.backgroundColor bg
                , Anim.borderColor border
                , Anim.fontColor fontColor
                ]
            ]
            (UI.Components.featherIcon 18 FeatherIcons.filter)
        ]


activeFilterSummary : I18n -> Config msg -> ActivityFilters -> Ui.Element msg
activeFilterSummary i18n config filters =
    let
        activityTypeLabels : List ( String, String )
        activityTypeLabels =
            [ ( Filter.activityTypeToString EntryActivity, T.filterActivityEntry i18n )
            , ( Filter.activityTypeToString MemberActivity, T.filterActivityMember i18n )
            , ( Filter.activityTypeToString GroupActivity, T.filterActivityGroup i18n )
            ]

        typeCategory : String
        typeCategory =
            T.filterActivityTypeLabel i18n

        typeChips : List (Ui.Element msg)
        typeChips =
            activityTypeLabels
                |> List.filterMap
                    (\( key, label ) ->
                        if Set.member key filters.activityTypes then
                            Just (filterChip typeCategory label)

                        else
                            Nothing
                    )

        actorChips : List (Ui.Element msg)
        actorChips =
            Set.toList filters.actors
                |> List.map (\id -> filterChip (T.filterActorLabel i18n) (config.resolveName id))

        involvedChips : List (Ui.Element msg)
        involvedChips =
            Set.toList filters.involvedMembers
                |> List.map (\id -> filterChip (T.filterInvolvedLabel i18n) (config.resolveName id))
    in
    Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
        [ UI.Components.sectionLabel (T.filterSectionTitle i18n)
        , Ui.row [ Ui.wrap, Ui.spacing Theme.spacing.xs ]
            (List.concat [ typeChips, actorChips, involvedChips ])
        ]


filterChip : String -> String -> Ui.Element msg
filterChip category label =
    Ui.row
        [ Ui.Font.size Theme.font.xs
        , Ui.paddingXY Theme.spacing.sm Theme.spacing.xs
        , Ui.rounded Theme.radius.md
        , Ui.background Theme.primary.tint
        , Ui.width Ui.shrink
        , Ui.spacing Theme.spacing.xs
        ]
        [ Ui.el [ Ui.Font.color Theme.base.textSubtle ] (Ui.text (category ++ ":"))
        , Ui.el
            [ Ui.Font.color Theme.primary.text
            , Ui.Font.weight Theme.fontWeight.medium
            ]
            (Ui.text label)
        ]


filterPanel : I18n -> Config msg -> ActivityFilters -> Ui.Element msg
filterPanel i18n config filters =
    UI.Components.card [ Ui.padding Theme.spacing.lg ]
        [ Ui.column [ Ui.spacing Theme.spacing.md, Ui.width Ui.fill ]
            [ activityTypeFilterSection i18n config.toMsg filters.activityTypes
            , actorFilterSection i18n config filters.actors
            , involvedFilterSection i18n config filters.involvedMembers
            , if Filter.isActivityFilterActive filters then
                Ui.el
                    [ Ui.pointer
                    , Ui.Events.onClick (config.toMsg ClearAllFilters)
                    , Ui.Font.size Theme.font.sm
                    , Ui.Font.color Theme.danger.text
                    , Ui.Font.weight Theme.fontWeight.medium
                    ]
                    (Ui.text (T.filterClearAll i18n))

              else
                Ui.none
            ]
        ]


activityTypeFilterSection : I18n -> (Msg -> msg) -> Set String -> Ui.Element msg
activityTypeFilterSection i18n toMsg selected =
    let
        types : List ( String, String )
        types =
            [ ( Filter.activityTypeToString EntryActivity, T.filterActivityEntry i18n )
            , ( Filter.activityTypeToString MemberActivity, T.filterActivityMember i18n )
            , ( Filter.activityTypeToString GroupActivity, T.filterActivityGroup i18n )
            ]
    in
    filterSection (T.filterActivityTypeLabel i18n)
        (List.map
            (\( key, label ) ->
                UI.Components.chip
                    { label = label
                    , selected = Set.member key selected
                    , onPress = toMsg (ToggleActivityType key)
                    }
            )
            types
        )


actorFilterSection : I18n -> Config msg -> Set Member.Id -> Ui.Element msg
actorFilterSection i18n config selected =
    filterSection (T.filterActorLabel i18n)
        (List.map
            (\( id, name ) ->
                UI.Components.chip
                    { label = name
                    , selected = Set.member id selected
                    , onPress = config.toMsg (ToggleActor id)
                    }
            )
            config.allMembers
        )


involvedFilterSection : I18n -> Config msg -> Set Member.Id -> Ui.Element msg
involvedFilterSection i18n config selected =
    filterSection (T.filterInvolvedLabel i18n)
        (List.map
            (\( id, name ) ->
                UI.Components.chip
                    { label = name
                    , selected = Set.member id selected
                    , onPress = config.toMsg (ToggleInvolvedMember id)
                    }
            )
            config.allMembers
        )


filterSection : String -> List (Ui.Element msg) -> Ui.Element msg
filterSection label chips =
    Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
        [ Ui.el
            [ Ui.Font.size Theme.font.sm
            , Ui.Font.color Theme.base.textSubtle
            , Ui.Font.weight Theme.fontWeight.medium
            ]
            (Ui.text label)
        , Ui.row [ Ui.wrap, Ui.spacing Theme.spacing.xs ] chips
        ]


groupedByDate : I18n -> Config msg -> Set Event.Id -> List Activity -> List (Ui.Element msg)
groupedByDate i18n config expandedActivities activities =
    let
        dateKey : Activity -> ( Int, Int, Int )
        dateKey activity =
            ( Time.toYear Time.utc activity.timestamp
            , monthToInt (Time.toMonth Time.utc activity.timestamp)
            , Time.toDay Time.utc activity.timestamp
            )
    in
    List.Extra.groupWhile (\a1 a2 -> dateKey a1 == dateKey a2) activities
        |> List.concatMap
            (\( first, rest ) ->
                dateSeparator i18n first.timestamp
                    :: List.map (activityItem i18n config expandedActivities) (first :: rest)
            )


dateSeparator : I18n -> Time.Posix -> Ui.Element msg
dateSeparator i18n posix =
    let
        year : Int
        year =
            Time.toYear Time.utc posix

        month : Int
        month =
            monthToInt (Time.toMonth Time.utc posix)

        day : Int
        day =
            Time.toDay Time.utc posix
    in
    Ui.el
        [ Ui.paddingTop Theme.spacing.md
        , Ui.Font.size Theme.font.xs
        , Ui.Font.weight Theme.fontWeight.semibold
        , Ui.Font.letterSpacing Theme.letterSpacing.wide
        , Ui.Font.color Theme.base.textSubtle
        ]
        (Ui.text (String.toUpper (monthName i18n month ++ " " ++ String.fromInt day ++ ", " ++ String.fromInt year)))


monthName : I18n -> Int -> String
monthName i18n m =
    case m of
        1 ->
            T.monthJanuary i18n

        2 ->
            T.monthFebruary i18n

        3 ->
            T.monthMarch i18n

        4 ->
            T.monthApril i18n

        5 ->
            T.monthMay i18n

        6 ->
            T.monthJune i18n

        7 ->
            T.monthJuly i18n

        8 ->
            T.monthAugust i18n

        9 ->
            T.monthSeptember i18n

        10 ->
            T.monthOctober i18n

        11 ->
            T.monthNovember i18n

        12 ->
            T.monthDecember i18n

        _ ->
            ""


activityItem : I18n -> Config msg -> Set Event.Id -> Activity -> Ui.Element msg
activityItem i18n config expandedActivities activity =
    let
        isExpanded : Bool
        isExpanded =
            Set.member activity.eventId expandedActivities

        isInvolved : Bool
        isInvolved =
            List.member config.currentUserRootId activity.involvedMembers

        ( borderWidth, borderColor ) =
            if isInvolved then
                ( Ui.borderWith { left = 4, top = Theme.border, right = Theme.border, bottom = Theme.border }
                , Ui.borderColor Theme.base.text
                )

            else
                ( Ui.noAttr, Ui.noAttr )
    in
    UI.Components.card
        [ Ui.Input.button (config.toMsg (ToggleExpanded activity.eventId))
        , Ui.paddingXY Theme.spacing.lg Theme.spacing.md
        , Ui.pointer
        , borderWidth
        , borderColor
        ]
        [ Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
            [ summaryRow i18n config.resolveName activity
            , if isExpanded then
                detailPanel i18n config activity.detail

              else
                Ui.none
            ]
        ]


detailIcon : Detail -> FeatherIcons.Icon
detailIcon detail =
    case detail of
        EntryAddedDetail _ ->
            FeatherIcons.plusCircle

        EntryModifiedDetail _ ->
            FeatherIcons.edit

        TransferAddedDetail _ ->
            FeatherIcons.arrowRight

        TransferModifiedDetail _ ->
            FeatherIcons.edit

        EntryDeletedDetail _ ->
            FeatherIcons.trash2

        EntryUndeletedDetail _ ->
            FeatherIcons.rotateCcw

        MemberCreatedDetail _ ->
            FeatherIcons.userPlus

        MemberReplacedDetail _ ->
            FeatherIcons.userCheck

        MemberRenamedDetail _ ->
            FeatherIcons.user

        MemberRetiredDetail _ ->
            FeatherIcons.userMinus

        MemberUnretiredDetail _ ->
            FeatherIcons.userCheck

        MemberMetadataUpdatedDetail _ ->
            FeatherIcons.user

        GroupCreatedDetail _ ->
            FeatherIcons.folder

        GroupMetadataUpdatedDetail _ ->
            FeatherIcons.settings

        SettlementPreferencesUpdatedDetail _ ->
            FeatherIcons.sliders


summaryRow : I18n -> (Member.Id -> String) -> Activity -> Ui.Element msg
summaryRow i18n resolveName activity =
    Ui.row [ Ui.spacing Theme.spacing.md, Ui.contentCenterY ]
        [ Ui.el [ Ui.width Ui.shrink, Ui.Font.color Theme.base.textSubtle ]
            (UI.Components.featherIcon 16 (detailIcon activity.detail))
        , Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.shrink ]
            [ Ui.el
                [ Ui.Font.weight Theme.fontWeight.semibold
                , Ui.Font.size Theme.font.sm
                , Ui.clipWithEllipsis
                ]
                (Ui.text (resolveName activity.actorId))
            , Ui.el
                [ Ui.Font.size Theme.font.xs
                , Ui.Font.color Theme.base.textSubtle
                , Ui.clipWithEllipsis
                ]
                (Ui.text (formatTimestamp activity.timestamp))
            ]
        , Ui.el [ Ui.Font.size Theme.font.sm ]
            (Ui.text (detailSummaryText i18n activity.detail))
        ]


detailSummaryText : I18n -> Detail -> String
detailSummaryText i18n detail =
    case detail of
        EntryAddedDetail data ->
            case data.entry.kind of
                Expense expData ->
                    T.activityEntryAdded expData.description i18n
                        ++ " ("
                        ++ Format.formatCentsWithCurrency expData.amount expData.currency
                        ++ ")"

                Transfer _ ->
                    T.activityTransferAdded i18n

        EntryModifiedDetail data ->
            case data.entry.kind of
                Expense expData ->
                    T.activityEntryModified expData.description i18n
                        ++ " ("
                        ++ Format.formatCentsWithCurrency expData.amount expData.currency
                        ++ ")"
                        ++ changesText i18n data.changes

                Transfer _ ->
                    T.activityTransferModified i18n

        TransferAddedDetail data ->
            case data.entry.kind of
                Transfer tData ->
                    T.activityTransferAdded i18n
                        ++ " ("
                        ++ Format.formatCentsWithCurrency tData.amount tData.currency
                        ++ ")"

                Expense _ ->
                    T.activityTransferAdded i18n

        TransferModifiedDetail data ->
            case data.entry.kind of
                Transfer tData ->
                    T.activityTransferModified i18n
                        ++ " ("
                        ++ Format.formatCentsWithCurrency tData.amount tData.currency
                        ++ ")"
                        ++ changesText i18n data.changes

                Expense _ ->
                    T.activityTransferModified i18n

        EntryDeletedDetail data ->
            T.activityEntryDeleted data.entryDescription i18n

        EntryUndeletedDetail data ->
            T.activityEntryUndeleted data.entryDescription i18n

        MemberCreatedDetail data ->
            case data.memberType of
                Member.Real ->
                    T.activityMemberCreated data.name i18n

                Member.Virtual ->
                    T.activityMemberCreatedVirtual data.name i18n

        MemberReplacedDetail data ->
            T.activityMemberReplaced data.name i18n

        MemberRenamedDetail data ->
            T.activityMemberRenamed { oldName = data.oldName, newName = data.newName } i18n

        MemberRetiredDetail data ->
            T.activityMemberRetired data.name i18n

        MemberUnretiredDetail data ->
            T.activityMemberUnretired data.name i18n

        MemberMetadataUpdatedDetail data ->
            T.activityMemberMetadataUpdated data.name i18n
                ++ changesText i18n data.updatedFields

        GroupCreatedDetail _ ->
            T.activityGroupCreated i18n

        GroupMetadataUpdatedDetail data ->
            T.activityGroupMetadataUpdated i18n
                ++ changesText i18n data.changedFields

        SettlementPreferencesUpdatedDetail data ->
            T.activitySettlementPreferencesUpdated data.name i18n


changesText : I18n -> List String -> String
changesText i18n fields =
    case fields of
        [] ->
            ""

        _ ->
            " — " ++ String.join ", " (List.map (translateField i18n) fields)


translateField : I18n -> String -> String
translateField i18n field =
    case field of
        "description" ->
            T.changeFieldDescription i18n

        "amount" ->
            T.changeFieldAmount i18n

        "date" ->
            T.changeFieldDate i18n

        "payers" ->
            T.changeFieldPayers i18n

        "beneficiaries" ->
            T.changeFieldBeneficiaries i18n

        "category" ->
            T.changeFieldCategory i18n

        "notes" ->
            T.changeFieldNotes i18n

        "from" ->
            T.changeFieldFrom i18n

        "to" ->
            T.changeFieldTo i18n

        "phone" ->
            T.changeFieldPhone i18n

        "email" ->
            T.changeFieldEmail i18n

        "payment" ->
            T.changeFieldPayment i18n

        "name" ->
            T.changeFieldName i18n

        "subtitle" ->
            T.changeFieldSubtitle i18n

        "links" ->
            T.changeFieldLinks i18n

        _ ->
            field



-- DETAIL PANELS


detailPanel : I18n -> Config msg -> Detail -> Ui.Element msg
detailPanel i18n config detail =
    Ui.column
        [ Ui.spacing Theme.spacing.sm
        , Ui.width Ui.fill
        , Ui.paddingWith { top = Theme.spacing.sm, bottom = 0, left = Theme.spacing.md, right = 0 }
        , Ui.borderWith { left = 2, top = 0, right = 0, bottom = 0 }
        , Ui.borderColor Theme.primary.accent
        ]
        (detailContent i18n config detail)


detailContent : I18n -> Config msg -> Detail -> List (Ui.Element msg)
detailContent i18n config detail =
    let
        resolveName : Member.Id -> String
        resolveName =
            config.resolveName
    in
    case detail of
        EntryAddedDetail data ->
            entryDetailRows i18n config.groupDefaultCurrency resolveName data.entry

        EntryModifiedDetail data ->
            entryModifiedDiffRows i18n config.groupDefaultCurrency resolveName data.entry data.previousEntry

        TransferAddedDetail data ->
            entryDetailRows i18n config.groupDefaultCurrency resolveName data.entry

        TransferModifiedDetail data ->
            entryModifiedDiffRows i18n config.groupDefaultCurrency resolveName data.entry data.previousEntry

        EntryDeletedDetail data ->
            case data.entry of
                Just entry ->
                    entryDetailRows i18n config.groupDefaultCurrency resolveName entry

                Nothing ->
                    [ detailRow (T.newEntryDescriptionLabel i18n) data.entryDescription ]

        EntryUndeletedDetail data ->
            case data.entry of
                Just entry ->
                    entryDetailRows i18n config.groupDefaultCurrency resolveName entry

                Nothing ->
                    [ detailRow (T.newEntryDescriptionLabel i18n) data.entryDescription ]

        MemberCreatedDetail data ->
            [ detailRow (T.changeFieldName i18n) data.name
            , detailRow (T.activityMemberTypeLabel i18n)
                (case data.memberType of
                    Member.Real ->
                        T.memberDetailTypeReal i18n

                    Member.Virtual ->
                        T.memberDetailTypeVirtual i18n
                )
            ]

        MemberReplacedDetail data ->
            [ detailRow (T.changeFieldName i18n) data.name ]

        MemberRenamedDetail data ->
            [ diffRow (T.changeFieldName i18n) data.oldName data.newName ]

        MemberRetiredDetail data ->
            [ detailRow (T.changeFieldName i18n) data.name ]

        MemberUnretiredDetail data ->
            [ detailRow (T.changeFieldName i18n) data.name ]

        MemberMetadataUpdatedDetail data ->
            memberMetadataDiffRows i18n data.oldMetadata data.newMetadata

        GroupCreatedDetail data ->
            [ detailRow (T.changeFieldName i18n) data.name
            , detailRow (T.newEntryCurrencyLabel i18n) (Currency.currencyCode data.defaultCurrency)
            ]

        GroupMetadataUpdatedDetail data ->
            groupMetadataDiffRows i18n data.oldMeta data.newMeta

        SettlementPreferencesUpdatedDetail data ->
            let
                formatRecipients : List String -> String
                formatRecipients recipients =
                    case recipients of
                        [] ->
                            T.activityDetailNoValue i18n

                        _ ->
                            String.join ", " recipients
            in
            [ detailRow (T.changeFieldName i18n) data.name
            , diffRow (T.settlementPreferPayFirst i18n)
                (formatRecipients data.oldRecipients)
                (formatRecipients data.newRecipients)
            ]


entryDetailRows : I18n -> Currency -> (Member.Id -> String) -> Entry.Entry -> List (Ui.Element msg)
entryDetailRows i18n groupCurrency resolveName entry =
    case entry.kind of
        Expense data ->
            List.concat
                [ [ detailRow (T.newEntryDescriptionLabel i18n) data.description
                  , detailRow (T.entryDetailDate i18n) (Date.toString data.date)
                  , detailRow (T.newEntryAmountLabel i18n) (Format.formatCentsWithCurrency data.amount data.currency)
                  ]
                , defaultCurrencyAmountRow groupCurrency data.defaultCurrencyAmount
                , [ detailRow (T.entryDetailPaidBy i18n) (payerNames resolveName data.payers)
                  , detailRow (T.entryDetailSplitAmong i18n) (beneficiaryNames resolveName data.beneficiaries)
                  ]
                , categoryRow i18n data.category
                , optionalRow (T.entryDetailNotes i18n) data.notes
                ]

        Transfer data ->
            List.concat
                [ [ detailRow (T.entryDetailDate i18n) (Date.toString data.date)
                  , detailRow (T.newEntryAmountLabel i18n) (Format.formatCentsWithCurrency data.amount data.currency)
                  ]
                , defaultCurrencyAmountRow groupCurrency data.defaultCurrencyAmount
                , [ detailRow (T.entryDetailFrom i18n) (resolveName data.from)
                  , detailRow (T.entryDetailTo i18n) (resolveName data.to)
                  ]
                , optionalRow (T.entryDetailNotes i18n) data.notes
                ]


defaultCurrencyAmountRow : Currency -> Maybe Int -> List (Ui.Element msg)
defaultCurrencyAmountRow groupCurrency maybeAmount =
    case maybeAmount of
        Just amount ->
            [ Ui.el
                [ Ui.Font.size Theme.font.sm
                , Ui.Font.color Theme.base.textSubtle
                ]
                (Ui.text ("≈ " ++ Format.formatCentsWithCurrency amount groupCurrency))
            ]

        Nothing ->
            []


entryModifiedDiffRows : I18n -> Currency -> (Member.Id -> String) -> Entry.Entry -> Maybe Entry.Entry -> List (Ui.Element msg)
entryModifiedDiffRows i18n groupCurrency resolveName newEntry maybePreviousEntry =
    case maybePreviousEntry of
        Nothing ->
            entryDetailRows i18n groupCurrency resolveName newEntry

        Just oldEntry ->
            case ( newEntry.kind, oldEntry.kind ) of
                ( Expense new, Expense old ) ->
                    expenseDiffRows i18n groupCurrency resolveName old new

                ( Transfer new, Transfer old ) ->
                    transferDiffRows i18n groupCurrency resolveName old new

                _ ->
                    entryDetailRows i18n groupCurrency resolveName newEntry


expenseDiffRows : I18n -> Currency -> (Member.Id -> String) -> Entry.ExpenseData -> Entry.ExpenseData -> List (Ui.Element msg)
expenseDiffRows i18n groupCurrency resolveName old new =
    List.concat
        [ [ maybeDiffOrDetailRow (T.newEntryDescriptionLabel i18n) old.description new.description ]
        , [ maybeDiffOrDetailRow (T.entryDetailDate i18n) (Date.toString old.date) (Date.toString new.date) ]
        , amountCurrencyDiffRows i18n
            groupCurrency
            { oldAmount = old.amount, oldCurrency = old.currency, oldDefaultCurrencyAmount = old.defaultCurrencyAmount }
            { newAmount = new.amount, newCurrency = new.currency, newDefaultCurrencyAmount = new.defaultCurrencyAmount }
        , [ payerDiffOrDetailRow i18n resolveName old.payers new.payers ]
        , [ beneficiaryDiffOrDetailRow i18n resolveName old.beneficiaries new.beneficiaries ]
        , categoryDiffRow i18n old.category new.category
        , notesDiffRow i18n old.notes new.notes
        ]


transferDiffRows : I18n -> Currency -> (Member.Id -> String) -> Entry.TransferData -> Entry.TransferData -> List (Ui.Element msg)
transferDiffRows i18n groupCurrency resolveName old new =
    List.concat
        [ [ maybeDiffOrDetailRow (T.entryDetailDate i18n) (Date.toString old.date) (Date.toString new.date) ]
        , amountCurrencyDiffRows i18n
            groupCurrency
            { oldAmount = old.amount, oldCurrency = old.currency, oldDefaultCurrencyAmount = old.defaultCurrencyAmount }
            { newAmount = new.amount, newCurrency = new.currency, newDefaultCurrencyAmount = new.defaultCurrencyAmount }
        , [ maybeDiffOrDetailRow (T.entryDetailFrom i18n) (resolveName old.from) (resolveName new.from) ]
        , [ maybeDiffOrDetailRow (T.entryDetailTo i18n) (resolveName old.to) (resolveName new.to) ]
        , notesDiffRow i18n old.notes new.notes
        ]


maybeDiffOrDetailRow : String -> String -> String -> Ui.Element msg
maybeDiffOrDetailRow label oldVal newVal =
    if oldVal == newVal then
        detailRow label newVal

    else
        diffRow label oldVal newVal


amountCurrencyDiffRows :
    I18n
    -> Currency
    -> { oldAmount : Int, oldCurrency : Currency, oldDefaultCurrencyAmount : Maybe Int }
    -> { newAmount : Int, newCurrency : Currency, newDefaultCurrencyAmount : Maybe Int }
    -> List (Ui.Element msg)
amountCurrencyDiffRows i18n groupCurrency old new =
    let
        currencyChanged : Bool
        currencyChanged =
            old.oldCurrency /= new.newCurrency

        formatDefaultAmount : Int -> String
        formatDefaultAmount amt =
            Format.formatCentsWithCurrency amt groupCurrency

        currencyRow : List (Ui.Element msg)
        currencyRow =
            if currencyChanged then
                [ diffRow (T.newEntryCurrencyLabel i18n)
                    (Currency.currencyCode old.oldCurrency)
                    (Currency.currencyCode new.newCurrency)
                ]

            else
                []

        amountRow : List (Ui.Element msg)
        amountRow =
            let
                amountChanged : Bool
                amountChanged =
                    old.oldAmount /= new.newAmount

                label : String
                label =
                    T.newEntryAmountLabel i18n

                newFormatted : String
                newFormatted =
                    Format.formatCentsWithCurrency new.newAmount new.newCurrency
            in
            if amountChanged || currencyChanged then
                let
                    oldFormatted : String
                    oldFormatted =
                        Format.formatCentsWithCurrency old.oldAmount old.oldCurrency
                in
                [ diffRow label oldFormatted newFormatted ]

            else
                [ detailRow label newFormatted ]

        defaultAmountRow : List (Ui.Element msg)
        defaultAmountRow =
            let
                label : String
                label =
                    "≈ " ++ T.newEntryAmountLabel i18n
            in
            case ( old.oldDefaultCurrencyAmount, new.newDefaultCurrencyAmount ) of
                ( Nothing, Nothing ) ->
                    []

                ( Nothing, Just newAmt ) ->
                    [ detailRow label (formatDefaultAmount newAmt) ]

                ( Just oldAmt, Nothing ) ->
                    [ diffRow label
                        (formatDefaultAmount oldAmt)
                        (T.activityDetailRemoved i18n)
                    ]

                ( Just oldAmt, Just newAmt ) ->
                    if oldAmt == newAmt && not currencyChanged then
                        [ detailRow label (formatDefaultAmount newAmt) ]

                    else
                        [ diffRow label
                            (formatDefaultAmount oldAmt)
                            (formatDefaultAmount newAmt)
                        ]
    in
    currencyRow ++ amountRow ++ defaultAmountRow


payerDiffOrDetailRow : I18n -> (Member.Id -> String) -> List Entry.Payer -> List Entry.Payer -> Ui.Element msg
payerDiffOrDetailRow i18n resolveName oldPayers newPayers =
    let
        label : String
        label =
            T.entryDetailPaidBy i18n

        formatPayer : Entry.Payer -> String
        formatPayer p =
            resolveName p.memberId
    in
    if oldPayers == newPayers then
        detailRow label (payerNames resolveName newPayers)

    else if List.length oldPayers == 1 && List.length newPayers == 1 then
        diffRow label (payerNames resolveName oldPayers) (payerNames resolveName newPayers)

    else
        let
            oldText : String
            oldText =
                oldPayers |> List.map formatPayer |> String.join ", "

            newText : String
            newText =
                newPayers |> List.map formatPayer |> String.join ", "
        in
        diffRow label oldText newText


beneficiaryDiffOrDetailRow : I18n -> (Member.Id -> String) -> List Entry.Beneficiary -> List Entry.Beneficiary -> Ui.Element msg
beneficiaryDiffOrDetailRow i18n resolveName oldBenefs newBenefs =
    let
        label : String
        label =
            T.entryDetailSplitAmong i18n
    in
    if oldBenefs == newBenefs then
        detailRow label (beneficiaryNames resolveName newBenefs)

    else
        diffRow label (beneficiaryNames resolveName oldBenefs) (beneficiaryNames resolveName newBenefs)


categoryDiffRow : I18n -> Maybe Entry.Category -> Maybe Entry.Category -> List (Ui.Element msg)
categoryDiffRow i18n oldCat newCat =
    if oldCat == newCat then
        categoryRow i18n newCat

    else
        let
            oldLabel : String
            oldLabel =
                oldCat |> Maybe.map (categoryLabel i18n) |> Maybe.withDefault (T.newEntryCategoryNone i18n)

            newLabel : String
            newLabel =
                newCat |> Maybe.map (categoryLabel i18n) |> Maybe.withDefault (T.newEntryCategoryNone i18n)
        in
        [ diffRow (T.entryDetailCategory i18n) oldLabel newLabel ]


notesDiffRow : I18n -> Maybe String -> Maybe String -> List (Ui.Element msg)
notesDiffRow i18n oldNotes newNotes =
    if oldNotes == newNotes then
        optionalRow (T.entryDetailNotes i18n) newNotes

    else
        let
            label : String
            label =
                T.entryDetailNotes i18n

            oldText : String
            oldText =
                Maybe.withDefault (T.activityDetailNoValue i18n) oldNotes

            newText : String
            newText =
                Maybe.withDefault (T.activityDetailRemoved i18n) newNotes
        in
        [ diffRow label oldText newText ]


payerNames : (Member.Id -> String) -> List Entry.Payer -> String
payerNames resolveName payers =
    payers
        |> List.map (\p -> resolveName p.memberId)
        |> String.join ", "


beneficiaryNames : (Member.Id -> String) -> List Entry.Beneficiary -> String
beneficiaryNames resolveName beneficiaries =
    beneficiaries
        |> List.map
            (\b ->
                case b of
                    Entry.ShareBeneficiary data ->
                        resolveName data.memberId

                    Entry.ExactBeneficiary data ->
                        resolveName data.memberId
            )
        |> String.join ", "


categoryRow : I18n -> Maybe Entry.Category -> List (Ui.Element msg)
categoryRow i18n maybeCategory =
    case maybeCategory of
        Just category ->
            [ detailRow (T.entryDetailCategory i18n) (categoryLabel i18n category) ]

        Nothing ->
            []


categoryLabel : I18n -> Entry.Category -> String
categoryLabel i18n category =
    case category of
        Entry.Food ->
            T.categoryFood i18n

        Entry.Transport ->
            T.categoryTransport i18n

        Entry.Accommodation ->
            T.categoryAccommodation i18n

        Entry.Entertainment ->
            T.categoryEntertainment i18n

        Entry.Shopping ->
            T.categoryShopping i18n

        Entry.Groceries ->
            T.categoryGroceries i18n

        Entry.Utilities ->
            T.categoryUtilities i18n

        Entry.Healthcare ->
            T.categoryHealthcare i18n

        Entry.Other ->
            T.categoryOther i18n


optionalRow : String -> Maybe String -> List (Ui.Element msg)
optionalRow label maybeValue =
    case maybeValue of
        Just value ->
            [ detailRow label value ]

        Nothing ->
            []



-- DIFF HELPERS


memberMetadataDiffRows : I18n -> Member.Metadata -> Member.Metadata -> List (Ui.Element msg)
memberMetadataDiffRows i18n old new =
    List.filterMap identity
        [ maybeDiffRow (T.changeFieldPhone i18n) old.phone new.phone
        , maybeDiffRow (T.changeFieldEmail i18n) old.email new.email
        , maybeDiffRow (T.changeFieldNotes i18n) old.notes new.notes
        , paymentDiffRows i18n old.payment new.payment
        ]


paymentDiffRows : I18n -> Maybe Member.PaymentInfo -> Maybe Member.PaymentInfo -> Maybe (Ui.Element msg)
paymentDiffRows i18n oldPayment newPayment =
    if oldPayment == newPayment then
        Nothing

    else
        let
            old : Member.PaymentInfo
            old =
                Maybe.withDefault emptyPayment oldPayment

            new : Member.PaymentInfo
            new =
                Maybe.withDefault emptyPayment newPayment

            rows : List (Ui.Element msg)
            rows =
                List.filterMap identity
                    [ maybeDiffRow (T.memberMetadataIban i18n) old.iban new.iban
                    , maybeDiffRow (T.memberMetadataWero i18n) old.wero new.wero
                    , maybeDiffRow (T.memberMetadataLydia i18n) old.lydia new.lydia
                    , maybeDiffRow (T.memberMetadataRevolut i18n) old.revolut new.revolut
                    , maybeDiffRow (T.memberMetadataPaypal i18n) old.paypal new.paypal
                    , maybeDiffRow (T.memberMetadataVenmo i18n) old.venmo new.venmo
                    , maybeDiffRow (T.memberMetadataBtc i18n) old.btcAddress new.btcAddress
                    , maybeDiffRow (T.memberMetadataAda i18n) old.adaAddress new.adaAddress
                    ]
        in
        case rows of
            [] ->
                Nothing

            _ ->
                Just (Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ] rows)


emptyPayment : Member.PaymentInfo
emptyPayment =
    { iban = Nothing
    , wero = Nothing
    , lydia = Nothing
    , revolut = Nothing
    , paypal = Nothing
    , venmo = Nothing
    , btcAddress = Nothing
    , adaAddress = Nothing
    }


maybeDiffRow : String -> Maybe String -> Maybe String -> Maybe (Ui.Element msg)
maybeDiffRow label oldVal newVal =
    if oldVal == newVal then
        Nothing

    else
        Just (diffRow label (Maybe.withDefault "—" oldVal) (Maybe.withDefault "—" newVal))


groupMetadataDiffRows : I18n -> GroupMetadataSnapshot -> GroupMetadataSnapshot -> List (Ui.Element msg)
groupMetadataDiffRows i18n old new =
    List.filterMap identity
        [ if old.name /= new.name then
            Just (diffRow (T.changeFieldName i18n) old.name new.name)

          else
            Nothing
        , maybeDiffRow (T.changeFieldSubtitle i18n) old.subtitle new.subtitle
        , maybeDiffRow (T.groupSettingsDescription i18n) old.description new.description
        , if old.links /= new.links then
            Just (diffRow (T.changeFieldLinks i18n) (linksToString old.links) (linksToString new.links))

          else
            Nothing
        ]


linksToString : List { label : String, url : String } -> String
linksToString links =
    case links of
        [] ->
            "—"

        _ ->
            links
                |> List.map (\l -> l.label ++ " (" ++ l.url ++ ")")
                |> String.join ", "



-- ROW HELPERS


detailRow : String -> String -> Ui.Element msg
detailRow label value =
    Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
        [ Ui.el
            [ Ui.Font.size Theme.font.sm
            , Ui.Font.color Theme.base.textSubtle
            ]
            (Ui.text label)
        , Ui.el [ Ui.Font.size Theme.font.sm ] (Ui.text value)
        ]


diffRow : String -> String -> String -> Ui.Element msg
diffRow label oldValue newValue =
    Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
        [ Ui.el
            [ Ui.Font.size Theme.font.sm
            , Ui.Font.color Theme.base.textSubtle
            ]
            (Ui.text label)
        , Ui.row [ Ui.spacing Theme.spacing.sm ]
            [ Ui.el
                [ Ui.Font.size Theme.font.sm
                , Ui.Font.color Theme.danger.text
                , Ui.Font.strike
                ]
                (Ui.text oldValue)
            , Ui.el [ Ui.Font.size Theme.font.sm ] (Ui.text "→")
            , Ui.el
                [ Ui.Font.size Theme.font.sm
                , Ui.Font.color Theme.success.text
                ]
                (Ui.text newValue)
            ]
        ]



-- TIMESTAMP


formatTimestamp : Time.Posix -> String
formatTimestamp posix =
    let
        year : String
        year =
            String.fromInt (Time.toYear Time.utc posix)

        month : String
        month =
            String.padLeft 2 '0' (String.fromInt (monthToInt (Time.toMonth Time.utc posix)))

        day : String
        day =
            String.padLeft 2 '0' (String.fromInt (Time.toDay Time.utc posix))

        hour : String
        hour =
            String.padLeft 2 '0' (String.fromInt (Time.toHour Time.utc posix))

        minute : String
        minute =
            String.padLeft 2 '0' (String.fromInt (Time.toMinute Time.utc posix))
    in
    year ++ "-" ++ month ++ "-" ++ day ++ " " ++ hour ++ ":" ++ minute


monthToInt : Time.Month -> Int
monthToInt month =
    case month of
        Time.Jan ->
            1

        Time.Feb ->
            2

        Time.Mar ->
            3

        Time.Apr ->
            4

        Time.May ->
            5

        Time.Jun ->
            6

        Time.Jul ->
            7

        Time.Aug ->
            8

        Time.Sep ->
            9

        Time.Oct ->
            10

        Time.Nov ->
            11

        Time.Dec ->
            12
