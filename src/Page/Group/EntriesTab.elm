module Page.Group.EntriesTab exposing (Config, Model, Msg, init, update, view)

{-| Entries tab showing expense and transfer cards with filtering.
-}

import Dict
import Domain.Currency as Currency
import Domain.Date exposing (Date)
import Domain.Entry as Entry
import Domain.Filter as Filter exposing (CategoryFilter(..), DateRange(..), EntryFilters)
import Domain.GroupState as GroupState exposing (GroupState)
import Domain.Member as Member
import Set exposing (Set)
import Time
import Translations as T exposing (I18n)
import UI.Components
import UI.Theme as Theme
import Ui
import Ui.Events
import Ui.Font
import Ui.Input


type Model
    = Model
        { filters : EntryFilters
        , showFilters : Bool
        , showDeleted : Bool
        }


type Msg
    = ToggleShowDeleted
    | ToggleFilters
    | TogglePerson Member.Id
    | ToggleCategory String
    | ToggleCurrency String
    | ToggleDateRange DateRange
    | ClearAllFilters


{-| Callback messages for entry interactions on this tab.
-}
type alias Config msg =
    { onNewEntry : msg
    , onEntryClick : Entry.Id -> msg
    , toMsg : Msg -> msg
    }


init : Model
init =
    Model
        { filters = Filter.emptyEntryFilters
        , showFilters = False
        , showDeleted = False
        }


update : Msg -> Model -> Model
update msg (Model data) =
    case msg of
        ToggleShowDeleted ->
            Model { data | showDeleted = not data.showDeleted }

        ToggleFilters ->
            Model { data | showFilters = not data.showFilters }

        TogglePerson memberId ->
            Model (updateFilters (\f -> { f | persons = toggleSet memberId f.persons }) data)

        ToggleCategory catStr ->
            Model (updateFilters (\f -> { f | categories = toggleSet catStr f.categories }) data)

        ToggleCurrency currStr ->
            Model (updateFilters (\f -> { f | currencies = toggleSet currStr f.currencies }) data)

        ToggleDateRange range ->
            Model
                (updateFilters
                    (\f ->
                        if List.member range f.dateRanges then
                            { f | dateRanges = List.filter (\r -> r /= range) f.dateRanges }

                        else
                            { f | dateRanges = range :: f.dateRanges }
                    )
                    data
                )

        ClearAllFilters ->
            Model { data | filters = Filter.emptyEntryFilters }


updateFilters : (EntryFilters -> EntryFilters) -> { a | filters : EntryFilters } -> { a | filters : EntryFilters }
updateFilters transform data =
    { data | filters = transform data.filters }


toggleSet : comparable -> Set comparable -> Set comparable
toggleSet item set =
    if Set.member item set then
        Set.remove item set

    else
        Set.insert item set


{-| Render the entries tab with filtering, expense/transfer cards, and a new entry button.
-}
view : I18n -> Config msg -> Date -> Model -> GroupState -> Ui.Element msg
view i18n config today (Model data) state =
    let
        deletedCount : Int
        deletedCount =
            Dict.values state.entries
                |> List.filter .isDeleted
                |> List.length

        visibleEntries : List { entry : Entry.Entry, isDeleted : Bool }
        visibleEntries =
            (if data.showDeleted then
                Dict.values state.entries
                    |> List.map (\es -> { entry = es.currentVersion, isDeleted = es.isDeleted })

             else
                GroupState.activeEntries state
                    |> List.map (\e -> { entry = e, isDeleted = False })
            )
                |> List.filter (\{ entry } -> Filter.matchesEntryFilters today data.filters entry)
                |> List.sortBy (\{ entry } -> entrySortKey entry)
    in
    Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.lg, Ui.Font.bold ] (Ui.text (T.entriesTabTitle i18n))
        , if deletedCount > 0 then
            deletedToggle i18n data.showDeleted deletedCount (config.toMsg ToggleShowDeleted)

          else
            Ui.none
        , filterToggle i18n config.toMsg data.showFilters data.filters
        , if data.showFilters then
            filterBar i18n config.toMsg data.filters state

          else
            Ui.none
        , if List.isEmpty visibleEntries then
            Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ]
                (Ui.text (T.entriesNone i18n))

          else
            let
                resolveName : Member.Id -> String
                resolveName =
                    GroupState.resolveMemberName state
            in
            Ui.column [ Ui.width Ui.fill ]
                (List.map (entryRow i18n resolveName config.onEntryClick) visibleEntries)
        , newEntryButton i18n config.onNewEntry
        ]


