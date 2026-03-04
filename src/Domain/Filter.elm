module Domain.Filter exposing
    ( ActivityFilters
    , ActivityType(..)
    , CategoryFilter(..)
    , DateRange(..)
    , EntryFilters
    , activityTypeToString
    , categoryFilterToString
    , countActiveActivityFilters
    , countActiveEntryFilters
    , emptyActivityFilters
    , emptyEntryFilters
    , isActivityFilterActive
    , isEntryFilterActive
    , matchesActivityFilters
    , matchesEntryFilters
    )

{-| Filter types and predicate logic for entries and activities.
-}

import Domain.Activity exposing (Activity, Detail(..))
import Domain.Currency as Currency
import Domain.Date as Date exposing (Date)
import Domain.Entry as Entry
import Domain.Member as Member
import Set exposing (Set)


{-| Entry filter state. Uses Set String internally since Elm's Set requires comparable.
-}
type alias EntryFilters =
    { persons : Set Member.Id
    , categories : Set String
    , currencies : Set String
    , dateRanges : List DateRange
    }


{-| Category filter including a virtual "transfer" category.
-}
type CategoryFilter
    = ExpenseCategory Entry.Category
    | TransferCategory


{-| Predefined and custom date ranges.
-}
type DateRange
    = Today
    | Yesterday
    | Last7Days
    | Last30Days
    | ThisMonth
    | LastMonth


{-| Activity filter state.
-}
type alias ActivityFilters =
    { activityTypes : Set String
    , actors : Set Member.Id
    , involvedMembers : Set Member.Id
    }


{-| Activity type categories.
-}
type ActivityType
    = EntryActivity
    | MemberActivity
    | GroupActivity


emptyEntryFilters : EntryFilters
emptyEntryFilters =
    { persons = Set.empty
    , categories = Set.empty
    , currencies = Set.empty
    , dateRanges = []
    }


emptyActivityFilters : ActivityFilters
emptyActivityFilters =
    { activityTypes = Set.empty
    , actors = Set.empty
    , involvedMembers = Set.empty
    }


isEntryFilterActive : EntryFilters -> Bool
isEntryFilterActive f =
    not (Set.isEmpty f.persons)
        || not (Set.isEmpty f.categories)
        || not (Set.isEmpty f.currencies)
        || not (List.isEmpty f.dateRanges)


isActivityFilterActive : ActivityFilters -> Bool
isActivityFilterActive f =
    not (Set.isEmpty f.activityTypes)
        || not (Set.isEmpty f.actors)
        || not (Set.isEmpty f.involvedMembers)


countActiveEntryFilters : EntryFilters -> Int
countActiveEntryFilters f =
    boolToInt (not (Set.isEmpty f.persons))
        + boolToInt (not (Set.isEmpty f.categories))
        + boolToInt (not (Set.isEmpty f.currencies))
        + boolToInt (not (List.isEmpty f.dateRanges))


countActiveActivityFilters : ActivityFilters -> Int
countActiveActivityFilters f =
    boolToInt (not (Set.isEmpty f.activityTypes))
        + boolToInt (not (Set.isEmpty f.actors))
        + boolToInt (not (Set.isEmpty f.involvedMembers))


boolToInt : Bool -> Int
boolToInt b =
    if b then
        1

    else
        0



-- Entry filter matching


{-| Check if an entry matches all active filters. Empty dimension = no constraint.
-}
matchesEntryFilters : Date -> EntryFilters -> Entry.Entry -> Bool
matchesEntryFilters today filters entry =
    matchesPersonFilter filters.persons entry
        && matchesCategoryFilter filters.categories entry
        && matchesCurrencyFilter filters.currencies entry
        && matchesDateFilter today filters.dateRanges entry


matchesPersonFilter : Set Member.Id -> Entry.Entry -> Bool
matchesPersonFilter persons entry =
    if Set.isEmpty persons then
        True

    else
        let
            involved : Set Member.Id
            involved =
                entryInvolvedMembers entry
        in
        Set.foldl (\p acc -> acc && Set.member p involved) True persons


entryInvolvedMembers : Entry.Entry -> Set Member.Id
entryInvolvedMembers entry =
    case entry.kind of
        Entry.Expense data ->
            let
                payerIds : List Member.Id
                payerIds =
                    List.map .memberId data.payers

                beneficiaryIds : List Member.Id
                beneficiaryIds =
                    List.map beneficiaryMemberId data.beneficiaries
            in
            Set.fromList (payerIds ++ beneficiaryIds)

        Entry.Transfer data ->
            Set.fromList [ data.from, data.to ]


beneficiaryMemberId : Entry.Beneficiary -> Member.Id
beneficiaryMemberId b =
    case b of
        Entry.ShareBeneficiary r ->
            r.memberId

        Entry.ExactBeneficiary r ->
            r.memberId


