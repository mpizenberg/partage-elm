module MigrationCurationTest exposing (suite)

import Dict
import Domain.Currency exposing (Currency(..))
import Domain.Entry as Entry exposing (Kind(..))
import Domain.Event exposing (Payload(..))
import Domain.GroupState as GroupState
import Domain.Member as Member
import Domain.MigrationCuration as MigrationCuration exposing (Bound(..))
import Expect
import Test exposing (Test, describe, test)
import TestHelpers exposing (defaultExpenseData, makeEnvelope, makeExpenseEntry)


{-| A legitimate group: genesis, three real members, one entry by Alice.
-}
legitEvents : List Domain.Event.Envelope
legitEvents =
    [ makeEnvelope "g" 0 "admin" (GroupCreated { name = "Trip", defaultCurrency = EUR })
    , makeEnvelope "m-admin" 1 "admin" (MemberCreated { memberId = "admin", name = "Admin", memberType = Member.Real, addedBy = "admin" })
    , makeEnvelope "m-alice" 2 "admin" (MemberCreated { memberId = "alice", name = "Alice", memberType = Member.Real, addedBy = "admin" })
    , makeEnvelope "m-bob" 3 "admin" (MemberCreated { memberId = "bob", name = "Bob", memberType = Member.Real, addedBy = "admin" })
    , makeEnvelope "e-add1" 1000 "alice" (EntryAdded (makeExpenseEntry "entry1" 1000 defaultExpenseData))
    ]


{-| Mallory holds the group key: she self-creates a member (self-links need no
root consent), adds her own entry, and hijacks Alice's entry1 with a later
modification — all validly signed, so all replay-valid.
-}
attackerEvents : List Domain.Event.Envelope
attackerEvents =
    let
        hijack : Entry.Entry
        hijack =
            Entry.replace (makeExpenseEntry "entry1" 1000 defaultExpenseData).meta
                "v-mallory"
                (Expense { defaultExpenseData | description = "Hijacked" })
    in
    [ makeEnvelope "m-mallory" 4000 "mallory" (MemberCreated { memberId = "mallory", name = "Mallory", memberType = Member.Real, addedBy = "mallory" })
    , makeEnvelope "e-add2" 4100 "mallory" (EntryAdded (makeExpenseEntry "entry2" 4100 defaultExpenseData))
    , makeEnvelope "e-mod" 4200 "mallory" (EntryModified hijack)
    ]


{-| Eve is a real member whose key later leaked: her first entry (batch seq 3) is
genuine, then a flood rode in on the stolen key in a later batch (seq 9). The
order map pairs each event id with its ingestion batch.
-}
leakedKeyEvents : List Domain.Event.Envelope
leakedKeyEvents =
    [ makeEnvelope "g" 0 "admin" (GroupCreated { name = "Trip", defaultCurrency = EUR })
    , makeEnvelope "m-admin" 1 "admin" (MemberCreated { memberId = "admin", name = "Admin", memberType = Member.Real, addedBy = "admin" })
    , makeEnvelope "m-eve" 2 "admin" (MemberCreated { memberId = "eve", name = "Eve", memberType = Member.Real, addedBy = "admin" })
    , makeEnvelope "e-eve1" 100 "eve" (EntryAdded (makeExpenseEntry "eve1" 100 defaultExpenseData))
    , makeEnvelope "e-eve2" 200 "eve" (EntryAdded (makeExpenseEntry "eve2" 200 defaultExpenseData))
    , makeEnvelope "e-eve3" 210 "eve" (EntryAdded (makeExpenseEntry "eve3" 210 defaultExpenseData))
    ]


leakedKeyOrder : Dict.Dict String Int
leakedKeyOrder =
    Dict.fromList
        [ ( "g", 1 )
        , ( "m-admin", 1 )
        , ( "m-eve", 1 )
        , ( "e-eve1", 3 )
        , ( "e-eve2", 9 )
        , ( "e-eve3", 9 )
        ]


suite : Test
suite =
    describe "MigrationCuration"
        [ curateEventsSuite
        , boundedSuite
        , identitiesSuite
        , previewSuite
        ]