filterToggle : I18n -> (Msg -> msg) -> Bool -> EntryFilters -> Ui.Element msg
filterToggle i18n toMsg showFilters filters =
    let
        label : String
        label =
            if showFilters then
                T.filterToggleHide i18n

            else
                T.filterToggleShow i18n

        activeCount : Int
        activeCount =
            Filter.countActiveEntryFilters filters
    in
    Ui.row [ Ui.spacing Theme.spacing.sm ]
        [ Ui.el
            [ Ui.pointer
            , Ui.Events.onClick (toMsg ToggleFilters)
            , Ui.Font.size Theme.fontSize.sm
            , Ui.Font.color Theme.primary
            ]
            (Ui.text label)
        , if not showFilters && activeCount > 0 then
            Ui.el
                [ Ui.Font.size Theme.fontSize.sm
                , Ui.Font.color Theme.neutral500
                ]
                (Ui.text (T.filterActiveCount (String.fromInt activeCount) i18n))

          else
            Ui.none
        ]


filterBar : I18n -> (Msg -> msg) -> EntryFilters -> GroupState -> Ui.Element msg
filterBar i18n toMsg filters state =
    Ui.column
        [ Ui.spacing Theme.spacing.sm
        , Ui.width Ui.fill
        , Ui.padding Theme.spacing.sm
        , Ui.rounded Theme.rounding.sm
        , Ui.background Theme.neutral200
        ]
        [ personFilterSection i18n toMsg filters.persons state
        , categoryFilterSection i18n toMsg filters.categories
        , currencyFilterSection i18n toMsg filters.currencies state
        , dateFilterSection i18n toMsg filters.dateRanges
        , if Filter.isEntryFilterActive filters then
            Ui.el
                [ Ui.pointer
                , Ui.Events.onClick (toMsg ClearAllFilters)
                , Ui.Font.size Theme.fontSize.sm
                , Ui.Font.color Theme.danger
                ]
                (Ui.text (T.filterClearAll i18n))

          else
            Ui.none
        ]


personFilterSection : I18n -> (Msg -> msg) -> Set Member.Id -> GroupState -> Ui.Element msg
personFilterSection i18n toMsg selected state =
    let
        members : List ( Member.Id, String )
        members =
            GroupState.activeMembers state
                |> List.map (\m -> ( m.rootId, m.name ))
                |> List.sortBy Tuple.second
    in
    filterSection (T.filterPersonLabel i18n)
        (List.map
            (\( id, name ) ->
                filterChip toMsg (TogglePerson id) name (Set.member id selected)
            )
            members
        )


categoryFilterSection : I18n -> (Msg -> msg) -> Set String -> Ui.Element msg
categoryFilterSection i18n toMsg selected =
    let
        allCategories : List ( String, String )
        allCategories =
            [ ( Filter.categoryFilterToString TransferCategory, T.filterCategoryTransfer i18n )
            , ( Filter.categoryFilterToString (ExpenseCategory Entry.Food), T.categoryFood i18n )
            , ( Filter.categoryFilterToString (ExpenseCategory Entry.Transport), T.categoryTransport i18n )
            , ( Filter.categoryFilterToString (ExpenseCategory Entry.Accommodation), T.categoryAccommodation i18n )
            , ( Filter.categoryFilterToString (ExpenseCategory Entry.Entertainment), T.categoryEntertainment i18n )
            , ( Filter.categoryFilterToString (ExpenseCategory Entry.Shopping), T.categoryShopping i18n )
            , ( Filter.categoryFilterToString (ExpenseCategory Entry.Groceries), T.categoryGroceries i18n )
            , ( Filter.categoryFilterToString (ExpenseCategory Entry.Utilities), T.categoryUtilities i18n )
            , ( Filter.categoryFilterToString (ExpenseCategory Entry.Healthcare), T.categoryHealthcare i18n )
            , ( Filter.categoryFilterToString (ExpenseCategory Entry.Other), T.categoryOther i18n )
            ]
    in
    filterSection (T.filterCategoryLabel i18n)
        (List.map
            (\( key, label ) ->
                filterChip toMsg (ToggleCategory key) label (Set.member key selected)
            )
            allCategories
        )


