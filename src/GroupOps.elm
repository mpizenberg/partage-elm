module GroupOps exposing
    ( CompactionOutcome
    , CompactionStep(..)
    , Context
    , LoadedGroup
    , MigrationResult
    , State
    , SyncApplyResult
    , addMember
    , addUnpushedId
    , appendEvent
    , applySyncResult
    , clampAfterLatest
    , compactionStep
    , deleteEntry
    , editEntry
    , event
    , eventWithId
    , importSplitwiseGroup
    , initLoadedGroup
    , migrateGroup
    , newEntry
    , newGroup
    , postSyncTasks
    , restoreEntry
    )

import ConcurrentTask exposing (ConcurrentTask)
import ConcurrentTask.Time
import Dict
import Domain.Compaction as Compaction
import Domain.Currency exposing (Currency)
import Domain.Entry as Entry
import Domain.Event as Event
import Domain.Group as Group
import Domain.GroupState as GroupState
import Domain.Member as Member
import Domain.MigrationCuration as MigrationCuration
import Domain.TamperSignals as TamperSignals exposing (TamperSignals)
import Form.NewGroup
import IndexedDb as Idb
import Infra.ConcurrentTaskExtra as Runner exposing (TaskRunner)
import Infra.Crypto as Crypto
import Infra.EventVerification as EventVerification
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
import WebCrypto
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
    , syncCursor : Maybe Group.SyncCursor
    , unpushedIds : Set String
    , tamperSignals : TamperSignals
    , suspicionDismissals : Set String
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
initLoadedGroup : List Event.Envelope -> Group.Summary -> Symmetric.Key -> Maybe Group.SyncCursor -> Set String -> TamperSignals -> Set String -> LoadedGroup
initLoadedGroup events summary key cursor unpushed tamperSignals suspicionDismissals =
    -- We store the events in reverse order for efficient prepending of new events
    { events = List.reverse events
    , groupState = GroupState.applyEvents events GroupState.empty
    , summary = summary
    , groupKey = key
    , syncCursor = cursor
    , unpushedIds = unpushed
    , tamperSignals = tamperSignals
    , suspicionDismissals = suspicionDismissals
    }


attempt : Context msg -> (Time.Posix -> Event.Envelope) -> LoadedGroup -> ( State msg, Cmd msg )
attempt ctx makeUnsignedEnvelope loaded =
    let
        signingKeyPair : Signature.SigningKeyPair
        signingKeyPair =
            Signature.importSigningKeyPair ctx.identity.signingKeyPair

        groupId : Group.Id
        groupId =
            loaded.summary.id

        task : ConcurrentTask Idb.Error Event.Envelope
        task =
            ConcurrentTask.map (clampAfterLatest loaded.events >> makeUnsignedEnvelope) ConcurrentTask.Time.now
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


{-| Clamp a wall-clock time to sort strictly after every event in the given
newest-first list. A device with a slow clock could otherwise author an event
that sorts before state it has already applied — kept by the incremental fast
path but dropped by every full replay, so devices would disagree until the
edit silently vanished. Clamping also guarantees `appendEvent`'s prepend
preserves the sort order of the event list.
-}
clampAfterLatest : List Event.Envelope -> Time.Posix -> Time.Posix
clampAfterLatest newestFirst now =
    case newestFirst of
        [] ->
            now

        latest :: _ ->
            Time.millisToPosix
                (max (Time.posixToMillis now) (Time.posixToMillis latest.clientTimestamp + 1))


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
            , lastSyncedAt = ctx.currentTime
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


{-| The two summaries a migration touches: the fresh group it minted and the old
group it replaced (now archived).
-}
type alias MigrationResult =
    { newSummary : Group.Summary
    , oldSummary : Group.Summary
    }


