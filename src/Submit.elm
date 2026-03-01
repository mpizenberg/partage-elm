module Submit exposing
    ( Context
    , LoadedGroup
    , State
    , addMember
    , deleteEntry
    , editEntry
    , event
    , newEntry
    , newGroup
    , restoreEntry
    )

import ConcurrentTask
import Dict
import Domain.Entry as Entry
import Domain.Event as Event
import Domain.Group as Group
import Domain.GroupState as GroupState
import Domain.Member as Member
import Form.NewGroup
import Identity exposing (Identity)
import IndexedDb as Idb
import Json.Encode
import Page.NewEntry
import Random
import Storage exposing (GroupSummary)
import Time
import UUID
import UuidGen


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


type alias State msg =
    { pool : ConcurrentTask.Pool msg
    , randomSeed : Random.Seed
    , uuidState : UUID.V7State
    }


type alias LoadedGroup =
    { groupId : Group.Id
    , events : List Event.Envelope
    , groupState : GroupState.GroupState
    , summary : GroupSummary
    }


attempt : Context msg -> Event.Envelope -> Group.Id -> ( State msg, Cmd msg )
attempt ctx envelope groupId =
    let
        task =
            Storage.saveEvents ctx.db groupId [ envelope ]
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


newGroup : Context msg -> (ConcurrentTask.Response Idb.Error GroupSummary -> msg) -> Form.NewGroup.Output -> ( State msg, Cmd msg )
newGroup ctx onComplete output =
    let
        ( groupId, seed1 ) =
            UuidGen.v4 ctx.randomSeed

        ( virtualMemberIds, seedAfter ) =
            UuidGen.v4batch (List.length output.virtualMembers) seed1

        ( eventIds, uuidStateAfter ) =
            UuidGen.v7batch (2 + List.length output.virtualMembers) ctx.currentTime ctx.uuidState

        allEvents =
            Event.buildGroupCreationEvents
                { creatorId = ctx.identity.publicKeyHash
                , groupName = output.name
                , creatorName = output.creatorName
                , virtualMembers = List.map2 Tuple.pair virtualMemberIds output.virtualMembers
                , eventIds = eventIds
                , currentTime = ctx.currentTime
                }

        summary =
            { id = groupId
            , name = output.name
            , defaultCurrency = output.currency
            }

        task =
            Storage.saveGroupSummary ctx.db summary
                |> ConcurrentTask.andThen (\_ -> Storage.saveEvents ctx.db groupId allEvents)
                |> ConcurrentTask.map (\_ -> summary)

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


newEntry : Context msg -> LoadedGroup -> Page.NewEntry.Output -> ( State msg, Cmd msg )
newEntry ctx loaded output =
    let
        ( entryId, seedAfter ) =
            UuidGen.v4 ctx.randomSeed

        ( eventId, uuidStateAfter ) =
            UuidGen.v7 ctx.currentTime ctx.uuidState

        envelope =
            case output of
                Page.NewEntry.ExpenseOutput data ->
                    Event.buildExpenseEvent
                        { entryId = entryId
                        , eventId = eventId
                        , memberId = ctx.identity.publicKeyHash
                        , currentTime = ctx.currentTime
                        , currency = loaded.summary.defaultCurrency
                        , payerId = data.payerId
                        , beneficiaryIds = data.beneficiaryIds
                        , description = data.description
                        , amountCents = data.amountCents
                        , category = data.category
                        , notes = data.notes
                        , date = data.date
                        }

                Page.NewEntry.TransferOutput data ->
                    Event.buildTransferEvent
                        { entryId = entryId
                        , eventId = eventId
                        , memberId = ctx.identity.publicKeyHash
                        , currentTime = ctx.currentTime
                        , currency = loaded.summary.defaultCurrency
                        , fromMemberId = data.fromMemberId
                        , toMemberId = data.toMemberId
                        , amountCents = data.amountCents
                        , notes = data.notes
                        , date = data.date
                        }
    in
    attempt { ctx | randomSeed = seedAfter, uuidState = uuidStateAfter } envelope loaded.groupId



-- Edit Entry


editEntry : Context msg -> LoadedGroup -> Entry.Id -> Page.NewEntry.Output -> Maybe ( State msg, Cmd msg )
editEntry ctx loaded originalEntryId output =
    case Dict.get originalEntryId loaded.groupState.entries of
        Nothing ->
            Nothing

        Just entryState ->
            let
                ( newEntryId, seedAfter ) =
                    UuidGen.v4 ctx.randomSeed

                ( eventId, uuidStateAfter ) =
                    UuidGen.v7 ctx.currentTime ctx.uuidState

                newKind =
                    Page.NewEntry.outputToKind loaded.summary.defaultCurrency output

                entry =
                    Entry.replace entryState.currentVersion.meta newEntryId newKind

                envelope =
                    Event.wrap eventId ctx.currentTime ctx.identity.publicKeyHash (Event.EntryModified entry)
            in
            Just (attempt { ctx | randomSeed = seedAfter, uuidState = uuidStateAfter } envelope loaded.groupId)



-- Delete / Restore Entry


deleteEntry : Context msg -> LoadedGroup -> Entry.Id -> ( State msg, Cmd msg )
deleteEntry ctx loaded rootId =
    simpleEvent ctx loaded (Event.EntryDeleted { rootId = rootId })


restoreEntry : Context msg -> LoadedGroup -> Entry.Id -> ( State msg, Cmd msg )
restoreEntry ctx loaded rootId =
    simpleEvent ctx loaded (Event.EntryUndeleted { rootId = rootId })


simpleEvent : Context msg -> LoadedGroup -> Event.Payload -> ( State msg, Cmd msg )
simpleEvent ctx loaded payload =
    let
        ( eventId, uuidStateAfter ) =
            UuidGen.v7 ctx.currentTime ctx.uuidState

        envelope =
            Event.wrap eventId ctx.currentTime ctx.identity.publicKeyHash payload
    in
    attempt { ctx | uuidState = uuidStateAfter } envelope loaded.groupId



-- Member Event (generic)


event : Context msg -> LoadedGroup -> Event.Payload -> ( State msg, Cmd msg )
event =
    simpleEvent



-- Add Member


addMember : Context msg -> LoadedGroup -> { name : String } -> ( State msg, Cmd msg )
addMember ctx loaded output =
    let
        ( newMemberId, seedAfter ) =
            UuidGen.v4 ctx.randomSeed

        ( eventId, uuidStateAfter ) =
            UuidGen.v7 ctx.currentTime ctx.uuidState

        payload =
            Event.MemberCreated
                { memberId = newMemberId
                , name = output.name
                , memberType = Member.Virtual
                , addedBy = ctx.identity.publicKeyHash
                }

        envelope =
            Event.wrap eventId ctx.currentTime ctx.identity.publicKeyHash payload
    in
    attempt { ctx | randomSeed = seedAfter, uuidState = uuidStateAfter } envelope loaded.groupId
