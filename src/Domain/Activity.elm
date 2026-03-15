module Domain.Activity exposing (Activity, Detail(..), GroupMetadataSnapshot, StateContext, fromEnvelope)

{-| Activity feed types and logic. Built incrementally by GroupState.applyEvents.
-}

import Domain.Currency exposing (Currency)
import Domain.Entry as Entry exposing (Kind(..))
import Domain.Event as Event exposing (Payload(..))
import Domain.Group as Group
import Domain.Member as Member
import Time


{-| A single activity item for the feed.
-}
type alias Activity =
    { eventId : Event.Id
    , timestamp : Time.Posix
    , actorId : Member.Id
    , detail : Detail
    , involvedMembers : List Member.Id
    }


{-| A snapshot of group metadata for diff display.
-}
type alias GroupMetadataSnapshot =
    { name : String
    , subtitle : Maybe String
    , description : Maybe String
    , links : List Group.Link
    }


{-| What happened in this activity.
-}
type Detail
    = EntryAddedDetail { entry : Entry.Entry }
    | EntryModifiedDetail { entry : Entry.Entry, previousEntry : Maybe Entry.Entry, changes : List String }
    | TransferAddedDetail { entry : Entry.Entry }
    | TransferModifiedDetail { entry : Entry.Entry, previousEntry : Maybe Entry.Entry, changes : List String }
    | EntryDeletedDetail { entryDescription : String, entry : Maybe Entry.Entry }
    | EntryUndeletedDetail { entryDescription : String, entry : Maybe Entry.Entry }
    | MemberCreatedDetail { name : String, memberType : Member.Type }
    | MemberReplacedDetail { name : String, rootId : Member.Id }
    | MemberRenamedDetail { oldName : String, newName : String, rootId : Member.Id }
    | MemberRetiredDetail { name : String, rootId : Member.Id }
    | MemberUnretiredDetail { name : String, rootId : Member.Id }
    | MemberMetadataUpdatedDetail { name : String, rootId : Member.Id, oldMetadata : Member.Metadata, newMetadata : Member.Metadata, updatedFields : List String }
    | GroupCreatedDetail { name : String, defaultCurrency : Currency }
    | GroupMetadataUpdatedDetail { oldMeta : GroupMetadataSnapshot, newMeta : GroupMetadataSnapshot, changedFields : List String }
    | SettlementPreferencesUpdatedDetail { name : String, memberRootId : Member.Id, oldRecipients : List String, newRecipients : List String }


{-| State lookups needed to build an activity from an event.
Constructed by GroupState to avoid circular dependency.
-}
type alias StateContext =
    { resolveName : Member.Id -> String
    , memberMetadata : Member.Id -> Member.Metadata
    , entryDescription : Entry.Id -> String
    , entryCurrentVersion : Entry.Id -> Maybe Entry.Entry
    , previousVersion : Entry.Entry -> Maybe Entry.Entry
    , groupMeta : GroupMetadataSnapshot
    , settlementPreference : Member.Id -> List Member.Id
    }


{-| Build an Activity from an event envelope, given the state before the event.
-}
fromEnvelope : StateContext -> Event.Envelope -> Activity
fromEnvelope ctx envelope =
    let
        detail : Detail
        detail =
            payloadToDetail ctx envelope.payload

        involved : List Member.Id
        involved =
            involvedMembers ctx envelope.payload
    in
    { eventId = envelope.id
    , timestamp = envelope.clientTimestamp
    , actorId = envelope.triggeredBy
    , detail = detail
    , involvedMembers = involved
    }


involvedMembers : StateContext -> Payload -> List Member.Id
involvedMembers ctx payload =
    case payload of
        EntryAdded entry ->
            entryInvolvedMembers entry

        EntryModified entry ->
            entryInvolvedMembers entry

        EntryDeleted { rootId } ->
            case ctx.entryCurrentVersion rootId of
                Just entry ->
                    entryInvolvedMembers entry

                Nothing ->
                    []

        EntryUndeleted { rootId } ->
            case ctx.entryCurrentVersion rootId of
                Just entry ->
                    entryInvolvedMembers entry

                Nothing ->
                    []

        MemberCreated data ->
            [ data.memberId ]

        MemberReplaced data ->
            [ data.rootId ]

        MemberRenamed data ->
            [ data.rootId ]

        MemberRetired data ->
            [ data.rootId ]

        MemberUnretired data ->
            [ data.rootId ]

        MemberMetadataUpdated data ->
            [ data.rootId ]

        GroupCreated _ ->
            []

        GroupMetadataUpdated _ ->
            []

        SettlementPreferencesUpdated data ->
            [ data.memberRootId ]