matchesCategoryFilter : Set String -> Entry.Entry -> Bool
matchesCategoryFilter categories entry =
    if Set.isEmpty categories then
        True

    else
        case entry.kind of
            Entry.Expense data ->
                case data.category of
                    Just cat ->
                        Set.member (categoryFilterToString (ExpenseCategory cat)) categories

                    Nothing ->
                        False

            Entry.Transfer _ ->
                Set.member (categoryFilterToString TransferCategory) categories


matchesCurrencyFilter : Set String -> Entry.Entry -> Bool
matchesCurrencyFilter currencies entry =
    if Set.isEmpty currencies then
        True

    else
        let
            code : String
            code =
                case entry.kind of
                    Entry.Expense data ->
                        Currency.currencyCode data.currency

                    Entry.Transfer data ->
                        Currency.currencyCode data.currency
        in
        Set.member code currencies


matchesDateFilter : Date -> List DateRange -> Entry.Entry -> Bool
matchesDateFilter today ranges entry =
    if List.isEmpty ranges then
        True

    else
        let
            entryDate : Date
            entryDate =
                case entry.kind of
                    Entry.Expense data ->
                        data.date

                    Entry.Transfer data ->
                        data.date
        in
        List.any (\range -> dateInRange today range entryDate) ranges


dateInRange : Date -> DateRange -> Date -> Bool
dateInRange today range date =
    let
        resolved : { from : Date, to : Date }
        resolved =
            resolveDateRange today range
    in
    Date.toComparable date
        >= Date.toComparable resolved.from
        && Date.toComparable date
        <= Date.toComparable resolved.to


{-| Resolve a date range preset to concrete from/to dates.
-}
resolveDateRange : Date -> DateRange -> { from : Date, to : Date }
resolveDateRange today range =
    case range of
        Today ->
            { from = today, to = today }

        Yesterday ->
            let
                y : Date
                y =
                    Date.addDays -1 today
            in
            { from = y, to = y }

        Last7Days ->
            { from = Date.addDays -6 today, to = today }

        Last30Days ->
            { from = Date.addDays -29 today, to = today }

        ThisMonth ->
            { from = Date.startOfMonth today, to = Date.endOfMonth today }

        LastMonth ->
            Date.previousMonth today



-- Activity filter matching


{-| Check if an activity matches all active filters.
-}
matchesActivityFilters : ActivityFilters -> Activity -> Bool
matchesActivityFilters filters activity =
    matchesActivityTypeFilter filters.activityTypes activity
        && matchesActorFilter filters.actors activity
        && matchesInvolvedFilter filters.involvedMembers activity


matchesActivityTypeFilter : Set String -> Activity -> Bool
matchesActivityTypeFilter types activity =
    if Set.isEmpty types then
        True

    else
        Set.member (activityTypeToString (classifyActivity activity)) types


classifyActivity : Activity -> ActivityType
classifyActivity activity =
    case activity.detail of
        EntryAddedDetail _ ->
            EntryActivity

        EntryModifiedDetail _ ->
            EntryActivity

        TransferAddedDetail _ ->
            EntryActivity

        TransferModifiedDetail _ ->
            EntryActivity

        EntryDeletedDetail _ ->
            EntryActivity

        EntryUndeletedDetail _ ->
            EntryActivity

        MemberCreatedDetail _ ->
            MemberActivity

        MemberReplacedDetail _ ->
            MemberActivity

        MemberRenamedDetail _ ->
            MemberActivity

        MemberRetiredDetail _ ->
            MemberActivity

        MemberUnretiredDetail _ ->
            MemberActivity

        MemberMetadataUpdatedDetail _ ->
            MemberActivity

        GroupCreatedDetail _ ->
            GroupActivity

        GroupMetadataUpdatedDetail _ ->
            GroupActivity

        SettlementPreferencesUpdatedDetail _ ->
            GroupActivity


matchesActorFilter : Set Member.Id -> Activity -> Bool
matchesActorFilter actors activity =
    if Set.isEmpty actors then
        True

    else
        Set.member activity.actorId actors


matchesInvolvedFilter : Set Member.Id -> Activity -> Bool
matchesInvolvedFilter members activity =
    if Set.isEmpty members then
        True

    else
        Set.foldl (\m acc -> acc && List.member m activity.involvedMembers) True members



-- String conversions for Set-based storage


categoryFilterToString : CategoryFilter -> String
categoryFilterToString cf =
    case cf of
        ExpenseCategory cat ->
            "expense:" ++ categoryToString cat

        TransferCategory ->
            "transfer"


categoryToString : Entry.Category -> String
categoryToString cat =
    case cat of
        Entry.Food ->
            "food"

        Entry.Transport ->
            "transport"

        Entry.Accommodation ->
            "accommodation"

        Entry.Entertainment ->
            "entertainment"

        Entry.Shopping ->
            "shopping"

        Entry.Groceries ->
            "groceries"

        Entry.Utilities ->
            "utilities"

        Entry.Healthcare ->
            "healthcare"

        Entry.Other ->
            "other"


activityTypeToString : ActivityType -> String
activityTypeToString at =
    case at of
        EntryActivity ->
            "entry"

        MemberActivity ->
            "member"

        GroupActivity ->
            "group"
