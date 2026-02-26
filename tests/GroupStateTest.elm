module GroupStateTest exposing (..)

import Dict
import Domain.Entry as Entry exposing (Beneficiary(..), Kind(..))
import Domain.Event as Event exposing (Envelope, Payload(..))
import Domain.GroupState as GroupState exposing (GroupState)
import Domain.Member as Member
import Expect
import Fuzz exposing (Fuzzer)
import Test exposing (..)
import TestHelpers exposing (..)
import Time


suite : Test
suite =
    describe "GroupState"
        [ memberCreationTests
        , memberRenameTests
        , memberRetireTests
        , memberUnretireTests
        , memberReplacementTests
        , groupMetadataTests
        , eventOrderingTests
        ]


createAliceEvents : List Envelope
createAliceEvents =
    [ makeEnvelope "e1"
        1000
        "admin"
        (MemberCreated { memberId = "alice", name = "Alice", memberType = Member.Real, addedBy = "admin" })
    ]


memberCreationTests : Test
memberCreationTests =
    describe "Member creation"
        [ test "sets the member name" <|
            \_ ->
                let
                    state =
                        GroupState.applyEvents createAliceEvents
                in
                Dict.get "alice" state.members
                    |> Maybe.map .name
                    |> Expect.equal (Just "Alice")
        , test "sets rootId to member's own id" <|
            \_ ->
                let
                    state =
                        GroupState.applyEvents createAliceEvents
                in
                Dict.get "alice" state.members
                    |> Maybe.map .rootId
                    |> Expect.equal (Just "alice")
        , test "member starts active" <|
            \_ ->
                let
                    state =
                        GroupState.applyEvents createAliceEvents
                in
                Dict.get "alice" state.members
                    |> Maybe.map .isActive
                    |> Expect.equal (Just True)
        , test "member starts not retired" <|
            \_ ->
                let
                    state =
                        GroupState.applyEvents createAliceEvents
                in
                Dict.get "alice" state.members
                    |> Maybe.map .isRetired
                    |> Expect.equal (Just False)
        , test "member starts not replaced" <|
            \_ ->
                let
                    state =
                        GroupState.applyEvents createAliceEvents
                in
                Dict.get "alice" state.members
                    |> Maybe.map .isReplaced
                    |> Expect.equal (Just False)
        , test "preserves member type" <|
            \_ ->
                let
                    state =
                        GroupState.applyEvents createAliceEvents
                in
                Dict.get "alice" state.members
                    |> Maybe.map .memberType
                    |> Expect.equal (Just Member.Real)
        , test "ignores duplicate member creation" <|
            \_ ->
                let
                    events =
                        createAliceEvents
                            ++ [ makeEnvelope "e2"
                                    2000
                                    "admin"
                                    (MemberCreated { memberId = "alice", name = "Alice2", memberType = Member.Virtual, addedBy = "admin" })
                               ]

                    state =
                        GroupState.applyEvents events
                in
                Dict.get "alice" state.members
                    |> Maybe.map .name
                    |> Expect.equal (Just "Alice")
        , test "creates multiple members" <|
            \_ ->
                let
                    events =
                        createAliceEvents
                            ++ [ makeEnvelope "e2"
                                    2000
                                    "admin"
                                    (MemberCreated { memberId = "bob", name = "Bob", memberType = Member.Virtual, addedBy = "admin" })
                               ]

                    state =
                        GroupState.applyEvents events
                in
                Expect.equal 2 (Dict.size state.members)
        ]


memberRenameTests : Test
memberRenameTests =
    describe "Member rename"
        [ test "renames an existing member" <|
            \_ ->
                let
                    events =
                        createAliceEvents
                            ++ [ makeEnvelope "e2"
                                    2000
                                    "alice"
                                    (MemberRenamed { memberId = "alice", oldName = "Alice", newName = "Alicia" })
                               ]

                    state =
                        GroupState.applyEvents events
                in
                Dict.get "alice" state.members
                    |> Maybe.map .name
                    |> Expect.equal (Just "Alicia")
        , test "ignores rename for non-existent member" <|
            \_ ->
                let
                    events =
                        [ makeEnvelope "e1"
                            1000
                            "admin"
                            (MemberRenamed { memberId = "ghost", oldName = "Ghost", newName = "Phantom" })
                        ]

                    state =
                        GroupState.applyEvents events
                in
                Expect.equal 0 (Dict.size state.members)
        ]