entryInvolvedMembers : Entry.Entry -> List Member.Id
entryInvolvedMembers entry =
    case entry.kind of
        Expense data ->
            List.map .memberId data.payers
                ++ List.map beneficiaryMemberId data.beneficiaries

        Transfer data ->
            [ data.from, data.to ]

        Income data ->
            data.receivedBy :: List.map beneficiaryMemberId data.beneficiaries


beneficiaryMemberId : Entry.Beneficiary -> Member.Id
beneficiaryMemberId beneficiary =
    case beneficiary of
        Entry.ShareBeneficiary data ->
            data.memberId

        Entry.ExactBeneficiary data ->
            data.memberId


payloadToDetail : StateContext -> Payload -> Detail
payloadToDetail ctx payload =
    case payload of
        EntryAdded entry ->
            entryAddedDetail entry

        EntryModified entry ->
            entryModifiedDetail ctx entry

        EntryDeleted { rootId } ->
            EntryDeletedDetail
                { entryDescription = ctx.entryDescription rootId
                , entry = ctx.entryCurrentVersion rootId
                }

        EntryUndeleted { rootId } ->
            EntryUndeletedDetail
                { entryDescription = ctx.entryDescription rootId
                , entry = ctx.entryCurrentVersion rootId
                }

        MemberCreated data ->
            MemberCreatedDetail { name = data.name, memberType = data.memberType }

        MemberReplaced { rootId } ->
            MemberReplacedDetail { name = ctx.resolveName rootId, rootId = rootId }

        MemberRenamed data ->
            MemberRenamedDetail { oldName = data.oldName, newName = data.newName, rootId = data.rootId }

        MemberRetired { rootId } ->
            MemberRetiredDetail { name = ctx.resolveName rootId, rootId = rootId }

        MemberUnretired { rootId } ->
            MemberUnretiredDetail { name = ctx.resolveName rootId, rootId = rootId }

        MemberMetadataUpdated data ->
            let
                oldMeta : Member.Metadata
                oldMeta =
                    ctx.memberMetadata data.rootId
            in
            MemberMetadataUpdatedDetail
                { name = ctx.resolveName data.rootId
                , rootId = data.rootId
                , oldMetadata = oldMeta
                , newMetadata = data.metadata
                , updatedFields = memberMetadataChanges oldMeta data.metadata
                }

        GroupCreated data ->
            GroupCreatedDetail { name = data.name, defaultCurrency = data.defaultCurrency }

        GroupMetadataUpdated change ->
            let
                oldMeta : GroupMetadataSnapshot
                oldMeta =
                    ctx.groupMeta

                newMeta : GroupMetadataSnapshot
                newMeta =
                    applyGroupMetadataChange oldMeta change
            in
            GroupMetadataUpdatedDetail
                { oldMeta = oldMeta
                , newMeta = newMeta
                , changedFields = groupMetadataChangedFields oldMeta change
                }

        SettlementPreferencesUpdated data ->
            SettlementPreferencesUpdatedDetail
                { name = ctx.resolveName data.memberRootId
                , memberRootId = data.memberRootId
                , oldRecipients = List.map ctx.resolveName (ctx.settlementPreference data.memberRootId)
                , newRecipients = List.map ctx.resolveName data.preferredRecipients
                }


applyGroupMetadataChange : GroupMetadataSnapshot -> Event.GroupMetadataChange -> GroupMetadataSnapshot
applyGroupMetadataChange old change =
    { name = Maybe.withDefault old.name change.name
    , subtitle = Maybe.withDefault old.subtitle change.subtitle
    , description = Maybe.withDefault old.description change.description
    , links = Maybe.withDefault old.links change.links
    }


entryAddedDetail : Entry.Entry -> Detail
entryAddedDetail entry =
    case entry.kind of
        Expense _ ->
            EntryAddedDetail { entry = entry }

        Transfer _ ->
            TransferAddedDetail { entry = entry }

        Income _ ->
            EntryAddedDetail { entry = entry }


entryModifiedDetail : StateContext -> Entry.Entry -> Detail
entryModifiedDetail ctx entry =
    let
        previousEntry : Maybe Entry.Entry
        previousEntry =
            ctx.previousVersion entry
    in
    case entry.kind of
        Expense data ->
            EntryModifiedDetail
                { entry = entry
                , previousEntry = previousEntry
                , changes = expenseChanges previousEntry data
                }

        Transfer data ->
            TransferModifiedDetail
                { entry = entry
                , previousEntry = previousEntry
                , changes = transferChanges previousEntry data
                }

        Income data ->
            EntryModifiedDetail
                { entry = entry
                , previousEntry = previousEntry
                , changes = incomeChanges previousEntry data
                }


