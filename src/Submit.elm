module Submit exposing
    ( Context
    , LoadedGroup
    , State
    , addMember
    , currentUserRootId
    , deleteEntry
    , editEntry
    , entryFormConfig
    , event
    , initLoadedGroup
    , newEntry
    , newGroup
    , restoreEntry
    )

import ConcurrentTask
import Crypto
import Dict
import Domain.Date as Date
import Domain.Entry as Entry
import Domain.Event as Event
import Domain.Group as Group
import Domain.GroupState as GroupState
import Domain.Member as Member
import Form.NewGroup
import IdGen
import Identity exposing (Identity)
import IndexedDb as Idb
import Json.Encode
import Page.NewEntry
import Random
import Set exposing (Set)
import Storage exposing (GroupSummary)
import Time
import UUID
import WebCrypto.Symmetric as Symmetric


{-| Dependencies needed to submit events: task pool, identity, DB, and RNG state.
-}
type alias Context msg =
    { pool : ConcurrentTask.Pool msg
    , sendTask : Json.Encode.Value -> Cmd msg
    , onComplete : ConcurrentTask.Response Idb.Error Event.Envelope -> msg
    , randomSeed : Random.Seed
    , uuidState : UUID.V7State
    , currentTime : Time.Posix
    , db : Idb.Db
    , identity : Identity
    }


{-| Returned state after a submission, with updated pool and RNG state.
-}
type alias State msg =
    { pool : ConcurrentTask.Pool msg
    , randomSeed : Random.Seed
    , uuidState : UUID.V7State
    }


{-| A fully loaded group with its events, computed state, summary, and encryption key.
-}
type alias LoadedGroup =
    { events : List Event.Envelope
    , groupState : GroupState.GroupState
    , summary : GroupSummary
    , groupKey : Symmetric.Key
    , syncCursor : Maybe String
    , unpushedIds : Set String
    }


{-| Build a LoadedGroup from raw events, a summary, and the group key, applying all events to compute state.
-}
initLoadedGroup : List Event.Envelope -> GroupSummary -> Symmetric.Key -> Maybe String -> Set String -> LoadedGroup
initLoadedGroup events summary key cursor unpushed =
    -- We store the events in reverse order for efficient prepending of new events
    { events = List.reverse events
    , groupState = GroupState.applyEvents events GroupState.empty
    , summary = summary
    , groupKey = key
    , syncCursor = cursor
    , unpushedIds = unpushed
    }


attempt : Context msg -> Event.Envelope -> Group.Id -> ( State msg, Cmd msg )
attempt ctx envelope groupId =
    let
        task : ConcurrentTask.ConcurrentTask Idb.Error Event.Envelope
        task =
            ConcurrentTask.batch
                [ Storage.saveEvents ctx.db groupId [ envelope ]
                , Storage.addUnpushedIds ctx.db groupId [ envelope.id ]
                ]
                |> ConcurrentTask.map (\_ -> envelope)

        ( pool, cmd ) =
            ConcurrentTask.attempt
                { pool = ctx.pool
                , send = ctx.sendTask
                , onComplete = ctx.onComplete
                }
                task
    in
    ( { pool = pool
      , randomSeed = ctx.randomSeed
      , uuidState = ctx.uuidState
      }
    , cmd
    )



-- New Group


{-| Submit a new group creation with its initial members and events.
-}
newGroup : Context msg -> (ConcurrentTask.Response Idb.Error GroupSummary -> msg) -> Form.NewGroup.Output -> ( State msg, Cmd msg )
newGroup ctx onComplete output =
    let
        ( groupId, seed1 ) =
            IdGen.pbId ctx.randomSeed

        ( virtualMemberIds, seedAfter ) =
            IdGen.v4batch (List.length output.virtualMembers) seed1

        ( eventIds, uuidStateAfter ) =
            IdGen.v7batch (2 + List.length output.virtualMembers) ctx.currentTime ctx.uuidState

        payloads : List Event.Payload
        payloads =
            Event.createGroup
                { name = output.name
                , creator = ( ctx.identity.publicKeyHash, output.creatorName )
                , virtualMembers = List.map2 Tuple.pair virtualMemberIds output.virtualMembers
                }

        allEvents : List Event.Envelope
        allEvents =
            List.map2 (\eventId -> Event.wrap eventId ctx.currentTime ctx.identity.publicKeyHash)
                eventIds
                payloads

        summary : GroupSummary
        summary =
            { id = groupId
            , name = output.name
            , defaultCurrency = output.currency
            }

        allEventIds : List String
        allEventIds =
            List.map .id allEvents

        task : ConcurrentTask.ConcurrentTask Idb.Error GroupSummary
        task =
            Crypto.generateGroupKey
                |> ConcurrentTask.andThen
                    (\key ->
                        Storage.saveGroupSummary ctx.db summary
                            |> ConcurrentTask.andThen (\_ -> Storage.saveGroupKey ctx.db groupId (Symmetric.exportKey key))
                            |> ConcurrentTask.andThen (\_ -> Storage.saveEvents ctx.db groupId allEvents)
                            |> ConcurrentTask.andThen (\_ -> Storage.addUnpushedIds ctx.db groupId allEventIds)
                            |> ConcurrentTask.map (\_ -> summary)
                    )

        ( pool, cmd ) =
            ConcurrentTask.attempt
                { pool = ctx.pool
                , send = ctx.sendTask
                , onComplete = onComplete
                }
                task
    in
    ( { pool = pool
      , randomSeed = seedAfter
      , uuidState = uuidStateAfter
      }
    , cmd
    )



