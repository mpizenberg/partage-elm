module GroupOps exposing
    ( Context
    , LoadedGroup
    , State
    , SyncApplyResult
    , addMember
    , addUnpushedId
    , appendEvent
    , applySyncResult
    , deleteEntry
    , editEntry
    , event
    , eventWithId
    , importSplitwiseGroup
    , initLoadedGroup
    , newEntry
    , newGroup
    , postSyncTasks
    , restoreEntry
    )

import ConcurrentTask exposing (ConcurrentTask)
import ConcurrentTask.Time
import Dict
import Domain.Currency exposing (Currency)
import Domain.Entry as Entry
import Domain.Event as Event
import Domain.Group as Group
import Domain.GroupState as GroupState
import Domain.Member as Member
import Form.NewGroup
import IndexedDb as Idb
import Infra.ConcurrentTaskExtra as Runner exposing (TaskRunner)
import Infra.Crypto as Crypto
import Infra.IdGen as IdGen
import Infra.Identity exposing (Identity)
import Infra.Server as Server
import Infra.Storage as Storage
import Page.Group.NewEntry
import Page.Group.NewEntry.Shared as NewEntryShared
import Random
import Set exposing (Set)
import SplitwiseImport
import Time
import UUID
import WebCrypto.Signature as Signature
import WebCrypto.Symmetric as Symmetric


{-| Dependencies needed to submit events: task runner, identity, DB, and RNG state.
-}
type alias Context msg =
    { runner : TaskRunner msg
    , onComplete : ConcurrentTask.Response Idb.Error Event.Envelope -> msg
    , randomSeed : Random.Seed
    , uuidState : UUID.V7State
    , currentTime : Time.Posix
    , db : Idb.Db
    , identity : Identity
    }


{-| Returned state after a submission, with updated runner and RNG state.
-}
type alias State msg =
    { runner : TaskRunner msg
    , randomSeed : Random.Seed
    , uuidState : UUID.V7State
    }


{-| A fully loaded group with its events, computed state, summary, and encryption key.
-}
type alias LoadedGroup =
    { events : List Event.Envelope
    , groupState : GroupState.GroupState
    , summary : Group.Summary
    , groupKey : Symmetric.Key
    , syncCursor : Maybe Int
    , unpushedIds : Set String
    }


{-| Append an event to a loaded group and recompute state.
-}
appendEvent : Event.Envelope -> LoadedGroup -> LoadedGroup
appendEvent envelope loaded =
    { loaded
        | events = envelope :: loaded.events
        , groupState = GroupState.applyEvents [ envelope ] loaded.groupState
    }


{-| Add an event ID to the unpushed set of a loaded group.
-}
addUnpushedId : String -> LoadedGroup -> LoadedGroup
addUnpushedId eventId loaded =
    { loaded | unpushedIds = Set.insert eventId loaded.unpushedIds }


{-| Build a LoadedGroup from raw events, a summary, and the group key, applying all events to compute state.
-}
initLoadedGroup : List Event.Envelope -> Group.Summary -> Symmetric.Key -> Maybe Int -> Set String -> LoadedGroup
initLoadedGroup events summary key cursor unpushed =
    -- We store the events in reverse order for efficient prepending of new events
    { events = List.reverse events
    , groupState = GroupState.applyEvents events GroupState.empty
    , summary = summary
    , groupKey = key
    , syncCursor = cursor
    , unpushedIds = unpushed
    }