retireAliceEvents : List Envelope
retireAliceEvents =
    createAliceEvents
        ++ [ makeEnvelope "e2"
                2000
                "admin"
                (MemberRetired { memberId = "alice" })
           ]


memberRetireTests : Test
memberRetireTests =
    describe "Member retire"
        [ test "retired member is marked retired" <|
            \_ ->
                let
                    state =
                        GroupState.applyEvents retireAliceEvents
                in
                Dict.get "alice" state.members
                    |> Maybe.map .isRetired
                    |> Expect.equal (Just True)
        , test "retired member is no longer active" <|
            \_ ->
                let
                    state =
                        GroupState.applyEvents retireAliceEvents
                in
                Dict.get "alice" state.members
                    |> Maybe.map .isActive
                    |> Expect.equal (Just False)
        , test "ignores retire for already retired member" <|
            \_ ->
                let
                    events =
                        retireAliceEvents
                            ++ [ makeEnvelope "e3"
                                    3000
                                    "admin"
                                    (MemberRetired { memberId = "alice" })
                               ]

                    state =
                        GroupState.applyEvents events
                in
                Dict.get "alice" state.members
                    |> Maybe.map .isRetired
                    |> Expect.equal (Just True)
        , test "ignores retire for non-existent member" <|
            \_ ->
                let
                    events =
                        [ makeEnvelope "e1"
                            1000
                            "admin"
                            (MemberRetired { memberId = "ghost" })
                        ]

                    state =
                        GroupState.applyEvents events
                in
                Expect.equal 0 (Dict.size state.members)
        ]


memberUnretireTests : Test
memberUnretireTests =
    let
        unretireAliceEvents =
            retireAliceEvents
                ++ [ makeEnvelope "e3"
                        3000
                        "admin"
                        (MemberUnretired { memberId = "alice" })
                   ]
    in
    describe "Member unretire"
        [ test "unretired member is no longer retired" <|
            \_ ->
                let
                    state =
                        GroupState.applyEvents unretireAliceEvents
                in
                Dict.get "alice" state.members
                    |> Maybe.map .isRetired
                    |> Expect.equal (Just False)
        , test "unretired member is active again" <|
            \_ ->
                let
                    state =
                        GroupState.applyEvents unretireAliceEvents
                in
                Dict.get "alice" state.members
                    |> Maybe.map .isActive
                    |> Expect.equal (Just True)
        , test "ignores unretire for active member" <|
            \_ ->
                let
                    events =
                        createAliceEvents
                            ++ [ makeEnvelope "e2"
                                    2000
                                    "admin"
                                    (MemberUnretired { memberId = "alice" })
                               ]

                    state =
                        GroupState.applyEvents events
                in
                Dict.get "alice" state.members
                    |> Maybe.map .isActive
                    |> Expect.equal (Just True)
        , test "ignores unretire for replaced member" <|
            \_ ->
                let
                    events =
                        createAliceEvents
                            ++ [ makeEnvelope "e2"
                                    1001
                                    "admin"
                                    (MemberCreated { memberId = "bob", name = "Bob", memberType = Member.Real, addedBy = "admin" })
                               , makeEnvelope "e3"
                                    2000
                                    "admin"
                                    (MemberReplaced { previousId = "alice", newId = "bob" })
                               , makeEnvelope "e4"
                                    3000
                                    "admin"
                                    (MemberUnretired { memberId = "alice" })
                               ]

                    state =
                        GroupState.applyEvents events
                in
                Dict.get "alice" state.members
                    |> Maybe.map .isReplaced
                    |> Expect.equal (Just True)
        ]