-- New Entry


{-| Submit a new entry (expense or transfer) to a group.
-}
newEntry : Context msg -> LoadedGroup -> Page.NewEntry.Output -> ( State msg, Cmd msg )
newEntry ctx loaded output =
    let
        ( entryId, seedAfter ) =
            IdGen.v4 ctx.randomSeed

        ( eventId, uuidStateAfter ) =
            IdGen.v7 ctx.currentTime ctx.uuidState

        meta : Entry.Metadata
        meta =
            Entry.newMetadata entryId ctx.identity.publicKeyHash ctx.currentTime

        kind : Entry.Kind
        kind =
            Page.NewEntry.outputToKind output

        entry : Entry.Entry
        entry =
            { meta = meta, kind = kind }

        envelope : Event.Envelope
        envelope =
            Event.wrap eventId ctx.currentTime ctx.identity.publicKeyHash (Event.EntryAdded entry)
    in
    attempt { ctx | randomSeed = seedAfter, uuidState = uuidStateAfter } envelope loaded.summary.id



-- Edit Entry


{-| Submit an edit to an existing entry. Returns Nothing if the entry is not found.
-}
editEntry : Context msg -> LoadedGroup -> Entry.Id -> Page.NewEntry.Output -> Maybe ( State msg, Cmd msg )
editEntry ctx loaded originalEntryId output =
    case Dict.get originalEntryId loaded.groupState.entries of
        Nothing ->
            Nothing

        Just entryState ->
            let
                ( newEntryId, seedAfter ) =
                    IdGen.v4 ctx.randomSeed

                ( eventId, uuidStateAfter ) =
                    IdGen.v7 ctx.currentTime ctx.uuidState

                newKind : Entry.Kind
                newKind =
                    Page.NewEntry.outputToKind output

                entry : Entry.Entry
                entry =
                    Entry.replace entryState.currentVersion.meta newEntryId newKind

                envelope : Event.Envelope
                envelope =
                    Event.wrap eventId ctx.currentTime ctx.identity.publicKeyHash (Event.EntryModified entry)
            in
            Just (attempt { ctx | randomSeed = seedAfter, uuidState = uuidStateAfter } envelope loaded.summary.id)



-- Delete / Restore Entry


{-| Submit a soft-delete for an entry.
-}
deleteEntry : Context msg -> LoadedGroup -> Entry.Id -> ( State msg, Cmd msg )
deleteEntry ctx loaded rootId =
    simpleEvent ctx loaded (Event.EntryDeleted { rootId = rootId })


{-| Submit an un-delete (restore) for a previously deleted entry.
-}
restoreEntry : Context msg -> LoadedGroup -> Entry.Id -> ( State msg, Cmd msg )
restoreEntry ctx loaded rootId =
    simpleEvent ctx loaded (Event.EntryUndeleted { rootId = rootId })


simpleEvent : Context msg -> LoadedGroup -> Event.Payload -> ( State msg, Cmd msg )
simpleEvent ctx loaded payload =
    let
        ( eventId, uuidStateAfter ) =
            IdGen.v7 ctx.currentTime ctx.uuidState

        envelope : Event.Envelope
        envelope =
            Event.wrap eventId ctx.currentTime ctx.identity.publicKeyHash payload
    in
    attempt { ctx | uuidState = uuidStateAfter } envelope loaded.summary.id



-- Member Event (generic)


{-| Submit a generic event payload to a group.
-}
event : Context msg -> LoadedGroup -> Event.Payload -> ( State msg, Cmd msg )
event =
    simpleEvent



-- Add Member


{-| Submit a new virtual member creation to a group.
-}
addMember : Context msg -> LoadedGroup -> { name : String } -> ( State msg, Cmd msg )
addMember ctx loaded output =
    let
        ( newMemberId, seedAfter ) =
            IdGen.v4 ctx.randomSeed

        ( eventId, uuidStateAfter ) =
            IdGen.v7 ctx.currentTime ctx.uuidState

        payload : Event.Payload
        payload =
            Event.MemberCreated
                { memberId = newMemberId
                , name = output.name
                , memberType = Member.Virtual
                , addedBy = ctx.identity.publicKeyHash
                }

        envelope : Event.Envelope
        envelope =
            Event.wrap eventId ctx.currentTime ctx.identity.publicKeyHash payload
    in
    attempt { ctx | randomSeed = seedAfter, uuidState = uuidStateAfter } envelope loaded.summary.id



-- Helpers


{-| Resolve the current user's member root ID within a loaded group.
-}
currentUserRootId : Storage.InitData -> LoadedGroup -> Member.Id
currentUserRootId readyData loaded =
    GroupState.resolveMemberRootId loaded.groupState
        (readyData.identity |> Maybe.map .publicKeyHash |> Maybe.withDefault "")


{-| Build the configuration needed by the new-entry form from a loaded group.
-}
entryFormConfig : Storage.InitData -> LoadedGroup -> Time.Posix -> Page.NewEntry.Config
entryFormConfig readyData loaded currentTime =
    { currentUserRootId = currentUserRootId readyData loaded
    , activeMembersRootIds = List.map .rootId (GroupState.activeMembers loaded.groupState)
    , today = Date.posixToDate currentTime
    , defaultCurrency = loaded.summary.defaultCurrency
    }
