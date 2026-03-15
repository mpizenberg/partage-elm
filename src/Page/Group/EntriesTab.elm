module Page.Group.EntriesTab exposing (Config, Model, Msg, Output(..), init, initWithHighlight, update, view)

{-| Entries tab showing expense and transfer cards with filtering
and inline expandable entry details.
-}

import Dict
import Domain.Currency as Currency
import Domain.Date as Date exposing (Date)
import Domain.Entry as Entry
import Domain.Filter as Filter exposing (CategoryFilter(..), DateRange(..), EntryFilters)
import Domain.GroupState as GroupState exposing (GroupState)
import Domain.Member as Member
import FeatherIcons
import Format
import Html
import Html.Attributes
import List.Extra
import Set exposing (Set)
import Time
import Translations as T exposing (I18n)
import UI.Components
import UI.Theme as Theme
import Ui
import Ui.Font
import Ui.Input


type Model
    = Model
        { filters : EntryFilters
        , showFilters : Bool
        , showDeleted : Bool
        , searchQuery : String
        , expandedEntries : Set Entry.Id
        , confirmingAction : Maybe ( Entry.Id, ConfirmAction )
        }


type ConfirmAction
    = ConfirmDelete
    | ConfirmRestore


type Msg
    = ToggleShowDeleted
    | ToggleFilters
    | TogglePerson Member.Id
    | ToggleCategory String
    | ToggleCurrency String
    | ToggleDateRange DateRange
    | ClearAllFilters
    | InputSearch String
    | ToggleEntry Entry.Id
    | ClickEdit Entry.Id
    | ClickDuplicate Entry.Id
    | ClickDelete Entry.Id
    | ClickRestore Entry.Id
    | Confirm
    | CancelConfirm


type Output
    = EditOutput Entry.Id
    | DuplicateOutput Entry.Id
    | DeleteOutput Entry.Id
    | RestoreOutput Entry.Id


{-| Callback messages for entry interactions on this tab.
-}
type alias Config msg =
    { onNewEntry : msg
    , newEntryHref : String
    , entryLinkHref : Entry.Id -> String
    , toMsg : Msg -> msg
    }


init : Model
init =
    Model
        { filters = Filter.emptyEntryFilters
        , showFilters = False
        , showDeleted = False
        , searchQuery = ""
        , expandedEntries = Set.empty
        , confirmingAction = Nothing
        }


{-| Initialize with a specific entry highlighted (expanded), resetting filters.
If the entry is deleted, showDeleted is turned on.
-}
initWithHighlight : Entry.Id -> Bool -> Model
initWithHighlight entryId isDeleted =
    Model
        { filters = Filter.emptyEntryFilters
        , showFilters = False
        , showDeleted = isDeleted
        , searchQuery = ""
        , expandedEntries = Set.singleton entryId
        , confirmingAction = Nothing
        }


update : Msg -> Model -> ( Model, Maybe Output )
update msg (Model data) =
    case msg of
        ToggleShowDeleted ->
            ( Model { data | showDeleted = not data.showDeleted }, Nothing )

        ToggleFilters ->
            ( Model { data | showFilters = not data.showFilters }, Nothing )

        TogglePerson memberId ->
            ( Model (updateFilters (\f -> { f | persons = toggleSet memberId f.persons }) data), Nothing )

        ToggleCategory catStr ->
            ( Model (updateFilters (\f -> { f | categories = toggleSet catStr f.categories }) data), Nothing )

        ToggleCurrency currStr ->
            ( Model (updateFilters (\f -> { f | currencies = toggleSet currStr f.currencies }) data), Nothing )

        ToggleDateRange range ->
            ( Model
                (updateFilters
                    (\f ->
                        if List.member range f.dateRanges then
                            { f | dateRanges = List.filter (\r -> r /= range) f.dateRanges }

                        else
                            { f | dateRanges = range :: f.dateRanges }
                    )
                    data
                )
            , Nothing
            )

        ClearAllFilters ->
            ( Model { data | filters = Filter.emptyEntryFilters, showDeleted = False }, Nothing )

        InputSearch query ->
            ( Model { data | searchQuery = query }, Nothing )

        ToggleEntry entryId ->
            ( Model
                { data
                    | expandedEntries =
                        if Set.member entryId data.expandedEntries then
                            Set.remove entryId data.expandedEntries

                        else
                            Set.insert entryId data.expandedEntries
                    , confirmingAction =
                        -- Clear confirm when collapsing
                        case data.confirmingAction of
                            Just ( id, _ ) ->
                                if id == entryId then
                                    Nothing

                                else
                                    data.confirmingAction

                            Nothing ->
                                Nothing
                }
            , Nothing
            )

        ClickEdit entryId ->
            ( Model data, Just (EditOutput entryId) )

        ClickDuplicate entryId ->
            ( Model data, Just (DuplicateOutput entryId) )

        ClickDelete entryId ->
            ( Model { data | confirmingAction = Just ( entryId, ConfirmDelete ) }, Nothing )

        ClickRestore entryId ->
            ( Model { data | confirmingAction = Just ( entryId, ConfirmRestore ) }, Nothing )

        Confirm ->
            case data.confirmingAction of
                Just ( entryId, ConfirmDelete ) ->
                    ( Model { data | confirmingAction = Nothing }, Just (DeleteOutput entryId) )

                Just ( entryId, ConfirmRestore ) ->
                    ( Model { data | confirmingAction = Nothing }, Just (RestoreOutput entryId) )

                Nothing ->
                    ( Model data, Nothing )

        CancelConfirm ->
            ( Model { data | confirmingAction = Nothing }, Nothing )