expenseChanges : Maybe Entry.Entry -> Entry.ExpenseData -> List String
expenseChanges maybePrev newData =
    case maybePrev of
        Nothing ->
            []

        Just prev ->
            case prev.kind of
                Expense oldData ->
                    List.filterMap identity
                        [ if oldData.description /= newData.description then
                            Just "description"

                          else
                            Nothing
                        , if oldData.amount /= newData.amount || oldData.currency /= newData.currency then
                            Just "amount"

                          else
                            Nothing
                        , if oldData.date /= newData.date then
                            Just "date"

                          else
                            Nothing
                        , if oldData.payers /= newData.payers then
                            Just "payers"

                          else
                            Nothing
                        , if oldData.beneficiaries /= newData.beneficiaries then
                            Just "beneficiaries"

                          else
                            Nothing
                        , if oldData.category /= newData.category then
                            Just "category"

                          else
                            Nothing
                        , if oldData.notes /= newData.notes then
                            Just "notes"

                          else
                            Nothing
                        ]

                Transfer _ ->
                    []

                Income _ ->
                    []


transferChanges : Maybe Entry.Entry -> Entry.TransferData -> List String
transferChanges maybePrev newData =
    case maybePrev of
        Nothing ->
            []

        Just prev ->
            case prev.kind of
                Transfer oldData ->
                    List.filterMap identity
                        [ if oldData.amount /= newData.amount || oldData.currency /= newData.currency then
                            Just "amount"

                          else
                            Nothing
                        , if oldData.date /= newData.date then
                            Just "date"

                          else
                            Nothing
                        , if oldData.from /= newData.from then
                            Just "from"

                          else
                            Nothing
                        , if oldData.to /= newData.to then
                            Just "to"

                          else
                            Nothing
                        , if oldData.notes /= newData.notes then
                            Just "notes"

                          else
                            Nothing
                        ]

                Expense _ ->
                    []

                Income _ ->
                    []


incomeChanges : Maybe Entry.Entry -> Entry.IncomeData -> List String
incomeChanges maybePrev newData =
    case maybePrev of
        Nothing ->
            []

        Just prev ->
            case prev.kind of
                Income oldData ->
                    List.filterMap identity
                        [ if oldData.description /= newData.description then
                            Just "description"

                          else
                            Nothing
                        , if oldData.amount /= newData.amount || oldData.currency /= newData.currency then
                            Just "amount"

                          else
                            Nothing
                        , if oldData.date /= newData.date then
                            Just "date"

                          else
                            Nothing
                        , if oldData.receivedBy /= newData.receivedBy then
                            Just "receivedBy"

                          else
                            Nothing
                        , if oldData.beneficiaries /= newData.beneficiaries then
                            Just "beneficiaries"

                          else
                            Nothing
                        , if oldData.notes /= newData.notes then
                            Just "notes"

                          else
                            Nothing
                        ]

                _ ->
                    []


memberMetadataChanges : Member.Metadata -> Member.Metadata -> List String
memberMetadataChanges oldMeta newMeta =
    List.filterMap identity
        [ if oldMeta.phone /= newMeta.phone then
            Just "phone"

          else
            Nothing
        , if oldMeta.email /= newMeta.email then
            Just "email"

          else
            Nothing
        , if oldMeta.payment /= newMeta.payment then
            Just "payment"

          else
            Nothing
        , if oldMeta.notes /= newMeta.notes then
            Just "notes"

          else
            Nothing
        ]


groupMetadataChangedFields :
    { a | name : String, subtitle : Maybe String, description : Maybe String, links : List Group.Link }
    -> Event.GroupMetadataChange
    -> List String
groupMetadataChangedFields oldMeta change =
    List.filterMap identity
        [ case change.name of
            Just newName ->
                if newName /= oldMeta.name then
                    Just "name"

                else
                    Nothing

            Nothing ->
                Nothing
        , case change.subtitle of
            Just newSubtitle ->
                if newSubtitle /= oldMeta.subtitle then
                    Just "subtitle"

                else
                    Nothing

            Nothing ->
                Nothing
        , case change.description of
            Just newDesc ->
                if newDesc /= oldMeta.description then
                    Just "description"

                else
                    Nothing

            Nothing ->
                Nothing
        , case change.links of
            Just newLinks ->
                if newLinks /= oldMeta.links then
                    Just "links"

                else
                    Nothing

            Nothing ->
                Nothing
        ]
