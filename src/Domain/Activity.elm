module Domain.Activity exposing (Activity, Detail(..), fromEvents)

{-| Build a human-readable activity feed from raw group events.
-}

import Dict
import Domain.Currency exposing (Currency)
import Domain.Entry as Entry exposing (Kind(..))
import Domain.Event as Event exposing (Payload(..))
import Domain.GroupState as GroupState exposing (GroupState)
import Domain.Member as Member
import Time


{-| A single activity item for the feed.
-}
type alias Activity =
    { eventId : Event.Id
    , timestamp : Time.Posix
    , actorId : Member.Id
    , detail : Detail
    }


{-| What happened in this activity.
-}
type Detail
    = EntryAddedDetail { description : String, amount : Int, currency : Currency }
    | EntryModifiedDetail { description : String, amount : Int, currency : Currency, changes : List String }
    | TransferAddedDetail { amount : Int, currency : Currency }
    | TransferModifiedDetail { amount : Int, currency : Currency, changes : List String }
    | EntryDeletedDetail { entryDescription : String }
    | EntryUndeletedDetail { entryDescription : String }
    | MemberCreatedDetail { name : String, memberType : Member.Type }
    | MemberReplacedDetail { name : String }
    | MemberRenamedDetail { oldName : String, newName : String }
    | MemberRetiredDetail { name : String }
    | MemberUnretiredDetail { name : String }
    | MemberMetadataUpdatedDetail { name : String, updatedFields : List String }
    | GroupMetadataUpdatedDetail { changedFields : List String }


{-| Convert a list of event envelopes to activity items, newest first.
Events are replayed chronologically so each activity can compare against
the state before the event was applied. The result is reversed for display.
-}
fromEvents : List Event.Envelope -> List Activity
fromEvents envelopes =
    envelopes
        |> Event.sortEvents
        |> List.foldl
            (\envelope ( state, activities ) ->
                let
                    activity =
                        envelopeToActivity state envelope

                    newState =
                        GroupState.applyEvents [ envelope ] state
                in
                ( newState, activity :: activities )
            )
            ( GroupState.empty, [] )
        |> Tuple.second


envelopeToActivity : GroupState -> Event.Envelope -> Activity
envelopeToActivity stateBefore envelope =
    { eventId = envelope.id
    , timestamp = envelope.clientTimestamp
    , actorId = envelope.triggeredBy
    , detail = payloadToDetail stateBefore envelope.payload
    }


payloadToDetail : GroupState -> Payload -> Detail
payloadToDetail stateBefore payload =
    case payload of
        EntryAdded entry ->
            entryAddedDetail entry

        EntryModified entry ->
            entryModifiedDetail stateBefore entry

        EntryDeleted { rootId } ->
            EntryDeletedDetail { entryDescription = lookupEntryDescription stateBefore rootId }

        EntryUndeleted { rootId } ->
            EntryUndeletedDetail { entryDescription = lookupEntryDescription stateBefore rootId }

        MemberCreated data ->
            MemberCreatedDetail { name = data.name, memberType = data.memberType }

        MemberReplaced { rootId } ->
            MemberReplacedDetail { name = GroupState.resolveMemberName stateBefore rootId }

        MemberRenamed data ->
            MemberRenamedDetail { oldName = data.oldName, newName = data.newName }

        MemberRetired { rootId } ->
            MemberRetiredDetail { name = GroupState.resolveMemberName stateBefore rootId }

        MemberUnretired { rootId } ->
            MemberUnretiredDetail { name = GroupState.resolveMemberName stateBefore rootId }

        MemberMetadataUpdated data ->
            let
                oldMetadata =
                    Dict.get data.rootId stateBefore.members
                        |> Maybe.map .metadata
                        |> Maybe.withDefault Member.emptyMetadata
            in
            MemberMetadataUpdatedDetail
                { name = GroupState.resolveMemberName stateBefore data.rootId
                , updatedFields = memberMetadataChanges oldMetadata data.metadata
                }

        GroupMetadataUpdated change ->
            GroupMetadataUpdatedDetail
                { changedFields = groupMetadataChangedFields stateBefore.groupMeta change }


entryAddedDetail : Entry.Entry -> Detail
entryAddedDetail entry =
    case entry.kind of
        Expense data ->
            EntryAddedDetail { description = data.description, amount = data.amount, currency = data.currency }

        Transfer data ->
            TransferAddedDetail { amount = data.amount, currency = data.currency }


entryModifiedDetail : GroupState -> Entry.Entry -> Detail
entryModifiedDetail state entry =
    let
        previousEntry =
            lookupPreviousVersion state entry
    in
    case entry.kind of
        Expense data ->
            EntryModifiedDetail
                { description = data.description
                , amount = data.amount
                , currency = data.currency
                , changes = expenseChanges previousEntry data
                }

        Transfer data ->
            TransferModifiedDetail
                { amount = data.amount
                , currency = data.currency
                , changes = transferChanges previousEntry data
                }


lookupPreviousVersion : GroupState -> Entry.Entry -> Maybe Entry.Entry
lookupPreviousVersion state entry =
    entry.meta.previousVersionId
        |> Maybe.andThen
            (\prevId ->
                Dict.get entry.meta.rootId state.entries
                    |> Maybe.andThen (\entryState -> Dict.get prevId entryState.allVersions)
            )


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


groupMetadataChangedFields : GroupState.GroupMetadata -> Event.GroupMetadataChange -> List String
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


lookupEntryDescription : GroupState -> Entry.Id -> String
lookupEntryDescription state rootId =
    case Dict.get rootId state.entries of
        Just entryState ->
            case entryState.currentVersion.kind of
                Expense data ->
                    data.description

                Transfer _ ->
                    "Transfer"

        Nothing ->
            rootId