updateFilters : (EntryFilters -> EntryFilters) -> { a | filters : EntryFilters } -> { a | filters : EntryFilters }
updateFilters transform data =
    { data | filters = transform data.filters }


toggleSet : comparable -> Set comparable -> Set comparable
toggleSet item set =
    if Set.member item set then
        Set.remove item set

    else
        Set.insert item set


{-| Check if an entry matches a search query. Searches description, notes,
and involved member names. Empty query matches everything.
-}
matchesSearch : I18n -> (Member.Id -> String) -> String -> Entry.Entry -> Bool
matchesSearch i18n resolveName query entry =
    if String.isEmpty query then
        True

    else
        let
            q : String
            q =
                String.toLower query

            contains : String -> Bool
            contains text =
                String.contains q (String.toLower text)

            matchesMemberName : Member.Id -> Bool
            matchesMemberName memberId =
                contains (resolveName memberId)

            matchesCategory : Maybe Entry.Category -> Bool
            matchesCategory maybeCat =
                case maybeCat of
                    Just cat ->
                        contains (detailCategoryLabel i18n cat)

                    Nothing ->
                        False
        in
        case entry.kind of
            Entry.Expense data ->
                contains data.description
                    || Maybe.withDefault False (Maybe.map contains data.notes)
                    || matchesCategory data.category
                    || List.any (\p -> matchesMemberName p.memberId) data.payers
                    || List.any (beneficiaryMatchesSearch matchesMemberName) data.beneficiaries

            Entry.Transfer data ->
                contains (T.entryTransfer i18n)
                    || Maybe.withDefault False (Maybe.map contains data.notes)
                    || matchesMemberName data.from
                    || matchesMemberName data.to


beneficiaryMatchesSearch : (Member.Id -> Bool) -> Entry.Beneficiary -> Bool
beneficiaryMatchesSearch matchesMemberName beneficiary =
    case beneficiary of
        Entry.ShareBeneficiary r ->
            matchesMemberName r.memberId

        Entry.ExactBeneficiary r ->
            matchesMemberName r.memberId


{-| Render the entries tab with filtering, entry cards grouped by date, and a FAB.
-}
view : I18n -> Config msg -> Maybe Member.Id -> Date -> Model -> GroupState -> Ui.Element msg
view i18n config maybeUserRootId today (Model data) state =
    let
        allEntries : List { entry : Entry.Entry, isDeleted : Bool }
        allEntries =
            if data.showDeleted then
                Dict.values state.entries
                    |> List.map (\es -> { entry = es.currentVersion, isDeleted = es.isDeleted })

            else
                GroupState.activeEntries state
                    |> List.map (\e -> { entry = e, isDeleted = False })

        resolveName : Member.Id -> String
        resolveName =
            GroupState.resolveMemberName state

        visibleEntries : List { entry : Entry.Entry, isDeleted : Bool }
        visibleEntries =
            allEntries
                |> List.filter (\{ entry } -> Filter.matchesEntryFilters today data.filters entry)
                |> List.filter (\{ entry } -> matchesSearch i18n resolveName data.searchQuery entry)
                |> List.sortBy (\{ entry } -> entrySortKey entry)

        totalAmount : Int
        totalAmount =
            visibleEntries
                |> List.map
                    (\{ entry } ->
                        case entry.kind of
                            Entry.Expense d ->
                                d.amount

                            Entry.Transfer d ->
                                d.amount
                    )
                |> List.sum

        toMsg : Msg -> msg
        toMsg =
            config.toMsg
    in
    Ui.column [ Ui.spacing Theme.spacing.md, Ui.width Ui.fill ]
        [ -- Summary row
          summaryRow (List.length visibleEntries) totalAmount

        -- New Entry button (hidden in read-only mode)
        , if maybeUserRootId /= Nothing then
            Ui.el [ Ui.paddingXY 0 Theme.spacing.lg ] <|
                UI.Components.btnPrimary
                    (UI.Components.spaLinkAttrs config.newEntryHref config.onNewEntry)
                    { label = T.newEntryTitle i18n, onPress = config.onNewEntry }

          else
            Ui.none

        -- Search bar + filter button
        , searchFilterRow i18n data.showFilters (Filter.isEntryFilterActive data.filters || data.showDeleted) data.searchQuery |> Ui.map toMsg

        -- Filter panel or active filter summary
        , if data.showFilters then
            filterPanel i18n data.filters data.showDeleted state |> Ui.map toMsg

          else if Filter.isEntryFilterActive data.filters || data.showDeleted then
            activeFilterSummary i18n data.filters data.showDeleted state

          else
            Ui.none

        -- Entry list grouped by date
        , if List.isEmpty visibleEntries then
            Ui.el [ Ui.Font.size Theme.font.sm, Ui.Font.color Theme.base.textSubtle ]
                (Ui.text (T.entriesNone i18n))

          else
            Ui.column [ Ui.width Ui.fill, Ui.spacing Theme.spacing.sm ]
                (groupedByDate i18n (maybeUserRootId /= Nothing) resolveName config.entryLinkHref data.expandedEntries data.confirmingAction visibleEntries)
                |> Ui.map toMsg
        ]



