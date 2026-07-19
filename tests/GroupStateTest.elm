module GroupStateTest exposing (suite)

import Dict
import Domain.Currency exposing (Currency(..))
import Domain.Event exposing (Envelope, Payload(..))
import Domain.GroupState as GroupState
import Domain.Member as Member
import Expect
import Fuzz
import Test exposing (Test, describe, fuzz, test)
import TestHelpers exposing (makeEnvelope)


suite : Test
suite =
    describe "GroupState"
        [ memberCreationTests
        , memberRenameTests
        , memberRetireTests
        , memberUnretireTests
        , memberLinkTests
        , groupMetadataTests
        , eventOrderingTests
        ]


{-| Bootstrap event: admin self-registers as a member so subsequent events by admin pass authorization.
-}
adminBootstrap : Envelope
adminBootstrap =
    makeEnvelope "e0" 0 "admin" (MemberCreated { memberId = "admin", name = "Admin", memberType = Member.Real, addedBy = "admin" })


createAliceEvents : List Envelope
createAliceEvents =
    [ adminBootstrap
    , makeEnvelope "e1"
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
                        GroupState.applyEvents createAliceEvents GroupState.empty
                in
                Dict.get "alice" state.members
                    |> Maybe.map .name
                    |> Expect.equal (Just "Alice")
        , test "sets rootId to member's own id" <|
            \_ ->
                let
                    state =
                        GroupState.applyEvents createAliceEvents GroupState.empty
                in
                Dict.get "alice" state.members
                    |> Maybe.map .rootId
                    |> Expect.equal (Just "alice")
        , test "member starts not retired" <|
            \_ ->
                let
                    state =
                        GroupState.applyEvents createAliceEvents GroupState.empty
                in
                Dict.get "alice" state.members
                    |> Maybe.map .isRetired
                    |> Expect.equal (Just False)
        , test "preserves member type" <|
            \_ ->
                let
                    state =
                        GroupState.applyEvents createAliceEvents GroupState.empty
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
                        GroupState.applyEvents events GroupState.empty
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
                        GroupState.applyEvents events GroupState.empty
                in
                -- admin + alice + bob = 3
                Expect.equal 3 (Dict.size state.members)
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
                                    (MemberRenamed { rootId = "alice", oldName = "Alice", newName = "Alicia" })
                               ]

                    state =
                        GroupState.applyEvents events GroupState.empty
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
                            (MemberRenamed { rootId = "ghost", oldName = "Ghost", newName = "Phantom" })
                        ]

                    state =
                        GroupState.applyEvents events GroupState.empty
                in
                Expect.equal 0 (Dict.size state.members)
        ]


retireAliceEvents : List Envelope
retireAliceEvents =
    createAliceEvents
        ++ [ makeEnvelope "e2"
                2000
                "admin"
                (MemberRetired { rootId = "alice" })
           ]


memberRetireTests : Test
memberRetireTests =
    describe "Member retire"
        [ test "retired member is marked retired" <|
            \_ ->
                let
                    state =
                        GroupState.applyEvents retireAliceEvents GroupState.empty
                in
                Dict.get "alice" state.members
                    |> Maybe.map .isRetired
                    |> Expect.equal (Just True)
        , test "retired member is excluded from activeMembers" <|
            \_ ->
                let
                    state =
                        GroupState.applyEvents retireAliceEvents GroupState.empty
                in
                -- admin is still active, alice is retired
                GroupState.activeMembers state
                    |> List.length
                    |> Expect.equal 1
        , test "ignores retire for already retired member" <|
            \_ ->
                let
                    events =
                        retireAliceEvents
                            ++ [ makeEnvelope "e3"
                                    3000
                                    "admin"
                                    (MemberRetired { rootId = "alice" })
                               ]

                    state =
                        GroupState.applyEvents events GroupState.empty
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
                            (MemberRetired { rootId = "ghost" })
                        ]

                    state =
                        GroupState.applyEvents events GroupState.empty
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
                        (MemberUnretired { rootId = "alice" })
                   ]
    in
    describe "Member unretire"
        [ test "unretired member is no longer retired" <|
            \_ ->
                let
                    state =
                        GroupState.applyEvents unretireAliceEvents GroupState.empty
                in
                Dict.get "alice" state.members
                    |> Maybe.map .isRetired
                    |> Expect.equal (Just False)
        , test "unretired member appears in activeMembers" <|
            \_ ->
                let
                    state =
                        GroupState.applyEvents unretireAliceEvents GroupState.empty
                in
                -- admin + alice both active
                GroupState.activeMembers state
                    |> List.length
                    |> Expect.equal 2
        , test "ignores unretire for non-retired member" <|
            \_ ->
                let
                    events =
                        createAliceEvents
                            ++ [ makeEnvelope "e2"
                                    2000
                                    "admin"
                                    (MemberUnretired { rootId = "alice" })
                               ]

                    state =
                        GroupState.applyEvents events GroupState.empty
                in
                Dict.get "alice" state.members
                    |> Maybe.map .isRetired
                    |> Expect.equal (Just False)
        ]