{-| Migrate a compromised group to a fresh one (spec §11.7). Mint a new id and
key, re-home the local verified history — dropping the events `selection` excises
from each excluded identity, resolving any per-identity time boundary against the
relay's `order` (`id → seq`) map — and queue what survives for push so the new
group registers on the relay on its first sync. The signature covers the
envelope, not the group id, so the carried events replay to the state they held
in the old group. The old
group is archived; it is left to the relay TTL. The new key
must reach only trusted members, out of band.
-}
migrateGroup : Context msg -> (ConcurrentTask.Response Idb.Error MigrationResult -> msg) -> Dict.Dict Event.Id Int -> Dict.Dict Member.Id MigrationCuration.Bound -> LoadedGroup -> ( State msg, Cmd msg )
migrateGroup ctx onComplete order selection loaded =
    let
        ( newId, seedAfter ) =
            IdGen.groupId ctx.randomSeed

        oldSummary : Group.Summary
        oldSummary =
            { loadedSummary | isArchived = True }

        loadedSummary : Group.Summary
        loadedSummary =
            loaded.summary

        task : ConcurrentTask Idb.Error MigrationResult
        task =
            ConcurrentTask.map2 Tuple.pair
                (EventVerification.filterVerifiedEvents GroupState.empty loaded.events
                    |> ConcurrentTask.map (MigrationCuration.curateEvents order selection)
                )
                Crypto.generateGroupKey
                |> ConcurrentTask.andThen
                    (\( verified, key ) ->
                        let
                            newSummary : Group.Summary
                            newSummary =
                                GroupState.summarize ctx.identity.publicKeyHash newId ctx.currentTime (GroupState.applyEvents verified GroupState.empty)
                        in
                        ConcurrentTask.batch
                            [ Storage.saveGroup ctx.db newSummary (Just (Symmetric.exportKey key)) verified Nothing
                            , Storage.addUnpushedIds ctx.db newId (List.map .id verified)
                            , Storage.saveGroupSummary ctx.db oldSummary |> ConcurrentTask.map (\_ -> ())
                            ]
                            |> ConcurrentTask.map (\_ -> { newSummary = newSummary, oldSummary = oldSummary })
                    )
    in
    ( ctx.runner, Cmd.none )
        |> Runner.andRun onComplete task
        |> Tuple.mapFirst
            (\r ->
                { runner = r
                , randomSeed = seedAfter
                , uuidState = ctx.uuidState
                }
            )


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
            , lastSyncedAt = ctx.currentTime
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
        loaded



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
                    loaded
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
        loaded



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
                loaded
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
        loaded



-- Compaction


{-| The one compaction action to take after a sync, in priority order:
execute a quorumed proposal (only while the relay is still worth
compacting), else sign approvals, else propose. Approvals and proposals
are returned as data — authoring them needs the caller's submit
machinery; execution talks to the relay right here.
-}
type CompactionStep
    = NoCompactionStep
    | ApproveProposals (List Event.Id)
    | ProposalReady { uptoEventId : Event.Id, eventCount : Int, manifestHash : String }
    | ExecutedCompaction Server.CompactOutcome


{-| A compaction step plus the orthogonal tamper signal: `manifestMismatch` is
True when a quorum-approved proposal reached this replica but its recomputed
manifest hash disagrees with the claimed one (spec §11.7). The replica then
declines to execute and falls back to `step` (propose/approve/nothing).
-}
type alias CompactionOutcome =
    { step : CompactionStep
    , manifestMismatch : Bool
    }


compactionStep :
    { serverCtx : Server.ServerContext
    , actorId : String
    , myRoot : Member.Id
    , recordCount : Int
    , now : Time.Posix
    }
    -> LoadedGroup
    -> ConcurrentTask Server.Error CompactionOutcome
compactionStep cfg loaded =
    let
        state : GroupState.GroupState
        state =
            loaded.groupState

        resolvers : { resolveRoot : Member.Id -> Maybe Member.Id, isRetired : Member.Id -> Bool }
        resolvers =
            { resolveRoot = GroupState.resolveMemberRootId state
            , isRetired =
                \root ->
                    Dict.get root state.members
                        |> Maybe.map .isRetired
                        |> Maybe.withDefault False
            }

        relayWorthCompacting : Bool
        relayWorthCompacting =
            cfg.recordCount >= Compaction.recordCountTrigger

        clean : CompactionStep -> CompactionOutcome
        clean step =
            { step = step, manifestMismatch = False }

        approveOrPropose : ConcurrentTask Server.Error CompactionStep
        approveOrPropose =
            compactionApprovalsDue cfg.myRoot loaded
                |> ConcurrentTask.andThen
                    (\proposalIds ->
                        case ( proposalIds, relayWorthCompacting, Compaction.proposalDraft cfg.now loaded.events ) of
                            ( _ :: _, _, _ ) ->
                                ConcurrentTask.succeed (ApproveProposals proposalIds)

                            ( [], True, Just draft ) ->
                                WebCrypto.sha256 draft.manifestInput
                                    |> ConcurrentTask.mapError Server.CryptoError
                                    |> ConcurrentTask.map
                                        (\hash ->
                                            ProposalReady
                                                { uptoEventId = draft.uptoEventId
                                                , eventCount = draft.eventCount
                                                , manifestHash = hash
                                                }
                                        )

                            _ ->
                                ConcurrentTask.succeed NoCompactionStep
                    )
    in
    case ( Compaction.executableProposal resolvers loaded.events, relayWorthCompacting ) of
        ( Just executable, True ) ->
            -- Execute only when this replica's manifest matches the quorumed
            -- claim: an executor never consolidates a history it disagrees
            -- with, no matter how many others signed it. Disagreement here is
            -- the advisory manifest-mismatch signal.
            WebCrypto.sha256 executable.manifestInput
                |> ConcurrentTask.mapError Server.CryptoError
                |> ConcurrentTask.andThen
                    (\hash ->
                        if hash == executable.claimedHash then
                            Server.compact cfg.serverCtx cfg.actorId executable.prefix
                                |> ConcurrentTask.map (\outcome -> clean (ExecutedCompaction outcome))

                        else
                            approveOrPropose
                                |> ConcurrentTask.map (\step -> { step = step, manifestMismatch = True })
                    )

        _ ->
            ConcurrentTask.map clean approveOrPropose