-- SEARCH BAR
-- SUMMARY ROW


summaryRow : Int -> Int -> Ui.Element msg
summaryRow entryCount totalAmount =
    Ui.el
        [ Ui.Font.size Theme.font.sm
        , Ui.Font.color Theme.base.textSubtle
        ]
        (Ui.text (String.fromInt entryCount ++ " entries · " ++ Format.formatCents totalAmount ++ " total"))



-- SEARCH BAR + FILTER BUTTON


searchFilterRow : I18n -> Bool -> Bool -> String -> Ui.Element Msg
searchFilterRow i18n showFilters hasActiveFilters query =
    Ui.row [ Ui.width Ui.fill, Ui.spacing Theme.spacing.sm, Ui.contentCenterY ]
        [ Ui.row
            [ Ui.width Ui.fill
            , Ui.paddingXY Theme.spacing.md Theme.spacing.sm
            , Ui.spacing Theme.spacing.sm
            , Ui.border Theme.border
            , Ui.borderColor Theme.base.accent
            , Ui.rounded Theme.radius.md
            , Ui.background (Ui.rgb 255 255 255)
            , Ui.contentCenterY
            ]
            [ Ui.el [ Ui.Font.color Theme.base.textSubtle, Ui.width Ui.shrink ]
                (UI.Components.featherIcon 18 FeatherIcons.search)
            , Ui.Input.text
                [ Ui.width Ui.fill
                , Ui.padding 0
                , Ui.border 0
                , Ui.Font.size Theme.font.md
                ]
                { onChange = InputSearch
                , text = query
                , placeholder = Just (T.entriesSearchLabel i18n ++ "...")
                , label = Ui.Input.labelHidden (T.entriesSearchLabel i18n)
                }
            ]
        , UI.Components.filterToggleButton
            { showFilters = showFilters
            , hasActiveFilters = hasActiveFilters
            , onPress = ToggleFilters
            }
        ]



-- ACTIVE FILTER SUMMARY


activeFilterSummary : I18n -> EntryFilters -> Bool -> GroupState -> Ui.Element msg
activeFilterSummary i18n filters showDeleted state =
    let
        resolveName : Member.Id -> String
        resolveName =
            GroupState.resolveMemberName state

        personChips : List (Ui.Element msg)
        personChips =
            Set.toList filters.persons
                |> List.map (\id -> UI.Components.filterSummaryChip (T.filterPersonLabel i18n) (resolveName id))

        categoryChips : List (Ui.Element msg)
        categoryChips =
            Set.toList filters.categories
                |> List.map (UI.Components.filterSummaryChip (T.filterCategoryLabel i18n))

        currencyChips : List (Ui.Element msg)
        currencyChips =
            Set.toList filters.currencies
                |> List.map (UI.Components.filterSummaryChip (T.filterCurrencyLabel i18n))

        dateChips : List (Ui.Element msg)
        dateChips =
            List.map (\r -> UI.Components.filterSummaryChip (T.filterDateLabel i18n) (dateRangeLabel i18n r)) filters.dateRanges

        deletedChip : List (Ui.Element msg)
        deletedChip =
            if showDeleted then
                [ UI.Components.filterSummaryChip (T.filterSectionTitle i18n) (T.entriesShowDeleted "" i18n) ]

            else
                []
    in
    Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
        [ UI.Components.sectionLabel (T.filterSectionTitle i18n)
        , Ui.row [ Ui.wrap, Ui.spacing Theme.spacing.xs ]
            (List.concat [ personChips, categoryChips, currencyChips, dateChips, deletedChip ])
        ]


dateRangeLabel : I18n -> DateRange -> String
dateRangeLabel i18n range =
    case range of
        Today ->
            T.filterDateToday i18n

        Yesterday ->
            T.filterDateYesterday i18n

        Last7Days ->
            T.filterDateLast7 i18n

        Last30Days ->
            T.filterDateLast30 i18n

        ThisMonth ->
            T.filterDateThisMonth i18n

        LastMonth ->
            T.filterDateLastMonth i18n



-- FILTER PANEL


filterPanel : I18n -> EntryFilters -> Bool -> GroupState -> Ui.Element Msg
filterPanel i18n filters showDeleted state =
    let
        deletedCount : Int
        deletedCount =
            Dict.size <| Dict.filter (\_ entry -> entry.isDeleted) state.entries
    in
    UI.Components.card [ Ui.padding Theme.spacing.lg ]
        [ personFilterSection i18n filters.persons state
        , categoryFilterSection i18n filters.categories
        , currencyFilterSection i18n filters.currencies state
        , dateFilterSection i18n filters.dateRanges

        -- Deleted entries toggle
        , Ui.row
            [ Ui.width Ui.fill
            , Ui.contentCenterY
            , Ui.paddingTop Theme.spacing.sm
            ]
            [ Ui.el
                [ Ui.Font.size Theme.font.sm
                , Ui.Font.color Theme.base.textSubtle
                ]
                (Ui.text (T.entriesShowDeleted (String.fromInt deletedCount) i18n))
            , UI.Components.toggle { isOn = showDeleted, onPress = ToggleShowDeleted }
            ]

        -- Clear all
        , if Filter.isEntryFilterActive filters then
            UI.Components.clearAllFiltersButton i18n ClearAllFilters

          else
            Ui.none
        ]