createVirtualMember : String -> String -> Int -> Envelope
createVirtualMember eventId name timestamp =
    makeEnvelope eventId
        timestamp
        "admin"
        (MemberCreated { memberId = String.toLower name, name = name, memberType = Member.Virtual, addedBy = "admin" })


linkAliceEvents : List Envelope
linkAliceEvents =
    [ adminBootstrap
    , createVirtualMember "e1" "Alice" 1000
    , makeEnvelope "e2"
        2000
        "bob-device"
        (MemberLinked { rootId = "alice", deviceId = "bob-device", seq = 0 })
    ]


memberLinkTests : Test
memberLinkTests =
    describe "Member device links"
        [ test "device resolves to the linked root" <|
            \_ ->
                let
                    state =
                        GroupState.applyEvents linkAliceEvents GroupState.empty
                in
                GroupState.resolveMemberRootId state "bob-device"
                    |> Expect.equal (Just "alice")
        , test "claiming makes a virtual member real" <|
            \_ ->
                let
                    state =
                        GroupState.applyEvents linkAliceEvents GroupState.empty
                in
                Dict.get "alice" state.members
                    |> Maybe.map .memberType
                    |> Expect.equal (Just Member.Real)
        , test "name is preserved after claiming" <|
            \_ ->
                let
                    state =
                        GroupState.applyEvents linkAliceEvents GroupState.empty
                in
                GroupState.resolveMemberName state "bob-device"
                    |> Expect.equal "Alice"
        , test "re-linking moves the device to the new root" <|
            \_ ->
                let
                    state =
                        GroupState.applyEvents relinkToCarolEvents GroupState.empty
                in
                GroupState.resolveMemberRootId state "bob-device"
                    |> Expect.equal (Just "carol")
        , test "re-linking vacates the previously claimed member" <|
            \_ ->
                let
                    state =
                        GroupState.applyEvents relinkToCarolEvents GroupState.empty
                in
                Dict.get "alice" state.members
                    |> Maybe.map .memberType
                    |> Expect.equal (Just Member.Virtual)
        , test "higher seq wins over a later timestamp" <|
            \_ ->
                let
                    -- The device's clock jumped backwards between re-links:
                    -- the seq-1 link to alice is older in wall-clock time.
                    events =
                        [ adminBootstrap
                        , createVirtualMember "e1" "Alice" 1000
                        , createVirtualMember "e2" "Carol" 1001
                        , makeEnvelope "e3"
                            5000
                            "bob-device"
                            (MemberLinked { rootId = "alice", deviceId = "bob-device", seq = 1 })
                        , makeEnvelope "e4"
                            6000
                            "bob-device"
                            (MemberLinked { rootId = "carol", deviceId = "bob-device", seq = 0 })
                        ]

                    state =
                        GroupState.applyEvents events GroupState.empty
                in
                GroupState.resolveMemberRootId state "bob-device"
                    |> Expect.equal (Just "alice")
        , test "ignores link to non-existent root" <|
            \_ ->
                let
                    events =
                        [ adminBootstrap
                        , makeEnvelope "e1"
                            1000
                            "bob-device"
                            (MemberLinked { rootId = "ghost", deviceId = "bob-device", seq = 0 })
                        ]

                    state =
                        GroupState.applyEvents events GroupState.empty
                in
                GroupState.resolveMemberRootId state "bob-device"
                    |> Expect.equal Nothing
        , test "ignores link not emitted by the device itself" <|
            \_ ->
                let
                    events =
                        [ adminBootstrap
                        , createVirtualMember "e1" "Alice" 1000
                        , makeEnvelope "e2"
                            2000
                            "admin"
                            (MemberLinked { rootId = "alice", deviceId = "bob-device", seq = 0 })
                        ]

                    state =
                        GroupState.applyEvents events GroupState.empty
                in
                GroupState.resolveMemberRootId state "bob-device"
                    |> Expect.equal Nothing
        , test "link takes precedence over the device's own root" <|
            \_ ->
                let
                    -- bob-device joined as a new member, then re-linked to alice
                    events =
                        [ adminBootstrap
                        , createVirtualMember "e1" "Alice" 1000
                        , makeEnvelope "e2"
                            2000
                            "bob-device"
                            (MemberCreated { memberId = "bob-device", name = "Bob", memberType = Member.Real, addedBy = "bob-device" })
                        , makeEnvelope "e3"
                            3000
                            "bob-device"
                            (MemberLinked { rootId = "alice", deviceId = "bob-device", seq = 0 })
                        ]

                    state =
                        GroupState.applyEvents events GroupState.empty
                in
                ( GroupState.resolveMemberRootId state "bob-device"
                , Dict.member "bob-device" state.members
                )
                    |> Expect.equal ( Just "alice", True )
        , test "nextLinkSeq starts at 0 for an unlinked device" <|
            \_ ->
                GroupState.nextLinkSeq GroupState.empty "bob-device"
                    |> Expect.equal 0
        , test "nextLinkSeq increments past the winning link" <|
            \_ ->
                let
                    state =
                        GroupState.applyEvents linkAliceEvents GroupState.empty
                in
                GroupState.nextLinkSeq state "bob-device"
                    |> Expect.equal 1
        ]


