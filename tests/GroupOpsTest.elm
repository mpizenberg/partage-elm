module GroupOpsTest exposing (suite)

import Dict
import Domain.Currency exposing (Currency(..))
import Domain.Entry as Entry exposing (Kind(..))
import Domain.Event as Event exposing (Payload(..))
import Domain.Group as Group
import Domain.GroupState as GroupState
import Domain.Member as Member
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
    GroupOps.initLoadedGroup events testSummary (Symmetric.importKey "test-key") Nothing Set.empty


syncWith : List Event.Envelope -> GroupOps.LoadedGroup -> GroupOps.SyncApplyResult
syncWith newEvents loaded =
    GroupOps.applySyncResult Set.empty
        { pullResult = { events = newEvents, cursor = 1, undecodable = 0 }, pushedCount = 0 }
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
    }