personFilterSection : I18n -> Set Member.Id -> GroupState -> Ui.Element Msg
personFilterSection i18n selected state =
    let
        members : List ( Member.Id, String )
        members =
            GroupState.activeMembers state
                |> List.map (\m -> ( m.rootId, m.name ))
                |> List.sortBy Tuple.second
    in
    UI.Components.filterSection (T.filterPersonLabel i18n)
        (List.map
            (\( id, name ) ->
                UI.Components.chip { label = name, selected = Set.member id selected, onPress = TogglePerson id }
            )
            members
        )


categoryFilterSection : I18n -> Set String -> Ui.Element Msg
categoryFilterSection i18n selected =
    let
        allCategories : List ( String, String )
        allCategories =
            [ ( Filter.categoryFilterToString TransferCategory, "💸 " ++ T.filterCategoryTransfer i18n )
            , ( Filter.categoryFilterToString (ExpenseCategory Entry.Food), "🍽️ " ++ T.categoryFood i18n )
            , ( Filter.categoryFilterToString (ExpenseCategory Entry.Transport), "🚗 " ++ T.categoryTransport i18n )
            , ( Filter.categoryFilterToString (ExpenseCategory Entry.Accommodation), "🏠 " ++ T.categoryAccommodation i18n )
            , ( Filter.categoryFilterToString (ExpenseCategory Entry.Entertainment), "🎭 " ++ T.categoryEntertainment i18n )
            , ( Filter.categoryFilterToString (ExpenseCategory Entry.Shopping), "🛍️ " ++ T.categoryShopping i18n )
            , ( Filter.categoryFilterToString (ExpenseCategory Entry.Groceries), "🛒 " ++ T.categoryGroceries i18n )
            , ( Filter.categoryFilterToString (ExpenseCategory Entry.Utilities), "⚡ " ++ T.categoryUtilities i18n )
            , ( Filter.categoryFilterToString (ExpenseCategory Entry.Healthcare), "💊 " ++ T.categoryHealthcare i18n )
            , ( Filter.categoryFilterToString (ExpenseCategory Entry.Other), "📦 " ++ T.categoryOther i18n )
            ]
    in
    UI.Components.filterSection (T.filterCategoryLabel i18n)
        (List.map
            (\( key, label ) ->
                UI.Components.chip { label = label, selected = Set.member key selected, onPress = ToggleCategory key }
            )
            allCategories
        )


currencyFilterSection : I18n -> Set String -> GroupState -> Ui.Element Msg
currencyFilterSection i18n selected state =
    let
        usedCurrencies : List String
        usedCurrencies =
            Dict.values state.entries
                |> List.map
                    (\es ->
                        case es.currentVersion.kind of
                            Entry.Expense data ->
                                Currency.currencyCode data.currency

                            Entry.Transfer data ->
                                Currency.currencyCode data.currency
                    )
                |> Set.fromList
                |> Set.toList
    in
    UI.Components.filterSection (T.filterCurrencyLabel i18n)
        (List.map
            (\code ->
                UI.Components.chip { label = code, selected = Set.member code selected, onPress = ToggleCurrency code }
            )
            usedCurrencies
        )


dateFilterSection : I18n -> List DateRange -> Ui.Element Msg
dateFilterSection i18n activeRanges =
    let
        presets : List ( DateRange, String )
        presets =
            [ ( Today, T.filterDateToday i18n )
            , ( Yesterday, T.filterDateYesterday i18n )
            , ( Last7Days, T.filterDateLast7 i18n )
            , ( Last30Days, T.filterDateLast30 i18n )
            , ( ThisMonth, T.filterDateThisMonth i18n )
            , ( LastMonth, T.filterDateLastMonth i18n )
            ]
    in
    UI.Components.filterSection (T.filterDateLabel i18n)
        (List.map
            (\( range, label ) ->
                UI.Components.chip { label = label, selected = List.member range activeRanges, onPress = ToggleDateRange range }
            )
            presets
        )



-- DATE GROUPING


groupedByDate : I18n -> Bool -> (Member.Id -> String) -> (Entry.Id -> String) -> Set Entry.Id -> Maybe ( Entry.Id, ConfirmAction ) -> List { entry : Entry.Entry, isDeleted : Bool } -> List (Ui.Element Msg)
groupedByDate i18n isMember resolveName entryLinkHref expandedEntries confirmingAction entries =
    let
        getDate : Entry.Entry -> Date
        getDate entry =
            case entry.kind of
                Entry.Expense data ->
                    data.date

                Entry.Transfer data ->
                    data.date

        groupEntries : List { entry : Entry.Entry, isDeleted : Bool } -> List ( Date, List { entry : Entry.Entry, isDeleted : Bool } )
        groupEntries items =
            List.Extra.groupWhile (\e1 e2 -> getDate e1.entry == getDate e2.entry) items
                |> List.map (\( e1, es ) -> ( getDate e1.entry, e1 :: es ))
    in
    groupEntries entries
        |> List.concatMap
            (\( date, group ) ->
                dateSeparator i18n date
                    :: List.map (entryCardView i18n isMember resolveName entryLinkHref expandedEntries confirmingAction) group
            )