relinkToCarolEvents : List Envelope
relinkToCarolEvents =
    linkAliceEvents
        ++ [ createVirtualMember "e1b" "Carol" 1001
           , makeEnvelope "e3"
                3000
                "bob-device"
                (MemberLinked { rootId = "carol", deviceId = "bob-device", seq = 1 })
           ]


groupMetadataTests : Test
groupMetadataTests =
    describe "Group metadata"
        [ test "updates group name" <|
            \_ ->
                let
                    events =
                        [ adminBootstrap
                        , makeEnvelope "e1"
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
                        GroupState.applyEvents events GroupState.empty
                in
                Expect.equal "Trip to Paris" state.groupMeta.name
        , test "partial update preserves name" <|
            \_ ->
                let
                    state =
                        GroupState.applyEvents partialUpdateEvents GroupState.empty
                in
                Expect.equal "Trip to Paris" state.groupMeta.name
        , test "partial update preserves subtitle" <|
            \_ ->
                let
                    state =
                        GroupState.applyEvents partialUpdateEvents GroupState.empty
                in
                Expect.equal (Just "Summer 2025") state.groupMeta.subtitle
        , test "a second GroupCreated is ignored" <|
            \_ ->
                let
                    genesis =
                        makeEnvelope "e-genesis" 500 "admin" (GroupCreated { name = "Trip", defaultCurrency = EUR })

                    duplicate =
                        makeEnvelope "e-dup" 1000 "admin" (GroupCreated { name = "Hijacked", defaultCurrency = USD })

                    state =
                        GroupState.applyEvents [ genesis, adminBootstrap, duplicate ] GroupState.empty
                in
                state.groupMeta
                    |> Expect.all
                        [ .name >> Expect.equal "Trip"
                        , .defaultCurrency >> Expect.equal EUR
                        ]
        ]


partialUpdateEvents : List Envelope
partialUpdateEvents =
    [ adminBootstrap
    , makeEnvelope "e1"
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
                            (MemberRenamed { rootId = "alice", oldName = "Alice", newName = "Alicia" })
                        , adminBootstrap
                        , makeEnvelope "e1"
                            1000
                            "admin"
                            (MemberCreated { memberId = "alice", name = "Alice", memberType = Member.Real, addedBy = "admin" })
                        ]

                    state =
                        GroupState.applyEvents events GroupState.empty
                in
                Dict.get "alice" state.members
                    |> Maybe.map .name
                    |> Expect.equal (Just "Alicia")
        , test "event id breaks timestamp ties" <|
            \_ ->
                let
                    events =
                        [ adminBootstrap
                        , makeEnvelope "e1"
                            1000
                            "admin"
                            (MemberCreated { memberId = "alice", name = "Alice", memberType = Member.Real, addedBy = "admin" })
                        , makeEnvelope "e3"
                            2000
                            "alice"
                            (MemberRenamed { rootId = "alice", oldName = "Alice", newName = "Third" })
                        , makeEnvelope "e2"
                            2000
                            "alice"
                            (MemberRenamed { rootId = "alice", oldName = "Alice", newName = "Second" })
                        ]

                    state =
                        GroupState.applyEvents events GroupState.empty
                in
                -- e2 sorts before e3 at same timestamp, so e3 is applied last
                Dict.get "alice" state.members
                    |> Maybe.map .name
                    |> Expect.equal (Just "Third")
        , fuzz (Fuzz.list (Fuzz.intRange 1 100)) "event ordering is deterministic regardless of input order" <|
            \randomInts ->
                let
                    baseEvents =
                        [ adminBootstrap
                        , makeEnvelope "e0b"
                            1
                            "admin"
                            (MemberCreated { memberId = "alice", name = "Alice", memberType = Member.Real, addedBy = "admin" })
                        ]

                    renameEvents =
                        List.indexedMap
                            (\i _ ->
                                makeEnvelope ("e" ++ String.fromInt (i + 1))
                                    ((i + 1) * 1000)
                                    "alice"
                                    (MemberRenamed { rootId = "alice", oldName = "", newName = "Name" ++ String.fromInt i })
                            )
                            randomInts

                    forwardState =
                        GroupState.applyEvents (baseEvents ++ renameEvents) GroupState.empty

                    reverseState =
                        GroupState.applyEvents (baseEvents ++ List.reverse renameEvents) GroupState.empty
                in
                Expect.equal
                    (Dict.get "alice" forwardState.members |> Maybe.map .name)
                    (Dict.get "alice" reverseState.members |> Maybe.map .name)
        ]
