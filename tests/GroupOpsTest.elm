module GroupOpsTest exposing (suite)

import Dict
import Domain.Currency exposing (Currency(..))
import Domain.Entry as Entry exposing (Kind(..))
import Domain.Event as Event exposing (Payload(..))
import Domain.Group as Group
import Domain.GroupState as GroupState
import Domain.Member as Member
import Domain.TamperSignals as TamperSignals
import Expect
import GroupOps
import Set
import Test exposing (Test, describe, test)
import TestHelpers exposing (bootstrapMembers, defaultExpenseData, makeEnvelope, makeExpenseEntry)
import Time
import WebCrypto.Symmetric as Symmetric


suite : Test
suite =
    describe "GroupOps"
        [ describe "clampAfterLatest" clampTests
        , describe "applySyncResult with late arrivals" lateArrivalTests
        , describe "applySyncResult after a cursor reset" cursorResetTests
        , describe "applySyncResult heal re-push" healRepushTests
        , describe "applySyncResult tamper signals" tamperSignalTests
        ]


cursorResetTests : List Test
cursorResetTests =
    [ test "a full re-pull from 0 converges without duplicates and adopts the new cursor" <|
        \_ ->
            let
                existing : List Event.Envelope
                existing =
                    bootstrapMembers
                        ++ [ makeEnvelope "e-add" 100 "alice" (EntryAdded (makeExpenseEntry "entry1" 100 defaultExpenseData)) ]

                fresh : Event.Envelope
                fresh =
                    makeEnvelope "e-fresh" 200 "bob" (EntryDeleted { rootId = "entry1" })

                loaded : GroupOps.LoadedGroup
                loaded =
                    GroupOps.initLoadedGroup existing testSummary (Symmetric.importKey "test-key") (Just 50) Set.empty TamperSignals.empty Set.empty

                result : GroupOps.SyncApplyResult
                result =
                    GroupOps.applySyncResult (Time.millisToPosix 0)
                        Set.empty
                        { pullResult = { events = existing ++ [ fresh ], cursor = 4, undecodable = 0, didReset = True, recordCount = 0, forgedAuthors = [] }, pushedCount = 0 }
                        loaded
            in
            result
                |> Expect.all
                    [ \r ->
                        List.map .id r.updatedGroup.events
                            |> Expect.equal (List.map .id (List.reverse (Event.sortEvents (fresh :: existing))))
                    , \r -> r.updatedGroup.syncCursor |> Expect.equal (Just 4)
                    , \r -> List.map .id r.newEvents |> Expect.equal [ "e-fresh" ]

                    -- The relay returned every local event (plus one new), so
                    -- the heal finds nothing missing to re-push.
                    , \r -> r.updatedGroup.unpushedIds |> Expect.equal Set.empty
                    ]
    ]


healRepushTests : List Test
healRepushTests =
    let
        localLog : List Event.Envelope
        localLog =
            bootstrapMembers
                ++ [ makeEnvelope "e-add" 100 "alice" (EntryAdded (makeExpenseEntry "entry1" 100 defaultExpenseData)) ]

        healAfter : { events : List Event.Envelope, didReset : Bool } -> GroupOps.SyncApplyResult
        healAfter { events, didReset } =
            GroupOps.applySyncResult (Time.millisToPosix 0)
                Set.empty
                { pullResult = { events = events, cursor = 0, undecodable = 0, didReset = didReset, recordCount = 0, forgedAuthors = [] }, pushedCount = 0 }
                (loadedFrom localLog)
    in
    [ test "a purge (reset pull returns nothing) queues every local event for re-push" <|
        \_ ->
            (healAfter { events = [], didReset = True }).updatedGroup.unpushedIds
                |> Expect.equal (Set.fromList (List.map .id localLog))
    , test "a partial loss queues only the events missing from the relay's remaining set" <|
        \_ ->
            (healAfter { events = bootstrapMembers, didReset = True }).updatedGroup.unpushedIds
                |> Expect.equal (Set.singleton "e-add")
    , test "a normal pull (no reset) never queues a re-push" <|
        \_ ->
            (healAfter { events = [], didReset = False }).updatedGroup.unpushedIds
                |> Expect.equal Set.empty
    ]