dateSeparator : I18n -> Date -> Ui.Element msg
dateSeparator i18n date =
    Ui.el
        [ Ui.paddingTop Theme.spacing.md
        , Ui.Font.size Theme.font.xs
        , Ui.Font.weight Theme.fontWeight.semibold
        , Ui.Font.letterSpacing Theme.letterSpacing.wide
        , Ui.Font.color Theme.base.textSubtle
        ]
        (Ui.text (String.toUpper (formatDate i18n date)))



-- ENTRY CARD


entryCardView : I18n -> Bool -> (Member.Id -> String) -> (Entry.Id -> String) -> Set Entry.Id -> Maybe ( Entry.Id, ConfirmAction ) -> { entry : Entry.Entry, isDeleted : Bool } -> Ui.Element Msg
entryCardView i18n isMember resolveName entryLinkHref expandedEntries confirmingAction { entry, isDeleted } =
    let
        entryId : Entry.Id
        entryId =
            entry.meta.rootId

        isExpanded : Bool
        isExpanded =
            Set.member entryId expandedEntries

        headerEl : Ui.Element Msg
        headerEl =
            case entry.kind of
                Entry.Expense data ->
                    expenseCardHeader i18n resolveName data

                Entry.Transfer data ->
                    transferCardHeader i18n resolveName data

        cardEl : Ui.Element Msg
        cardEl =
            UI.Components.card
                [ Ui.paddingXY Theme.spacing.lg Theme.spacing.md
                , Ui.id (entryDomId entryId)
                ]
                [ Ui.el [ Ui.Input.button (ToggleEntry entryId), Ui.pointer ]
                    headerEl
                , if isExpanded then
                    entryDetail i18n isMember resolveName (entryLinkHref entryId) entryId entry isDeleted confirmingAction

                  else
                    Ui.none
                ]
    in
    if isDeleted then
        Ui.el [ Ui.opacity 0.5 ] cardEl

    else
        cardEl


{-| DOM id for an entry card element. Must match Page.Group.entryDomId.
-}
entryDomId : Entry.Id -> String
entryDomId entryId =
    "entry-" ++ entryId


expenseCardHeader : I18n -> (Member.Id -> String) -> Entry.ExpenseData -> Ui.Element msg
expenseCardHeader i18n resolveName data =
    Ui.column [ Ui.width Ui.fill ]
        [ -- Top row: description + amount
          Ui.row [ Ui.width Ui.fill ]
            [ Ui.el
                [ Ui.Font.weight Theme.fontWeight.semibold
                , Ui.Font.size Theme.font.md
                ]
                (Ui.text data.description)
            , Ui.el
                [ Ui.alignRight
                , Ui.Font.weight Theme.fontWeight.bold
                , Ui.Font.size Theme.font.md
                , Ui.Font.letterSpacing Theme.letterSpacing.tight
                ]
                (Ui.text (Format.formatCentsWithCurrency data.amount data.currency))
            ]

        -- Meta row: date + category tag
        , Ui.row
            [ Ui.spacing Theme.spacing.xs
            , Ui.paddingTop Theme.spacing.xs
            , Ui.contentCenterY
            , Ui.Font.size Theme.font.sm
            , Ui.Font.color Theme.base.textSubtle
            ]
            [ Ui.el [ Ui.width Ui.shrink ] (Ui.text (formatShortDate i18n data.date))
            , case data.category of
                Just cat ->
                    entryTag (categoryLabel i18n cat)

                Nothing ->
                    Ui.none

            -- Flow: payer → recipients
            , Ui.row
                [ Ui.spacing Theme.spacing.xs
                , Ui.width Ui.shrink
                , Ui.contentCenterY
                , Ui.alignRight
                ]
                [ Ui.text (payerText resolveName data.payers)
                , Ui.el [ Ui.Font.color Theme.base.textSubtle ] (Ui.text "→")
                , Ui.text (recipientText resolveName data.beneficiaries)
                ]
            ]
        ]