{-| The ids of compaction proposals the member `myRoot` should approve:
pending per `Compaction.pendingApprovals`, and whose recomputed manifest
hash equals the claimed one — the approval signature attests "my replica's
history up to this boundary is exactly this".
-}
compactionApprovalsDue : Member.Id -> LoadedGroup -> ConcurrentTask x (List Event.Id)
compactionApprovalsDue myRoot loaded =
    Compaction.pendingApprovals (GroupState.resolveMemberRootId loaded.groupState) myRoot loaded.events
        |> List.map
            (\pending ->
                WebCrypto.sha256 pending.manifestInput
                    |> ConcurrentTask.map
                        (\hash ->
                            if hash == pending.claimedHash then
                                Just pending.proposalId

                            else
                                Nothing
                        )
            )
        |> ConcurrentTask.batch
        |> ConcurrentTask.map (List.filterMap identity)
        |> ConcurrentTask.onError (\_ -> ConcurrentTask.succeed [])



-- Helpers


{-| Result of applying a sync to a loaded group: the updated group plus any new events from the server.
-}
type alias SyncApplyResult =
    { updatedGroup : LoadedGroup
    , newEvents : List Event.Envelope
    , pullCursor : Group.SyncCursor
    }


{-| Apply a sync result to a loaded group: deduplicate pulled events, update state, clear pushed IDs.
Events are merged in sorted order. If any new events conflict with existing events in the overlap
window (same entity, order-dependent resolution), the group state is rebuilt from scratch.
`now` stamps any tamper signal this sync raised (spec §11.7).
-}
applySyncResult : Time.Posix -> Set String -> Server.SyncResult -> LoadedGroup -> SyncApplyResult
applySyncResult now pushedIds syncResult loaded =
    let
        pullResult : Server.PullResult
        pullResult =
            syncResult.pullResult

        existingIds : Set String
        existingIds =
            List.map .id loaded.events |> Set.fromList

        -- Local events the relay no longer holds after a reset: lost to a
        -- purge, truncation, or unsanctioned compaction.
        lostOnReset : Set String
        lostOnReset =
            if pullResult.didReset then
                Set.diff existingIds (Set.fromList (List.map .id pullResult.events))

            else
                Set.empty

        tamperSignals : TamperSignals
        tamperSignals =
            loaded.tamperSignals
                |> TamperSignals.recordForgedAuthors pullResult.forgedAuthors now
                |> (if Set.isEmpty lostOnReset then
                        identity

                    else
                        TamperSignals.recordResetWithLoss now
                   )

        newEvents : List Event.Envelope
        newEvents =
            List.filter (\e -> not (Set.member e.id existingIds)) pullResult.events

        -- Heal re-push: a reset pull returns everything the relay still holds,
        -- so any local event absent from it was lost and must be re-pushed.
        -- `unpushedIds` only tracks never-pushed events, so the gap is added
        -- here; the follow-up sync it triggers does the actual pushing.
        remainingUnpushedIds : Set String
        remainingUnpushedIds =
            Set.union (Set.diff loaded.unpushedIds pushedIds) lostOnReset

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
            , syncCursor = Just { seq = pullResult.cursor, epoch = pullResult.epoch }
            , unpushedIds = remainingUnpushedIds
            , tamperSignals = tamperSignals
        }
    , newEvents = sortedNewEvents
    , pullCursor = { seq = pullResult.cursor, epoch = pullResult.epoch }
    }


