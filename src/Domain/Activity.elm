module Domain.Activity exposing (Activity, Detail(..), StateContext, fromEnvelope)

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


{-| State lookups needed to build an activity from an event.
Constructed by GroupState to avoid circular dependency.
-}
type alias StateContext =
    { resolveName : Member.Id -> String
    , memberMetadata : Member.Id -> Member.Metadata
    , entryDescription : Entry.Id -> String
    , previousVersion : Entry.Entry -> Maybe Entry.Entry
    , groupMeta : { name : String, subtitle : Maybe String, description : Maybe String, links : List Group.Link }
    }


{-| Build an Activity from an event envelope, given the state before the event.
-}
fromEnvelope : StateContext -> Event.Envelope -> Activity
fromEnvelope ctx envelope =
    { eventId = envelope.id
    , timestamp = envelope.clientTimestamp
    , actorId = envelope.triggeredBy
    , detail = payloadToDetail ctx envelope.payload
    }


payloadToDetail : StateContext -> Payload -> Detail
payloadToDetail ctx payload =
    case payload of
        EntryAdded entry ->
            entryAddedDetail entry

        EntryModified entry ->
            entryModifiedDetail ctx entry

        EntryDeleted { rootId } ->
            EntryDeletedDetail { entryDescription = ctx.entryDescription rootId }

        EntryUndeleted { rootId } ->
            EntryUndeletedDetail { entryDescription = ctx.entryDescription rootId }

        MemberCreated data ->
            MemberCreatedDetail { name = data.name, memberType = data.memberType }

        MemberReplaced { rootId } ->
            MemberReplacedDetail { name = ctx.resolveName rootId }

        MemberRenamed data ->
            MemberRenamedDetail { oldName = data.oldName, newName = data.newName }

        MemberRetired { rootId } ->
            MemberRetiredDetail { name = ctx.resolveName rootId }

        MemberUnretired { rootId } ->
            MemberUnretiredDetail { name = ctx.resolveName rootId }

        MemberMetadataUpdated data ->
            MemberMetadataUpdatedDetail
                { name = ctx.resolveName data.rootId
                , updatedFields = memberMetadataChanges (ctx.memberMetadata data.rootId) data.metadata
                }

        GroupMetadataUpdated change ->
            GroupMetadataUpdatedDetail
                { changedFields = groupMetadataChangedFields ctx.groupMeta change }


entryAddedDetail : Entry.Entry -> Detail
entryAddedDetail entry =
    case entry.kind of
        Expense data ->
            EntryAddedDetail { description = data.description, amount = data.amount, currency = data.currency }

        Transfer data ->
            TransferAddedDetail { amount = data.amount, currency = data.currency }


entryModifiedDetail : StateContext -> Entry.Entry -> Detail
entryModifiedDetail ctx entry =
    let
        previousEntry =
            ctx.previousVersion entry
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