transferCardHeader : I18n -> (Member.Id -> String) -> Entry.TransferData -> Ui.Element msg
transferCardHeader i18n resolveName data =
    Ui.column [ Ui.width Ui.fill ]
        [ -- Top row: "Transfer" + amount
          Ui.row [ Ui.width Ui.fill ]
            [ Ui.el
                [ Ui.Font.weight Theme.fontWeight.semibold
                , Ui.Font.size Theme.font.md
                ]
                (Ui.text (T.entryTransfer i18n))
            , Ui.el
                [ Ui.alignRight
                , Ui.Font.weight Theme.fontWeight.bold
                , Ui.Font.size Theme.font.md
                , Ui.Font.letterSpacing Theme.letterSpacing.tight
                ]
                (Ui.text (Format.formatCentsWithCurrency data.amount data.currency))
            ]

        -- Meta row: date + transfer tag + flow from->to
        , Ui.row
            [ Ui.spacing Theme.spacing.xs
            , Ui.paddingTop Theme.spacing.xs
            , Ui.Font.color Theme.base.textSubtle
            , Ui.Font.size Theme.font.sm
            , Ui.contentCenterY
            ]
            [ Ui.el [ Ui.width Ui.shrink ] (Ui.text (formatShortDate i18n data.date))
            , entryTag ("💸 " ++ T.filterCategoryTransfer i18n)

            -- Flow: from → to
            , Ui.row
                [ Ui.spacing Theme.spacing.xs
                , Ui.width Ui.shrink
                , Ui.contentCenterY
                , Ui.alignRight
                ]
                [ Ui.text (resolveName data.from)
                , Ui.el [ Ui.Font.color Theme.base.textSubtle ] (Ui.text "→")
                , Ui.text (resolveName data.to)
                ]
            ]
        ]


entryTag : String -> Ui.Element msg
entryTag label =
    Ui.el
        [ Ui.Font.size Theme.font.xs
        , Ui.Font.weight Theme.fontWeight.semibold
        , Ui.paddingXY Theme.spacing.sm Theme.spacing.xs
        , Ui.rounded Theme.radius.md
        , Ui.background Theme.base.tint
        , Ui.Font.color Theme.base.textSubtle
        , Ui.width Ui.shrink
        ]
        (Ui.text label)


categoryLabel : I18n -> Entry.Category -> String
categoryLabel i18n cat =
    case cat of
        Entry.Food ->
            "🍽️ " ++ T.categoryFood i18n

        Entry.Transport ->
            "🚗 " ++ T.categoryTransport i18n

        Entry.Accommodation ->
            "🏠 " ++ T.categoryAccommodation i18n

        Entry.Entertainment ->
            "🎭 " ++ T.categoryEntertainment i18n

        Entry.Shopping ->
            "🛍️ " ++ T.categoryShopping i18n

        Entry.Groceries ->
            "🛒 " ++ T.categoryGroceries i18n

        Entry.Utilities ->
            "⚡ " ++ T.categoryUtilities i18n

        Entry.Healthcare ->
            "💊 " ++ T.categoryHealthcare i18n

        Entry.Other ->
            "📦 " ++ T.categoryOther i18n


payerText : (Member.Id -> String) -> List Entry.Payer -> String
payerText resolveName payers =
    case payers of
        [] ->
            ""

        [ single ] ->
            resolveName single.memberId

        multiple ->
            String.join ", " (List.map (.memberId >> resolveName) multiple)


recipientText : (Member.Id -> String) -> List Entry.Beneficiary -> String
recipientText resolveName beneficiaries =
    case beneficiaries of
        [] ->
            ""

        [ single ] ->
            case single of
                Entry.ShareBeneficiary { memberId } ->
                    resolveName memberId

                Entry.ExactBeneficiary { memberId } ->
                    resolveName memberId

        _ ->
            let
                names : List String
                names =
                    List.map
                        (\b ->
                            case b of
                                Entry.ShareBeneficiary { memberId } ->
                                    resolveName memberId

                                Entry.ExactBeneficiary { memberId } ->
                                    resolveName memberId
                        )
                        beneficiaries
            in
            case names of
                first :: rest ->
                    first ++ " +" ++ String.fromInt (List.length rest)

                [] ->
                    ""



-- ENTRY DETAIL (expanded)


entryDetail : I18n -> Bool -> (Member.Id -> String) -> String -> Entry.Id -> Entry.Entry -> Bool -> Maybe ( Entry.Id, ConfirmAction ) -> Ui.Element Msg
entryDetail i18n isMember resolveName linkHref entryId entry isDeleted confirmingAction =
    Ui.column
        [ Ui.paddingTop Theme.spacing.md
        , Ui.spacing Theme.spacing.md
        ]
        [ entryContent i18n resolveName entry
        , if isMember then
            Ui.row [ Ui.spacing Theme.spacing.sm ]
                [ copyLinkBtn linkHref (T.entryDetailCopyLink i18n)
                , UI.Components.btnOutline [ Ui.width Ui.shrink ]
                    { label = T.entryDetailDuplicateButton i18n
                    , icon = Just (UI.Components.featherIcon 16 FeatherIcons.copy)
                    , onPress = ClickDuplicate entryId
                    }
                ]

          else
            Ui.none
        , if isMember then
            actionButtons i18n
                entryId
                isDeleted
                (case confirmingAction of
                    Just ( id, action ) ->
                        if id == entryId then
                            Just action

                        else
                            Nothing

                    Nothing ->
                        Nothing
                )

          else
            Ui.none
        ]


entryContent : I18n -> (Member.Id -> String) -> Entry.Entry -> Ui.Element msg
entryContent i18n resolveName entry =
    case entry.kind of
        Entry.Expense data ->
            expenseContent i18n resolveName data

        Entry.Transfer data ->
            transferContent i18n resolveName data