curateEventsSuite : Test
curateEventsSuite =
    describe "curateEvents (whole identity)"
        [ test "empty selection keeps every event" <|
            \_ ->
                MigrationCuration.curateEvents Dict.empty Dict.empty (legitEvents ++ attackerEvents)
                    |> Expect.equal (legitEvents ++ attackerEvents)
        , test "excluding an absent author is a no-op" <|
            \_ ->
                MigrationCuration.curateEvents Dict.empty (Dict.singleton "ghost" All) legitEvents
                    |> Expect.equal legitEvents
        , test "excluding an author drops exactly their events" <|
            \_ ->
                MigrationCuration.curateEvents Dict.empty (Dict.singleton "mallory" All) (legitEvents ++ attackerEvents)
                    |> Expect.equal legitEvents
        , test "the attack lands before curation" <|
            \_ ->
                let
                    state : GroupState.GroupState
                    state =
                        GroupState.applyEvents (legitEvents ++ attackerEvents) GroupState.empty
                in
                Expect.all
                    [ \s -> Dict.member "mallory" s.members |> Expect.equal True
                    , \s -> Dict.member "entry2" s.entries |> Expect.equal True
                    , \s -> Dict.get "entry1" s.entries |> Maybe.map (.currentVersion >> .meta >> .id) |> Expect.equal (Just "v-mallory")
                    ]
                    state
        , test "curation reverts the attack: member gone, entry gone, hijack undone" <|
            \_ ->
                let
                    curated : GroupState.GroupState
                    curated =
                        MigrationCuration.curateEvents Dict.empty (Dict.singleton "mallory" All) (legitEvents ++ attackerEvents)
                            |> (\events -> GroupState.applyEvents events GroupState.empty)
                in
                Expect.all
                    [ \s -> Dict.member "mallory" s.members |> Expect.equal False
                    , \s -> Dict.member "entry2" s.entries |> Expect.equal False
                    , \s -> Dict.get "entry1" s.entries |> Maybe.map (.currentVersion >> .meta >> .id) |> Expect.equal (Just "entry1")
                    ]
                    curated
        , test "curated replay equals the attack-free baseline" <|
            \_ ->
                let
                    curated : GroupState.GroupState
                    curated =
                        MigrationCuration.curateEvents Dict.empty (Dict.singleton "mallory" All) (legitEvents ++ attackerEvents)
                            |> (\events -> GroupState.applyEvents events GroupState.empty)
                in
                Expect.equal (GroupState.applyEvents legitEvents GroupState.empty) curated
        ]


boundedSuite : Test
boundedSuite =
    describe "curateEvents (time-bounded)"
        [ test "After keeps events up to the boundary seq and drops later ones" <|
            \_ ->
                MigrationCuration.curateEvents leakedKeyOrder (Dict.singleton "eve" (After 3)) leakedKeyEvents
                    |> List.map .id
                    |> Expect.equal [ "g", "m-admin", "m-eve", "e-eve1" ]
        , test "the boundary reverts the flood but keeps the genuine early entry" <|
            \_ ->
                let
                    curated : GroupState.GroupState
                    curated =
                        MigrationCuration.curateEvents leakedKeyOrder (Dict.singleton "eve" (After 3)) leakedKeyEvents
                            |> (\events -> GroupState.applyEvents events GroupState.empty)
                in
                Expect.all
                    [ \s -> Dict.member "eve1" s.entries |> Expect.equal True
                    , \s -> Dict.member "eve2" s.entries |> Expect.equal False
                    , \s -> Dict.member "eve3" s.entries |> Expect.equal False
                    ]
                    curated
        , test "an event with no known seq is kept even under a boundary" <|
            \_ ->
                let
                    -- e-eve2 absent from the order map: it cannot be placed, so it survives.
                    partialOrder : Dict.Dict String Int
                    partialOrder =
                        Dict.remove "e-eve2" leakedKeyOrder
                in
                MigrationCuration.curateEvents partialOrder (Dict.singleton "eve" (After 3)) leakedKeyEvents
                    |> List.map .id
                    |> Expect.equal [ "g", "m-admin", "m-eve", "e-eve1", "e-eve2" ]
        ]


findIdentity : String -> List MigrationCuration.Identity -> Maybe MigrationCuration.Identity
findIdentity id =
    List.filter (\identity -> identity.id == id) >> List.head