attempt : Context msg -> (Time.Posix -> Event.Envelope) -> Group.Id -> ( State msg, Cmd msg )
attempt ctx makeUnsignedEnvelope groupId =
    let
        signingKeyPair : Signature.SigningKeyPair
        signingKeyPair =
            Signature.importSigningKeyPair ctx.identity.signingKeyPair

        task : ConcurrentTask Idb.Error Event.Envelope
        task =
            ConcurrentTask.map makeUnsignedEnvelope ConcurrentTask.Time.now
                |> ConcurrentTask.andThen (signEnvelope signingKeyPair)
                |> ConcurrentTask.andThen
                    (\envelope ->
                        ConcurrentTask.batch
                            [ Storage.saveEvents ctx.db groupId [ envelope ]
                            , Storage.addUnpushedIds ctx.db groupId [ envelope.id ]
                            ]
                            |> ConcurrentTask.map (\_ -> envelope)
                    )
    in
    ( ctx.runner, Cmd.none )
        |> Runner.andRun ctx.onComplete task
        |> Tuple.mapFirst
            (\r ->
                { runner = r
                , randomSeed = ctx.randomSeed
                , uuidState = ctx.uuidState
                }
            )


{-| Sign an envelope, producing a new envelope with the signature field set.
-}
signEnvelope : Signature.SigningKeyPair -> Event.Envelope -> ConcurrentTask Idb.Error Event.Envelope
signEnvelope signingKeyPair envelope =
    Signature.signText signingKeyPair (Event.canonicalize envelope)
        |> ConcurrentTask.mapError (\_ -> Idb.DatabaseError "Signing failed")
        |> ConcurrentTask.map (\sig -> Event.withSignature sig envelope)


{-| The local device as an event author, for `Event.wrap`.
-}
author : Context msg -> { id : Member.Id, publicKey : String }
author ctx =
    { id = ctx.identity.publicKeyHash
    , publicKey = ctx.identity.signingKeyPair.publicKey
    }



-- New Group


{-| Submit a new group creation with its initial members and events.
-}
newGroup : Context msg -> (ConcurrentTask.Response Idb.Error Group.Summary -> msg) -> Form.NewGroup.Output -> ( State msg, Cmd msg )
newGroup ctx onComplete output =
    let
        ( groupId, seed1 ) =
            IdGen.groupId ctx.randomSeed

        ( virtualMemberIds, seedAfter ) =
            IdGen.v4batch (List.length output.virtualMembers) seed1

        ( eventIds, uuidStateAfter ) =
            IdGen.v7batch (2 + List.length output.virtualMembers) ctx.currentTime ctx.uuidState

        payloads : List Event.Payload
        payloads =
            Event.createGroup
                { name = output.name
                , defaultCurrency = output.currency
                , creator = ( ctx.identity.publicKeyHash, output.creatorName )
                , virtualMembers = List.map2 Tuple.pair virtualMemberIds output.virtualMembers
                }

        summary : Group.Summary
        summary =
            { id = groupId
            , name = output.name
            , defaultCurrency = output.currency
            , isSubscribed = False
            , isArchived = False
            , createdAt = ctx.currentTime
            , memberCount = 1 + List.length output.virtualMembers
            , myBalanceCents = 0
            }

        signingKeyPair : Signature.SigningKeyPair
        signingKeyPair =
            Signature.importSigningKeyPair ctx.identity.signingKeyPair

        generateEnvelopes : ConcurrentTask Idb.Error (List Event.Envelope)
        generateEnvelopes =
            ConcurrentTask.Time.now
                |> ConcurrentTask.map
                    (\now ->
                        List.map2 (\eventId payload -> Event.wrap eventId now (author ctx) payload "")
                            eventIds
                            payloads
                    )
                |> ConcurrentTask.andThen
                    (\unsignedEnvelopes ->
                        List.map (signEnvelope signingKeyPair) unsignedEnvelopes
                            |> ConcurrentTask.batch
                    )

        allTasks : List Event.Envelope -> ConcurrentTask Idb.Error Group.Summary
        allTasks allEvents =
            let
                allEventIds : List String
                allEventIds =
                    List.map .id allEvents
            in
            Crypto.generateGroupKey
                |> ConcurrentTask.andThen
                    (\key ->
                        Storage.saveGroupSummary ctx.db summary
                            |> ConcurrentTask.andThen (\_ -> Storage.saveGroupKey ctx.db groupId (Symmetric.exportKey key))
                            |> ConcurrentTask.andThen (\_ -> Storage.saveEvents ctx.db groupId allEvents)
                            |> ConcurrentTask.andThen (\_ -> Storage.addUnpushedIds ctx.db groupId allEventIds)
                            |> ConcurrentTask.map (\_ -> summary)
                    )
    in
    ( ctx.runner, Cmd.none )
        |> Runner.andRun onComplete (generateEnvelopes |> ConcurrentTask.andThen allTasks)
        |> Tuple.mapFirst
            (\r ->
                { runner = r
                , randomSeed = seedAfter
                , uuidState = uuidStateAfter
                }
            )