expenseContent : I18n -> (Member.Id -> String) -> Entry.ExpenseData -> Ui.Element msg
expenseContent i18n resolveName data =
    Ui.column [ Ui.spacing Theme.spacing.md, Ui.width Ui.fill ]
        (List.concat
            [ [ detailRow (T.newEntryDescriptionLabel i18n) data.description
              , detailRow (T.entryDetailDate i18n) (Date.toString data.date)
              , detailRow (T.newEntryAmountLabel i18n) (Format.formatCentsWithCurrency data.amount data.currency)
              ]
            , defaultCurrencyAmountRow data.defaultCurrencyAmount
            , [ detailRow (T.entryDetailPaidBy i18n) (payerNames resolveName data.payers)
              , beneficiariesSection i18n resolveName data.beneficiaries
              ]
            , detailCategoryRow i18n data.category
            , optionalRow (T.entryDetailNotes i18n) data.notes
            ]
        )


transferContent : I18n -> (Member.Id -> String) -> Entry.TransferData -> Ui.Element msg
transferContent i18n resolveName data =
    Ui.column [ Ui.spacing Theme.spacing.md, Ui.width Ui.fill ]
        (List.concat
            [ [ detailRow (T.entryDetailDate i18n) (Date.toString data.date)
              , detailRow (T.newEntryAmountLabel i18n) (Format.formatCentsWithCurrency data.amount data.currency)
              ]
            , defaultCurrencyAmountRow data.defaultCurrencyAmount
            , [ detailRow (T.entryDetailFrom i18n) (resolveName data.from)
              , detailRow (T.entryDetailTo i18n) (resolveName data.to)
              ]
            , optionalRow (T.entryDetailNotes i18n) data.notes
            ]
        )


defaultCurrencyAmountRow : Maybe Int -> List (Ui.Element msg)
defaultCurrencyAmountRow maybeAmount =
    case maybeAmount of
        Just amount ->
            [ Ui.el
                [ Ui.Font.size Theme.font.sm
                , Ui.Font.color Theme.base.textSubtle
                ]
                (Ui.text ("≈ " ++ Format.formatCents amount))
            ]

        Nothing ->
            []


detailRow : String -> String -> Ui.Element msg
detailRow label value =
    Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
        [ Ui.el
            [ Ui.Font.size Theme.font.sm
            , Ui.Font.color Theme.base.textSubtle
            ]
            (Ui.text label)
        , Ui.el
            [ Ui.Font.size Theme.font.md
            , Ui.Font.weight Theme.fontWeight.medium
            ]
            (Ui.text value)
        ]


optionalRow : String -> Maybe String -> List (Ui.Element msg)
optionalRow label maybeValue =
    case maybeValue of
        Just value ->
            [ detailRow label value ]

        Nothing ->
            []


payerNames : (Member.Id -> String) -> List Entry.Payer -> String
payerNames resolveName payers =
    payers
        |> List.map (\p -> resolveName p.memberId)
        |> String.join ", "


beneficiariesSection : I18n -> (Member.Id -> String) -> List Entry.Beneficiary -> Ui.Element msg
beneficiariesSection i18n resolveName beneficiaries =
    Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
        [ Ui.el
            [ Ui.Font.size Theme.font.sm
            , Ui.Font.color Theme.base.textSubtle
            ]
            (Ui.text (T.entryDetailSplitAmong i18n))
        , Ui.row [ Ui.spacing Theme.spacing.sm, Ui.wrap ]
            (List.map (beneficiaryItem resolveName) beneficiaries
                |> List.intersperse (Ui.text "·")
            )
        ]


beneficiaryItem : (Member.Id -> String) -> Entry.Beneficiary -> Ui.Element msg
beneficiaryItem resolveName beneficiary =
    case beneficiary of
        Entry.ShareBeneficiary data ->
            Ui.row [ Ui.spacing Theme.spacing.sm, Ui.width Ui.shrink ]
                [ Ui.el [ Ui.Font.size Theme.font.md ] (Ui.text (resolveName data.memberId))
                , if data.shares > 1 then
                    Ui.el
                        [ Ui.Font.size Theme.font.sm
                        , Ui.Font.color Theme.base.textSubtle
                        ]
                        (Ui.text ("×" ++ String.fromInt data.shares))

                  else
                    Ui.none
                ]

        Entry.ExactBeneficiary data ->
            Ui.row [ Ui.spacing Theme.spacing.sm, Ui.width Ui.shrink ]
                [ Ui.el [ Ui.Font.size Theme.font.md ] (Ui.text (resolveName data.memberId))
                , Ui.el
                    [ Ui.Font.size Theme.font.sm
                    , Ui.Font.color Theme.base.textSubtle
                    , Ui.alignBottom
                    ]
                    (Ui.text (Format.formatCents data.amount))
                ]


detailCategoryRow : I18n -> Maybe Entry.Category -> List (Ui.Element msg)
detailCategoryRow i18n maybeCategory =
    case maybeCategory of
        Just category ->
            [ detailRow (T.entryDetailCategory i18n) (detailCategoryLabel i18n category) ]

        Nothing ->
            []


detailCategoryLabel : I18n -> Entry.Category -> String
detailCategoryLabel i18n category =
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