currencyFilterSection : I18n -> (Msg -> msg) -> Set String -> GroupState -> Ui.Element msg
currencyFilterSection i18n toMsg selected state =
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
    filterSection (T.filterCurrencyLabel i18n)
        (List.map
            (\code ->
                filterChip toMsg (ToggleCurrency code) code (Set.member code selected)
            )
            usedCurrencies
        )


dateFilterSection : I18n -> (Msg -> msg) -> List DateRange -> Ui.Element msg
dateFilterSection i18n toMsg activeRanges =
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
    filterSection (T.filterDateLabel i18n)
        (List.map
            (\( range, label ) ->
                filterChip toMsg (ToggleDateRange range) label (List.member range activeRanges)
            )
            presets
        )


filterSection : String -> List (Ui.Element msg) -> Ui.Element msg
filterSection label chips =
    Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ] (Ui.text label)
        , Ui.row [ Ui.wrap, Ui.spacing Theme.spacing.xs ] chips
        ]


filterChip : (Msg -> msg) -> Msg -> String -> Bool -> Ui.Element msg
filterChip toMsg msg label isActive =
    let
        bgColor : Ui.Attribute msg
        bgColor =
            if isActive then
                Ui.background Theme.primaryLight

            else
                Ui.background Theme.white

        borderColor : Ui.Attribute msg
        borderColor =
            if isActive then
                Ui.borderColor Theme.primary

            else
                Ui.borderColor Theme.neutral300
    in
    Ui.el
        [ Ui.paddingXY Theme.spacing.sm Theme.spacing.xs
        , Ui.rounded Theme.rounding.sm
        , Ui.border Theme.borderWidth.sm
        , bgColor
        , borderColor
        , Ui.pointer
        , Ui.Font.size Theme.fontSize.sm
        , Ui.Events.onClick (toMsg msg)
        ]
        (Ui.text label)


entryRow : I18n -> (Entry.Id -> String) -> (Entry.Id -> msg) -> { entry : Entry.Entry, isDeleted : Bool } -> Ui.Element msg
entryRow i18n resolveName onEntryClick { entry, isDeleted } =
    let
        card : Ui.Element msg
        card =
            UI.Components.entryCard i18n resolveName (onEntryClick entry.meta.rootId) entry
    in
    if isDeleted then
        Ui.el [ Ui.opacity 0.5 ]
            (Ui.row [ Ui.width Ui.fill, Ui.spacing Theme.spacing.sm ]
                [ card
                , Ui.el
                    [ Ui.Font.size Theme.fontSize.sm
                    , Ui.Font.color Theme.danger
                    , Ui.Font.bold
                    ]
                    (Ui.text (T.entryDeletedBadge i18n))
                ]
            )

    else
        card


deletedToggle : I18n -> Bool -> Int -> msg -> Ui.Element msg
deletedToggle i18n showDeleted count onToggle =
    Ui.el
        [ Ui.pointer
        , Ui.Events.onClick onToggle
        , Ui.Font.size Theme.fontSize.sm
        , Ui.Font.color Theme.primary
        ]
        (Ui.text
            (if showDeleted then
                T.entriesHideDeleted i18n

             else
                T.entriesShowDeleted (String.fromInt count) i18n
            )
        )


newEntryButton : I18n -> msg -> Ui.Element msg
newEntryButton i18n onNewEntry =
    Ui.el
        [ Ui.Input.button onNewEntry
        , Ui.width Ui.fill
        , Ui.padding Theme.spacing.md
        , Ui.rounded Theme.rounding.md
        , Ui.background Theme.primary
        , Ui.Font.color Theme.white
        , Ui.Font.center
        , Ui.Font.bold
        , Ui.pointer
        ]
        (Ui.text (T.shellNewEntry i18n))


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