-- Import Splitwise Group


{-| Inputs for building a new group from a parsed Splitwise CSV export.
`rate c` gives the value of one unit of currency `c` in the default currency,
used only to fill `defaultCurrencyAmount` on non-default-currency entries.
-}
type alias SplitwiseImportConfig =
    { groupName : String
    , creatorName : String
    , claimedMemberIndex : Maybe Int
    , defaultCurrency : Currency
    , rate : Currency -> Float
    , parsed : SplitwiseImport.Parsed
    }


{-| Create a new group from a parsed Splitwise export. The importer is the (Real)
creator; they either take over one Splitwise participant (`claimedMemberIndex`)
or join as a new member, in which case every participant becomes a Virtual
member. One signed event is emitted per reconstructed entry, on top of the
group/member creation events.
-}
importSplitwiseGroup : Context msg -> (ConcurrentTask.Response Idb.Error Group.Summary -> msg) -> SplitwiseImportConfig -> ( State msg, Cmd msg )
importSplitwiseGroup ctx onComplete cfg =
    let
        memberNames : List String
        memberNames =
            cfg.parsed.memberNames

        ( groupId, seed1 ) =
            IdGen.groupId ctx.randomSeed

        ( virtualMemberIds, seed2 ) =
            IdGen.v4batch (List.length memberNames) seed1

        isClaimed : Int -> Bool
        isClaimed index =
            cfg.claimedMemberIndex == Just index

        -- For each Splitwise column: the member id to use in reconstructed
        -- entries (the creator's id for the claimed column, else a fresh id).
        memberIds : List Member.Id
        memberIds =
            List.indexedMap
                (\index virtualId ->
                    if isClaimed index then
                        ctx.identity.publicKeyHash

                    else
                        virtualId
                )
                virtualMemberIds

        virtualMembers : List ( Member.Id, String )
        virtualMembers =
            List.map2 Tuple.pair virtualMemberIds memberNames
                |> List.indexedMap Tuple.pair
                |> List.filterMap
                    (\( index, idName ) ->
                        if isClaimed index then
                            Nothing

                        else
                            Just idName
                    )

        kinds : List Entry.Kind
        kinds =
            List.filterMap
                (SplitwiseImport.reconstruct
                    { memberIds = memberIds
                    , defaultCurrency = cfg.defaultCurrency
                    , rate = cfg.rate
                    }
                )
                cfg.parsed.rows

        ( entryIds, seedAfter ) =
            IdGen.v4batch (List.length kinds) seed2

        ( eventIds, uuidStateAfter ) =
            IdGen.v7batch (2 + List.length virtualMembers + List.length kinds) ctx.currentTime ctx.uuidState

        payloads : List Event.Payload
        payloads =
            Event.createGroup
                { name = cfg.groupName
                , defaultCurrency = cfg.defaultCurrency
                , creator = ( ctx.identity.publicKeyHash, cfg.creatorName )
                , virtualMembers = virtualMembers
                }
                ++ List.map2
                    (\entryId kind ->
                        Event.EntryAdded
                            { meta = Entry.newMetadata entryId ctx.identity.publicKeyHash ctx.currentTime
                            , kind = kind
                            }
                    )
                    entryIds
                    kinds

        summary : Group.Summary
        summary =
            { id = groupId
            , name = cfg.groupName
            , defaultCurrency = cfg.defaultCurrency
            , isSubscribed = False
            , isArchived = False
            , createdAt = ctx.currentTime
            , memberCount = 1 + List.length virtualMembers
            , myBalanceCents = 0
            }

        signingKeyPair : Signature.SigningKeyPair
        signingKeyPair =
            Signature.importSigningKeyPair ctx.identity.signingKeyPair

        generateEnvelopes : ConcurrentTask Idb.Error (List Event.Envelope)
        generateEnvelopes =
            ConcurrentTask.Time.now
                |> ConcurrentTask.map
                    (\now ->
                        List.map2 (\eventId payload -> Event.wrap eventId now (author ctx) payload "")
                            eventIds
                            payloads
                    )
                |> ConcurrentTask.andThen
                    (\unsignedEnvelopes ->
                        List.map (signEnvelope signingKeyPair) unsignedEnvelopes
                            |> ConcurrentTask.batch
                    )

        allTasks : List Event.Envelope -> ConcurrentTask Idb.Error Group.Summary
        allTasks allEvents =
            Crypto.generateGroupKey
                |> ConcurrentTask.andThen
                    (\key ->
                        Storage.saveGroupSummary ctx.db summary
                            |> ConcurrentTask.andThen (\_ -> Storage.saveGroupKey ctx.db groupId (Symmetric.exportKey key))
                            |> ConcurrentTask.andThen (\_ -> Storage.saveEvents ctx.db groupId allEvents)
                            |> ConcurrentTask.andThen (\_ -> Storage.addUnpushedIds ctx.db groupId (List.map .id allEvents))
                            |> ConcurrentTask.map (\_ -> summary)
                    )
    in
    ( ctx.runner, Cmd.none )
        |> Runner.andRun onComplete (generateEnvelopes |> ConcurrentTask.andThen allTasks)
        |> Tuple.mapFirst
            (\r ->
                { runner = r
                , randomSeed = seedAfter
                , uuidState = uuidStateAfter
                }
            )



-- New Entry


{-| Submit a new entry (expense or transfer) to a group.
-}
newEntry : Context msg -> LoadedGroup -> NewEntryShared.Output -> ( State msg, Cmd msg )
newEntry ctx loaded output =
    let
        ( entryId, seedAfter ) =
            IdGen.v4 ctx.randomSeed

        ( eventId, uuidStateAfter ) =
            IdGen.v7 ctx.currentTime ctx.uuidState

        payload : Time.Posix -> Event.Payload
        payload now =
            Event.EntryAdded
                { meta = Entry.newMetadata entryId ctx.identity.publicKeyHash now
                , kind = Page.Group.NewEntry.outputToKind output
                }
    in
    attempt { ctx | randomSeed = seedAfter, uuidState = uuidStateAfter }
        (\now -> Event.wrap eventId now (author ctx) (payload now) "")
        loaded.summary.id



-- Edit Entry


{-| Submit an edit to an existing entry. Returns Nothing if the entry is not found.
-}
editEntry : Context msg -> LoadedGroup -> Entry.Id -> NewEntryShared.Output -> Maybe ( State msg, Cmd msg )
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

                entry : Entry.Entry
                entry =
                    Page.Group.NewEntry.outputToKind output
                        |> Entry.replace entryState.currentVersion.meta newEntryId
            in
            Just
                (attempt { ctx | randomSeed = seedAfter, uuidState = uuidStateAfter }
                    (\now -> Event.wrap eventId now (author ctx) (Event.EntryModified entry) "")
                    loaded.summary.id
                )



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
    in
    attempt { ctx | uuidState = uuidStateAfter }
        (\now -> Event.wrap eventId now (author ctx) payload "")
        loaded.summary.id



-- Member Event (generic)


{-| Submit a generic event payload to a group.
-}
event : Context msg -> LoadedGroup -> Event.Payload -> ( State msg, Cmd msg )
event =
    simpleEvent


{-| Same as `event`, but also returns the freshly generated envelope id.
Useful when the caller needs to track completion of one or more submitted
events (e.g. a multi-event merge).
-}
eventWithId : Context msg -> LoadedGroup -> Event.Payload -> ( State msg, Cmd msg, Event.Id )
eventWithId ctx loaded payload =
    let
        ( eventId, uuidStateAfter ) =
            IdGen.v7 ctx.currentTime ctx.uuidState

        ( state, cmd ) =
            attempt { ctx | uuidState = uuidStateAfter }
                (\now -> Event.wrap eventId now (author ctx) payload "")
                loaded.summary.id
    in
    ( state, cmd, eventId )



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
    in
    attempt { ctx | randomSeed = seedAfter, uuidState = uuidStateAfter }
        (\now -> Event.wrap eventId now (author ctx) payload "")
        loaded.summary.id



-- Helpers


{-| Result of applying a sync to a loaded group: the updated group plus any new events from the server.
-}
type alias SyncApplyResult =
    { updatedGroup : LoadedGroup
    , newEvents : List Event.Envelope
    , pullCursor : Int
    }


{-| Apply a sync result to a loaded group: deduplicate pulled events, update state, clear pushed IDs.
Events are merged in sorted order. If any new events conflict with existing events in the overlap
window (same entity, order-dependent resolution), the group state is rebuilt from scratch.
-}
applySyncResult : Set String -> Server.SyncResult -> LoadedGroup -> SyncApplyResult
applySyncResult pushedIds syncResult loaded =
    let
        pullResult : Server.PullResult
        pullResult =
            syncResult.pullResult

        existingIds : Set String
        existingIds =
            List.map .id loaded.events |> Set.fromList

        newEvents : List Event.Envelope
        newEvents =
            List.filter (\e -> not (Set.member e.id existingIds)) pullResult.events

        remainingUnpushedIds : Set String
        remainingUnpushedIds =
            Set.diff loaded.unpushedIds pushedIds

        -- Sort only new events, then merge with existing (already sorted) events.
        -- loaded.events is newest-first; new events need sorting before merge.
        sortedNewEvents : List Event.Envelope
        sortedNewEvents =
            Event.sortEvents newEvents

        mergedEventsNewestFirst : List Event.Envelope
        mergedEventsNewestFirst =
            mergeEventsNewestFirst (List.reverse sortedNewEvents) loaded.events

        -- Check for conflicts: find the overlap window (existing events concurrent with new events)
        oldestNewTimestamp : Maybe Int
        oldestNewTimestamp =
            List.head sortedNewEvents
                |> Maybe.map (.clientTimestamp >> Time.posixToMillis)

        overlapEvents : List Event.Envelope
        overlapEvents =
            case oldestNewTimestamp of
                Just ts ->
                    List.filter (\e -> Time.posixToMillis e.clientTimestamp >= ts) loaded.events

                Nothing ->
                    []

        needsRebuild : Bool
        needsRebuild =
            hasConflicts sortedNewEvents overlapEvents

        updatedGroupState : GroupState.GroupState
        updatedGroupState =
            if needsRebuild then
                GroupState.applyEvents (List.reverse mergedEventsNewestFirst) GroupState.empty

            else
                GroupState.applyEvents sortedNewEvents loaded.groupState
    in
    { updatedGroup =
        { loaded
            | events = mergedEventsNewestFirst
            , groupState = updatedGroupState
            , syncCursor = Just pullResult.cursor
            , unpushedIds = remainingUnpushedIds
        }
    , newEvents = sortedNewEvents
    , pullCursor = pullResult.cursor
    }


{-| Check if any new events conflict with existing events in the overlap window.
Conflictual pairs modify the same entity with order-dependent resolution.
-}
hasConflicts : List Event.Envelope -> List Event.Envelope -> Bool
hasConflicts newEvents overlapEvents =
    List.any (\new -> List.any (areConflicting new) overlapEvents) newEvents


{-| Two events conflict if they modify the same entity in an order-dependent way.
-}
areConflicting : Event.Envelope -> Event.Envelope -> Bool
areConflicting a b =
    case ( a.payload, b.payload ) of
        ( Event.MemberRenamed r1, Event.MemberRenamed r2 ) ->
            r1.rootId == r2.rootId

        ( Event.MemberRetired r1, Event.MemberUnretired r2 ) ->
            r1.rootId == r2.rootId

        ( Event.MemberUnretired r1, Event.MemberRetired r2 ) ->
            r1.rootId == r2.rootId

        ( Event.MemberMetadataUpdated r1, Event.MemberMetadataUpdated r2 ) ->
            r1.rootId == r2.rootId

        ( Event.GroupMetadataUpdated _, Event.GroupMetadataUpdated _ ) ->
            True

        ( Event.SettlementPreferencesUpdated r1, Event.SettlementPreferencesUpdated r2 ) ->
            r1.memberRootId == r2.memberRootId

        ( Event.EntryDeleted r1, Event.EntryUndeleted r2 ) ->
            r1.rootId == r2.rootId

        ( Event.EntryUndeleted r1, Event.EntryDeleted r2 ) ->
            r1.rootId == r2.rootId

        ( Event.EntryDeleted r1, Event.EntryModified e2 ) ->
            r1.rootId == e2.meta.rootId

        ( Event.EntryModified e1, Event.EntryDeleted r2 ) ->
            e1.meta.rootId == r2.rootId

        ( Event.EntryUndeleted r1, Event.EntryModified e2 ) ->
            r1.rootId == e2.meta.rootId

        ( Event.EntryModified e1, Event.EntryUndeleted r2 ) ->
            e1.meta.rootId == r2.rootId

        _ ->
            False


{-| Merge two lists of events, both sorted newest-first. Tail-recursive.
-}
mergeEventsNewestFirst : List Event.Envelope -> List Event.Envelope -> List Event.Envelope
mergeEventsNewestFirst xs ys =
    mergeEventsHelp xs ys []


mergeEventsHelp : List Event.Envelope -> List Event.Envelope -> List Event.Envelope -> List Event.Envelope
mergeEventsHelp xs ys acc =
    case ( xs, ys ) of
        ( [], _ ) ->
            List.reverse acc ++ ys

        ( _, [] ) ->
            List.reverse acc ++ xs

        ( x :: xr, y :: yr ) ->
            case Event.compareEnvelopes x y of
                LT ->
                    -- x is older, so y comes first (newest-first)
                    mergeEventsHelp xs yr (y :: acc)

                _ ->
                    mergeEventsHelp xr ys (x :: acc)


{-| Build the persistence tasks to run after a successful sync.
-}
postSyncTasks : Idb.Db -> Server.ServerContext -> SyncApplyResult -> ConcurrentTask Idb.Error ()
postSyncTasks db ctx result =
    List.filterMap identity
        [ Just <| Storage.saveUnpushedIds db ctx.groupId result.updatedGroup.unpushedIds
        , if List.isEmpty result.newEvents then
            Nothing

          else
            Just <| Storage.saveEvents db ctx.groupId result.newEvents
        , if result.pullCursor > 0 then
            Just <| Storage.saveSyncCursor db ctx.groupId result.pullCursor

          else
            Nothing
        , Just <| ConcurrentTask.onError (\_ -> ConcurrentTask.succeed ()) (Server.subscribeToGroup ctx)
        ]
        |> ConcurrentTask.batch
        |> ConcurrentTask.map (\_ -> ())