replaceAliceWithBobEvents : List Envelope
replaceAliceWithBobEvents =
    [ makeEnvelope "e1"
        1000
        "admin"
        (MemberCreated { memberId = "alice", name = "Alice", memberType = Member.Virtual, addedBy = "admin" })
    , makeEnvelope "e2"
        1001
        "admin"
        (MemberCreated { memberId = "bob", name = "Bob", memberType = Member.Real, addedBy = "admin" })
    , makeEnvelope "e3"
        2000
        "bob"
        (MemberReplaced { previousId = "alice", newId = "bob" })
    ]


memberReplacementTests : Test
memberReplacementTests =
    describe "Member replacement"
        [ test "replaced member is marked replaced" <|
            \_ ->
                let
                    state =
                        GroupState.applyEvents replaceAliceWithBobEvents
                in
                Dict.get "alice" state.members
                    |> Maybe.map .isReplaced
                    |> Expect.equal (Just True)
        , test "replaced member is no longer active" <|
            \_ ->
                let
                    state =
                        GroupState.applyEvents replaceAliceWithBobEvents
                in
                Dict.get "alice" state.members
                    |> Maybe.map .isActive
                    |> Expect.equal (Just False)
        , test "replacer inherits rootId from replaced member" <|
            \_ ->
                let
                    state =
                        GroupState.applyEvents replaceAliceWithBobEvents
                in
                Dict.get "bob" state.members
                    |> Maybe.map .rootId
                    |> Expect.equal (Just "alice")
        , test "replacer has previousId pointing to replaced member" <|
            \_ ->
                let
                    state =
                        GroupState.applyEvents replaceAliceWithBobEvents
                in
                Dict.get "bob" state.members
                    |> Maybe.map .previousId
                    |> Expect.equal (Just (Just "alice"))
        , test "replacement chain preserves rootId" <|
            \_ ->
                let
                    events =
                        replaceAliceWithBobEvents
                            ++ [ makeEnvelope "e4"
                                    2001
                                    "admin"
                                    (MemberCreated { memberId = "m3", name = "Third", memberType = Member.Real, addedBy = "admin" })
                               , makeEnvelope "e5"
                                    3000
                                    "m3"
                                    (MemberReplaced { previousId = "bob", newId = "m3" })
                               ]

                    state =
                        GroupState.applyEvents events
                in
                Dict.get "m3" state.members
                    |> Maybe.map .rootId
                    |> Expect.equal (Just "alice")
        , test "ignores self-replacement" <|
            \_ ->
                let
                    events =
                        createAliceEvents
                            ++ [ makeEnvelope "e2"
                                    2000
                                    "alice"
                                    (MemberReplaced { previousId = "alice", newId = "alice" })
                               ]

                    state =
                        GroupState.applyEvents events
                in
                Dict.get "alice" state.members
                    |> Maybe.map .isActive
                    |> Expect.equal (Just True)
        , test "ignores replacement of already replaced member" <|
            \_ ->
                let
                    events =
                        replaceAliceWithBobEvents
                            ++ [ makeEnvelope "e4"
                                    1002
                                    "admin"
                                    (MemberCreated { memberId = "carol", name = "Carol", memberType = Member.Real, addedBy = "admin" })
                               , makeEnvelope "e5"
                                    3000
                                    "carol"
                                    (MemberReplaced { previousId = "alice", newId = "carol" })
                               ]

                    state =
                        GroupState.applyEvents events
                in
                -- Carol's rootId should still be her own (replacement was ignored)
                Dict.get "carol" state.members
                    |> Maybe.map .rootId
                    |> Expect.equal (Just "carol")
        ]


