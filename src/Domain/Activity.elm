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
    | EntryModifiedDetail { description : String, amount : Int, currency : Currency }
    | TransferAddedDetail { amount : Int, currency : Currency }
    | TransferModifiedDetail { amount : Int, currency : Currency }
    | EntryDeletedDetail { entryDescription : String }
    | EntryUndeletedDetail { entryDescription : String }
    | MemberCreatedDetail { name : String, memberType : Member.Type }
    | MemberReplacedDetail { name : String }
    | MemberRenamedDetail { oldName : String, newName : String }
    | MemberRetiredDetail { name : String }
    | MemberUnretiredDetail { name : String }
    | MemberMetadataUpdatedDetail { name : String }
    | GroupMetadataUpdatedDetail


{-| Convert a list of event envelopes to activity items, newest first.
Events are sorted chronologically then reversed so the most recent activity
appears first regardless of the input order.
-}
fromEvents : GroupState -> List Event.Envelope -> List Activity
fromEvents state envelopes =
    envelopes
        |> Event.sortEvents
        |> List.reverse
        |> List.map (envelopeToActivity state)


envelopeToActivity : GroupState -> Event.Envelope -> Activity
envelopeToActivity state envelope =
    { eventId = envelope.id
    , timestamp = envelope.clientTimestamp
    , actorId = envelope.triggeredBy
    , detail = payloadToDetail state envelope.payload
    }


payloadToDetail : GroupState -> Payload -> Detail
payloadToDetail state payload =
    case payload of
        EntryAdded entry ->
            entryAddedDetail entry

        EntryModified entry ->
            entryModifiedDetail entry

        EntryDeleted { rootId } ->
            EntryDeletedDetail { entryDescription = lookupEntryDescription state rootId }

        EntryUndeleted { rootId } ->
            EntryUndeletedDetail { entryDescription = lookupEntryDescription state rootId }

        MemberCreated data ->
            MemberCreatedDetail { name = data.name, memberType = data.memberType }

        MemberReplaced { rootId } ->
            MemberReplacedDetail { name = GroupState.resolveMemberName state rootId }

        MemberRenamed data ->
            MemberRenamedDetail { oldName = data.oldName, newName = data.newName }

        MemberRetired { rootId } ->
            MemberRetiredDetail { name = GroupState.resolveMemberName state rootId }

        MemberUnretired { rootId } ->
            MemberUnretiredDetail { name = GroupState.resolveMemberName state rootId }

        MemberMetadataUpdated { rootId } ->
            MemberMetadataUpdatedDetail { name = GroupState.resolveMemberName state rootId }

        GroupMetadataUpdated _ ->
            GroupMetadataUpdatedDetail


entryAddedDetail : Entry.Entry -> Detail
entryAddedDetail entry =
    case entry.kind of
        Expense data ->
            EntryAddedDetail { description = data.description, amount = data.amount, currency = data.currency }

        Transfer data ->
            TransferAddedDetail { amount = data.amount, currency = data.currency }


entryModifiedDetail : Entry.Entry -> Detail
entryModifiedDetail entry =
    case entry.kind of
        Expense data ->
            EntryModifiedDetail { description = data.description, amount = data.amount, currency = data.currency }

        Transfer data ->
            TransferModifiedDetail { amount = data.amount, currency = data.currency }


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