tamperSignalTests : List Test
tamperSignalTests =
    let
        syncWithForged : List String -> GroupOps.SyncApplyResult
        syncWithForged forgedAuthors =
            GroupOps.applySyncResult (Time.millisToPosix 1000)
                Set.empty
                { pullResult = { events = [], cursor = 0, undecodable = 0, didReset = False, recordCount = 0, forgedAuthors = forgedAuthors }, pushedCount = 0 }
                (loadedFrom bootstrapMembers)
    in
    [ test "a pull carrying forged signatures tallies the claimed authors and raises the banner" <|
        \_ ->
            (syncWithForged [ "impostor", "impostor" ]).updatedGroup.tamperSignals
                |> Expect.all
                    [ TamperSignals.forgedCount >> Expect.equal 2
                    , TamperSignals.bannerWorthy >> Expect.equal True
                    ]
    , test "a clean pull leaves the counters untouched" <|
        \_ ->
            (syncWithForged []).updatedGroup.tamperSignals
                |> TamperSignals.isClean
                |> Expect.equal True
    ]


clampTests : List Test
clampTests =
    let
        latestAt : Int -> List Event.Envelope
        latestAt ts =
            [ makeEnvelope "e1" ts "admin" (EntryDeleted { rootId = "x" }) ]
    in
    [ test "keeps the wall clock when it is past the latest event" <|
        \_ ->
            GroupOps.clampAfterLatest (latestAt 100) (Time.millisToPosix 200)
                |> Expect.equal (Time.millisToPosix 200)
    , test "clamps to just after the latest event when the wall clock is behind" <|
        \_ ->
            GroupOps.clampAfterLatest (latestAt 100) (Time.millisToPosix 40)
                |> Expect.equal (Time.millisToPosix 101)
    , test "keeps the wall clock when there are no events" <|
        \_ ->
            GroupOps.clampAfterLatest [] (Time.millisToPosix 40)
                |> Expect.equal (Time.millisToPosix 40)
    ]


lateArrivalTests : List Test
lateArrivalTests =
    [ test "a modification sorting before its entry's creation is dropped, matching full replay" <|
        \_ ->
            let
                original : Entry.Entry
                original =
                    makeExpenseEntry "entry1" 100 defaultExpenseData

                modified : Entry.Entry
                modified =
                    Entry.replace original.meta "entry1v2" (Expense { defaultExpenseData | amount = 9999 })

                existing : List Event.Envelope
                existing =
                    bootstrapMembers ++ [ makeEnvelope "e-add" 100 "alice" (EntryAdded original) ]

                lateEdit : Event.Envelope
                lateEdit =
                    makeEnvelope "e-edit" 90 "bob" (EntryModified modified)

                result : GroupOps.SyncApplyResult
                result =
                    syncWith [ lateEdit ] (loadedFrom existing)

                replayed : GroupState.GroupState
                replayed =
                    GroupState.applyEvents (Event.sortEvents (lateEdit :: existing)) GroupState.empty
            in
            result
                |> Expect.all
                    [ \r -> r.updatedGroup.groupState |> Expect.equal replayed
                    , \r ->
                        Dict.get "entry1" r.updatedGroup.groupState.entries
                            |> Maybe.map (.currentVersion >> .meta >> .id)
                            |> Expect.equal (Just "entry1")
                    ]
    , test "a rename applied before its member's creation arrives is honored after rebuild" <|
        \_ ->
            let
                existing : List Event.Envelope
                existing =
                    bootstrapMembers
                        ++ [ makeEnvelope "e-rename" 100 "admin" (MemberRenamed { rootId = "carol", oldName = "Carol", newName = "Caroline" }) ]

                lateCreate : Event.Envelope
                lateCreate =
                    makeEnvelope "e-create" 50 "admin" (MemberCreated { memberId = "carol", name = "Carol", memberType = Member.Virtual, addedBy = "admin" })

                result : GroupOps.SyncApplyResult
                result =
                    syncWith [ lateCreate ] (loadedFrom existing)
            in
            Dict.get "carol" result.updatedGroup.groupState.members
                |> Maybe.map .name
                |> Expect.equal (Just "Caroline")
    ]


loadedFrom : List Event.Envelope -> GroupOps.LoadedGroup
loadedFrom events =
    GroupOps.initLoadedGroup events testSummary (Symmetric.importKey "test-key") Nothing Set.empty TamperSignals.empty Set.empty


syncWith : List Event.Envelope -> GroupOps.LoadedGroup -> GroupOps.SyncApplyResult
syncWith newEvents loaded =
    GroupOps.applySyncResult (Time.millisToPosix 0)
        Set.empty
        { pullResult = { events = newEvents, cursor = 1, undecodable = 0, didReset = False, recordCount = 0, forgedAuthors = [] }, pushedCount = 0 }
        loaded


testSummary : Group.Summary
testSummary =
    { id = "g1"
    , name = "Test"
    , defaultCurrency = EUR
    , isSubscribed = False
    , isArchived = False
    , createdAt = Time.millisToPosix 0
    , memberCount = 3
    , myBalanceCents = 0
    , lastSyncedAt = Time.millisToPosix 0
    }