identitiesSuite : Test
identitiesSuite =
    let
        allEvents : List Domain.Event.Envelope
        allEvents =
            legitEvents ++ attackerEvents

        state : GroupState.GroupState
        state =
            GroupState.applyEvents allEvents GroupState.empty

        -- admin is the group creator and the migrator here.
        ids : List MigrationCuration.Identity
        ids =
            MigrationCuration.identities Dict.empty "admin" state allEvents
    in
    describe "identities"
        [ test "one entry per author, heaviest first" <|
            \_ ->
                List.map (\i -> ( i.id, i.eventCount )) ids
                    |> Expect.equal [ ( "admin", 4 ), ( "mallory", 3 ), ( "alice", 1 ) ]
        , test "the migrator/creator is not excludable" <|
            \_ ->
                findIdentity "admin" ids |> Maybe.map .excludable |> Expect.equal (Just False)
        , test "an injected member is excludable" <|
            \_ ->
                findIdentity "mallory" ids |> Maybe.map .excludable |> Expect.equal (Just True)
        , test "without a fetched order there are no boundaries" <|
            \_ ->
                findIdentity "mallory" ids |> Maybe.map .boundaries |> Expect.equal (Just [])
        , test "a linked device is flagged and resolves to its root for exclusion" <|
            \_ ->
                let
                    withDevice : List Domain.Event.Envelope
                    withDevice =
                        legitEvents
                            ++ [ makeEnvelope "link" 500 "admin-phone" (MemberLinked { rootId = "admin", deviceId = "admin-phone", seq = 1 })
                               , makeEnvelope "ap-1" 1500 "admin-phone" (EntryAdded (makeExpenseEntry "entry3" 1500 defaultExpenseData))
                               ]

                    deviceId : Maybe MigrationCuration.Identity
                    deviceId =
                        MigrationCuration.identities Dict.empty "admin" (GroupState.applyEvents withDevice GroupState.empty) withDevice
                            |> findIdentity "admin-phone"
                in
                Expect.equal ( Just True, Just False )
                    ( Maybe.map .isDevice deviceId, Maybe.map .excludable deviceId )
        , test "a fetched order yields the identity's split points, excluding the last batch" <|
            \_ ->
                MigrationCuration.identities leakedKeyOrder "admin" (GroupState.applyEvents leakedKeyEvents GroupState.empty) leakedKeyEvents
                    |> findIdentity "eve"
                    |> Maybe.map .boundaries
                    |> Expect.equal (Just [ { seq = 3, kept = 1 } ])
        ]


previewSuite : Test
previewSuite =
    describe "preview"
        [ test "counts what survives and what is dropped" <|
            \_ ->
                let
                    result : MigrationCuration.Preview
                    result =
                        MigrationCuration.preview Dict.empty "alice" (Dict.singleton "mallory" All) (legitEvents ++ attackerEvents)
                in
                Expect.all
                    [ \r -> r.carried |> Expect.equal (List.length legitEvents)
                    , \r -> r.dropped |> Expect.equal (List.length attackerEvents)
                    , \r -> r.members |> Expect.equal 3
                    , \r -> r.entries |> Expect.equal 1
                    ]
                    result
        , test "the migrator's balance matches the attack-free baseline" <|
            \_ ->
                let
                    selfBalance : MigrationCuration.Preview -> Maybe Int
                    selfBalance p =
                        p.balances |> List.filter .isSelf |> List.head |> Maybe.map .balanceCents

                    baseline : MigrationCuration.Preview
                    baseline =
                        MigrationCuration.preview Dict.empty "alice" Dict.empty legitEvents

                    curated : MigrationCuration.Preview
                    curated =
                        MigrationCuration.preview Dict.empty "alice" (Dict.singleton "mallory" All) (legitEvents ++ attackerEvents)
                in
                Expect.equal (selfBalance baseline) (selfBalance curated)
        , test "a time boundary drops only the flood in the preview" <|
            \_ ->
                let
                    result : MigrationCuration.Preview
                    result =
                        MigrationCuration.preview leakedKeyOrder "admin" (Dict.singleton "eve" (After 3)) leakedKeyEvents
                in
                Expect.all
                    [ \r -> r.carried |> Expect.equal 4
                    , \r -> r.dropped |> Expect.equal 2
                    , \r -> r.members |> Expect.equal 2
                    , \r -> r.entries |> Expect.equal 1
                    ]
                    result
        ]