{-| Check if any new events conflict with existing events in the overlap window.
Conflictual pairs modify the same entity with order-dependent resolution.
-}
hasConflicts : List Event.Envelope -> List Event.Envelope -> Bool
hasConflicts newEvents overlapEvents =
    List.any (\new -> List.any (areConflicting new) overlapEvents) newEvents


{-| Two events conflict if their application order changes the outcome.
-}
areConflicting : Event.Envelope -> Event.Envelope -> Bool
areConflicting a b =
    orderDependent a.payload b.payload || orderDependent b.payload a.payload


{-| Order-dependent payload pairs, listed in one orientation;
`areConflicting` checks both.
-}
orderDependent : Event.Payload -> Event.Payload -> Bool
orderDependent a b =
    case ( a, b ) of
        ( Event.MemberRenamed r1, Event.MemberRenamed r2 ) ->
            r1.rootId == r2.rootId

        ( Event.MemberRetired r1, Event.MemberUnretired r2 ) ->
            r1.rootId == r2.rootId

        ( Event.MemberMetadataUpdated r1, Event.MemberMetadataUpdated r2 ) ->
            r1.rootId == r2.rootId

        ( Event.GroupMetadataUpdated _, Event.GroupMetadataUpdated _ ) ->
            True

        -- Only the first GroupCreated in sort order applies, and it resets
        -- the metadata fields GroupMetadataUpdated edits.
        ( Event.GroupCreated _, Event.GroupCreated _ ) ->
            True

        ( Event.GroupCreated _, Event.GroupMetadataUpdated _ ) ->
            True

        ( Event.SettlementPreferencesUpdated r1, Event.SettlementPreferencesUpdated r2 ) ->
            r1.memberRootId == r2.memberRootId

        ( Event.EntryDeleted r1, Event.EntryUndeleted r2 ) ->
            r1.rootId == r2.rootId

        ( Event.EntryModified e1, Event.EntryDeleted r2 ) ->
            e1.meta.rootId == r2.rootId

        ( Event.EntryModified e1, Event.EntryUndeleted r2 ) ->
            e1.meta.rootId == r2.rootId

        -- An event referencing an entity (or an entry version) is ignored by
        -- replay when it sorts before the event creating what it references.
        ( Event.EntryModified e1, Event.EntryModified e2 ) ->
            e1.meta.rootId == e2.meta.rootId

        ( Event.EntryAdded e1, Event.EntryModified e2 ) ->
            e1.meta.rootId == e2.meta.rootId

        ( Event.EntryAdded e1, Event.EntryDeleted r2 ) ->
            e1.meta.rootId == r2.rootId

        ( Event.EntryAdded e1, Event.EntryUndeleted r2 ) ->
            e1.meta.rootId == r2.rootId

        ( Event.MemberCreated m1, Event.MemberRenamed r2 ) ->
            m1.memberId == r2.rootId

        ( Event.MemberCreated m1, Event.MemberRetired r2 ) ->
            m1.memberId == r2.rootId

        ( Event.MemberCreated m1, Event.MemberUnretired r2 ) ->
            m1.memberId == r2.rootId

        ( Event.MemberCreated m1, Event.MemberMetadataUpdated r2 ) ->
            m1.memberId == r2.rootId

        ( Event.MemberCreated m1, Event.MemberLinked l2 ) ->
            m1.memberId == l2.rootId

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
        , if TamperSignals.isClean result.updatedGroup.tamperSignals then
            Nothing

          else
            Just <| Storage.saveTamperSignals db ctx.groupId result.updatedGroup.tamperSignals
        , if List.isEmpty result.newEvents then
            Nothing

          else
            Just <| Storage.saveEvents db ctx.groupId result.newEvents
        , Just <| Storage.saveSyncCursor db ctx.groupId result.pullCursor
        , if result.updatedGroup.summary.isArchived then
            Nothing

          else
            Just <| ConcurrentTask.onError (\_ -> ConcurrentTask.succeed ()) (Server.subscribeToGroup ctx)
        ]
        |> ConcurrentTask.batch
        |> ConcurrentTask.map (\_ -> ())
