module MigrationCurationTest exposing (suite)

import Dict
import Domain.Currency exposing (Currency(..))
import Domain.Entry as Entry exposing (Kind(..))
import Domain.Event exposing (Payload(..))
import Domain.GroupState as GroupState
import Domain.Member as Member
import Domain.MigrationCuration as MigrationCuration
import Expect
import Set
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


suite : Test
suite =
    describe "MigrationCuration.curateEvents"
        [ test "empty exclusion keeps every event" <|
            \_ ->
                MigrationCuration.curateEvents Set.empty (legitEvents ++ attackerEvents)
                    |> Expect.equal (legitEvents ++ attackerEvents)
        , test "excluding an absent author is a no-op" <|
            \_ ->
                MigrationCuration.curateEvents (Set.singleton "ghost") legitEvents
                    |> Expect.equal legitEvents
        , test "excluding an author drops exactly their events" <|
            \_ ->
                MigrationCuration.curateEvents (Set.singleton "mallory") (legitEvents ++ attackerEvents)
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
                        MigrationCuration.curateEvents (Set.singleton "mallory") (legitEvents ++ attackerEvents)
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
                        MigrationCuration.curateEvents (Set.singleton "mallory") (legitEvents ++ attackerEvents)
                            |> (\events -> GroupState.applyEvents events GroupState.empty)
                in
                Expect.equal (GroupState.applyEvents legitEvents GroupState.empty) curated
        ]