actionButtons : I18n -> Entry.Id -> Bool -> Maybe ConfirmAction -> Ui.Element Msg
actionButtons i18n entryId isDeleted confirmAction =
    case confirmAction of
        Just ConfirmDelete ->
            confirmSection i18n
                { warning = T.entryDeleteWarning i18n
                , confirmLabel = T.entryDeleteConfirm i18n
                , confirmIcon = FeatherIcons.trash2
                , bgColor = Theme.danger.solid
                , textColor = Theme.danger.solidText
                }

        Just ConfirmRestore ->
            confirmSection i18n
                { warning = T.entryRestoreWarning i18n
                , confirmLabel = T.entryRestoreConfirm i18n
                , confirmIcon = FeatherIcons.rotateCcw
                , bgColor = Theme.success.solid
                , textColor = Theme.success.solidText
                }

        Nothing ->
            defaultButtons i18n entryId isDeleted


confirmSection : I18n -> { warning : String, confirmLabel : String, confirmIcon : FeatherIcons.Icon, bgColor : Ui.Color, textColor : Ui.Color } -> Ui.Element Msg
confirmSection i18n config =
    Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
        [ Ui.el
            [ Ui.width Ui.fill
            , Ui.padding Theme.spacing.md
            , Ui.rounded Theme.radius.md
            , Ui.background Theme.danger.tint
            , Ui.Font.color Theme.danger.text
            , Ui.Font.size Theme.font.sm
            ]
            (Ui.text config.warning)
        , Ui.row [ Ui.spacing Theme.spacing.sm ]
            [ Ui.row
                [ Ui.Input.button Confirm
                , Ui.width Ui.fill
                , Ui.spacing Theme.spacing.sm
                , Ui.contentCenterX
                , Ui.contentCenterY
                , Ui.padding Theme.spacing.md
                , Ui.rounded Theme.radius.md
                , Ui.background config.bgColor
                , Ui.Font.color config.textColor
                , Ui.Font.weight Theme.fontWeight.semibold
                , Ui.pointer
                ]
                [ UI.Components.featherIcon 16 config.confirmIcon
                , Ui.text config.confirmLabel
                ]
            , UI.Components.btnOutline [] { label = T.memberRenameCancel i18n, icon = Nothing, onPress = CancelConfirm }
            ]
        ]


defaultButtons : I18n -> Entry.Id -> Bool -> Ui.Element Msg
defaultButtons i18n entryId isDeleted =
    Ui.row [ Ui.spacing Theme.spacing.sm ]
        [ UI.Components.btnOutline []
            { label = T.entryDetailEditButton i18n
            , icon = Just (UI.Components.featherIcon 16 FeatherIcons.edit)
            , onPress = ClickEdit entryId
            }
        , if isDeleted then
            UI.Components.btnSuccess []
                { label = T.entryDetailRestoreButton i18n
                , icon = FeatherIcons.rotateCcw
                , onPress = ClickRestore entryId
                }

          else
            UI.Components.btnDanger []
                { label = T.entryDetailDeleteButton i18n
                , icon = FeatherIcons.trash2
                , onPress = ClickDelete entryId
                }
        ]



-- COPY LINK BUTTON


{-| Copy-to-clipboard button using the copy-button web component.
-}
copyLinkBtn : String -> String -> Ui.Element msg
copyLinkBtn copyText label =
    Ui.row
        (Ui.width Ui.shrink
            :: Ui.inFront
                (Ui.html
                    (Html.node "copy-button"
                        [ Html.Attributes.attribute "data-copy" copyText
                        , Html.Attributes.style "display" "block"
                        , Html.Attributes.style "width" "100%"
                        , Html.Attributes.style "height" "100%"
                        , Html.Attributes.style "cursor" "pointer"
                        ]
                        []
                    )
                )
            :: UI.Components.btnOutlineAttrs
        )
        [ UI.Components.featherIcon 16 FeatherIcons.link
        , Ui.text label
        ]



-- SORT KEY


entrySortKey : Entry.Entry -> ( Int, Int, String )
entrySortKey entry =
    let
        d : Date
        d =
            case entry.kind of
                Entry.Expense data ->
                    data.date

                Entry.Transfer data ->
                    data.date
    in
    ( -(d.year * 10000 + d.month * 100 + d.day)
    , -(Time.posixToMillis entry.meta.createdAt)
    , entry.meta.id
    )



-- DATE FORMATTING HELPERS


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


shortMonthName : I18n -> Int -> String
shortMonthName i18n m =
    case m of
        1 ->
            T.monthShortJan i18n

        2 ->
            T.monthShortFeb i18n

        3 ->
            T.monthShortMar i18n

        4 ->
            T.monthShortApr i18n

        5 ->
            T.monthShortMay i18n

        6 ->
            T.monthShortJun i18n

        7 ->
            T.monthShortJul i18n

        8 ->
            T.monthShortAug i18n

        9 ->
            T.monthShortSep i18n

        10 ->
            T.monthShortOct i18n

        11 ->
            T.monthShortNov i18n

        12 ->
            T.monthShortDec i18n

        _ ->
            ""


formatDate : I18n -> Date -> String
formatDate i18n date =
    monthName i18n date.month ++ " " ++ String.fromInt date.day ++ ", " ++ String.fromInt date.year


formatShortDate : I18n -> Date -> String
formatShortDate i18n date =
    shortMonthName i18n date.month ++ " " ++ String.fromInt date.day