groupMetadataTests : Test
groupMetadataTests =
    describe "Group metadata"
        [ test "updates group name" <|
            \_ ->
                let
                    events =
                        [ makeEnvelope "e1"
                            1000
                            "admin"
                            (GroupMetadataUpdated
                                { name = Just "Trip to Paris"
                                , subtitle = Nothing
                                , description = Nothing
                                , links = Nothing
                                }
                            )
                        ]

                    state =
                        GroupState.applyEvents events
                in
                Expect.equal "Trip to Paris" state.groupMeta.name
        , test "partial update preserves name" <|
            \_ ->
                let
                    state =
                        GroupState.applyEvents partialUpdateEvents
                in
                Expect.equal "Trip to Paris" state.groupMeta.name
        , test "partial update preserves subtitle" <|
            \_ ->
                let
                    state =
                        GroupState.applyEvents partialUpdateEvents
                in
                Expect.equal (Just "Summer 2025") state.groupMeta.subtitle
        ]


partialUpdateEvents : List Envelope
partialUpdateEvents =
    [ makeEnvelope "e1"
        1000
        "admin"
        (GroupMetadataUpdated
            { name = Just "Trip"
            , subtitle = Just (Just "Summer 2025")
            , description = Nothing
            , links = Nothing
            }
        )
    , makeEnvelope "e2"
        2000
        "admin"
        (GroupMetadataUpdated
            { name = Just "Trip to Paris"
            , subtitle = Nothing
            , description = Nothing
            , links = Nothing
            }
        )
    ]


eventOrderingTests : Test
eventOrderingTests =
    describe "Event ordering"
        [ test "events are applied in timestamp order" <|
            \_ ->
                let
                    -- Events provided in reverse order
                    events =
                        [ makeEnvelope "e2"
                            2000
                            "alice"
                            (MemberRenamed { memberId = "alice", oldName = "Alice", newName = "Alicia" })
                        , makeEnvelope "e1"
                            1000
                            "admin"
                            (MemberCreated { memberId = "alice", name = "Alice", memberType = Member.Real, addedBy = "admin" })
                        ]

                    state =
                        GroupState.applyEvents events
                in
                Dict.get "alice" state.members
                    |> Maybe.map .name
                    |> Expect.equal (Just "Alicia")
        , test "event id breaks timestamp ties" <|
            \_ ->
                let
                    events =
                        [ makeEnvelope "e1"
                            1000
                            "admin"
                            (MemberCreated { memberId = "alice", name = "Alice", memberType = Member.Real, addedBy = "admin" })
                        , makeEnvelope "e3"
                            2000
                            "alice"
                            (MemberRenamed { memberId = "alice", oldName = "Alice", newName = "Third" })
                        , makeEnvelope "e2"
                            2000
                            "alice"
                            (MemberRenamed { memberId = "alice", oldName = "Alice", newName = "Second" })
                        ]

                    state =
                        GroupState.applyEvents events
                in
                -- e2 sorts before e3 at same timestamp, so e3 is applied last
                Dict.get "alice" state.members
                    |> Maybe.map .name
                    |> Expect.equal (Just "Third")
        , fuzz (Fuzz.list (Fuzz.intRange 1 100)) "event ordering is deterministic regardless of input order" <|
            \randomInts ->
                let
                    baseEvents =
                        [ makeEnvelope "e0"
                            0
                            "admin"
                            (MemberCreated { memberId = "alice", name = "Alice", memberType = Member.Real, addedBy = "admin" })
                        ]

                    renameEvents =
                        List.indexedMap
                            (\i _ ->
                                makeEnvelope ("e" ++ String.fromInt (i + 1))
                                    ((i + 1) * 1000)
                                    "alice"
                                    (MemberRenamed { memberId = "alice", oldName = "", newName = "Name" ++ String.fromInt i })
                            )
                            randomInts

                    forwardState =
                        GroupState.applyEvents (baseEvents ++ renameEvents)

                    reverseState =
                        GroupState.applyEvents (baseEvents ++ List.reverse renameEvents)
                in
                Expect.equal
                    (Dict.get "alice" forwardState.members |> Maybe.map .name)
                    (Dict.get "alice" reverseState.members |> Maybe.map .name)
        ]
