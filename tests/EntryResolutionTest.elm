module EntryResolutionTest exposing (suite)

import Dict
import Domain.Entry as Entry exposing (Beneficiary(..), Kind(..))
import Domain.Event as Event exposing (Payload(..))
import Domain.GroupState as GroupState exposing (RejectionReason(..))
import Expect
import Test exposing (..)
import TestHelpers exposing (..)


suite : Test
suite =
    describe "Entry resolution"
        [ singleVersionTests
        , modificationTests
        , deletionTests
        , concurrentModificationTests
        , rejectionTests
        ]


singleVersionTests : Test
singleVersionTests =
    describe "Single version"
        [ describe "added entry becomes current version" <|
            let
                entry =
                    makeExpenseEntry "entry1" 1000 defaultExpenseData

                state =
                    GroupState.applyEvents
                        [ makeEnvelope "e1" 1000 "admin" (EntryAdded entry) ]
            in
            [ test "current version id matches" <|
                \_ ->
                    Dict.get "entry1" state.entries
                        |> Maybe.map (.currentVersion >> .meta >> .id)
                        |> Expect.equal (Just "entry1")
            , test "entry is not deleted" <|
                \_ ->
                    Dict.get "entry1" state.entries
                        |> Maybe.map .isDeleted
                        |> Expect.equal (Just False)
            , test "has exactly one version" <|
                \_ ->
                    Dict.get "entry1" state.entries
                        |> Maybe.map (.allVersions >> Dict.size)
                        |> Expect.equal (Just 1)
            ]
        ]


modificationTests : Test
modificationTests =
    let
        originalEntry =
            makeExpenseEntry "entry1" 1000 defaultExpenseData

        modifiedData =
            { defaultExpenseData | description = "Modified expense", amount = 2000 }

        modifiedEntry =
            Entry.replace originalEntry.meta "entry2" (Expense modifiedData)
    in
    describe "Modifications"
        [ test "current version updates to modified entry" <|
            \_ ->
                let
                    state =
                        GroupState.applyEvents
                            [ makeEnvelope "e1" 1000 "admin" (EntryAdded originalEntry)
                            , makeEnvelope "e2" 2000 "admin" (EntryModified modifiedEntry)
                            ]
                in
                Dict.get "entry1" state.entries
                    |> Maybe.map (.currentVersion >> .meta >> .id)
                    |> Expect.equal (Just "entry2")
        , test "all versions are tracked" <|
            \_ ->
                let
                    state =
                        GroupState.applyEvents
                            [ makeEnvelope "e1" 1000 "admin" (EntryAdded originalEntry)
                            , makeEnvelope "e2" 2000 "admin" (EntryModified modifiedEntry)
                            ]
                in
                Dict.get "entry1" state.entries
                    |> Maybe.map (.allVersions >> Dict.size)
                    |> Expect.equal (Just 2)
        , test "modification of non-existent entry is ignored" <|
            \_ ->
                let
                    orphanEntry =
                        makeExpenseEntry "entry2" 2000 defaultExpenseData
                            |> (\e ->
                                    let
                                        meta =
                                            e.meta
                                    in
                                    { e | meta = { meta | rootId = "entry1" } }
                               )

                    state =
                        GroupState.applyEvents
                            [ makeEnvelope "e1" 2000 "admin" (EntryModified orphanEntry) ]
                in
                Expect.equal 0 (Dict.size state.entries)
        ]


deletionTests : Test
deletionTests =
    describe "Deletion and undeletion"
        [ test "deleted entry is marked as deleted" <|
            \_ ->
                let
                    entry =
                        makeExpenseEntry "entry1" 1000 defaultExpenseData

                    state =
                        GroupState.applyEvents
                            [ makeEnvelope "e1" 1000 "admin" (EntryAdded entry)
                            , makeEnvelope "e2" 2000 "admin" (EntryDeleted { rootId = "entry1" })
                            ]
                in
                Dict.get "entry1" state.entries
                    |> Maybe.map .isDeleted
                    |> Expect.equal (Just True)
        , test "undeleted entry is restored" <|
            \_ ->
                let
                    entry =
                        makeExpenseEntry "entry1" 1000 defaultExpenseData

                    state =
                        GroupState.applyEvents
                            [ makeEnvelope "e1" 1000 "admin" (EntryAdded entry)
                            , makeEnvelope "e2" 2000 "admin" (EntryDeleted { rootId = "entry1" })
                            , makeEnvelope "e3" 3000 "admin" (EntryUndeleted { rootId = "entry1" })
                            ]
                in
                Dict.get "entry1" state.entries
                    |> Maybe.map .isDeleted
                    |> Expect.equal (Just False)
        , test "deleted entries excluded from active entries" <|
            \_ ->
                let
                    entry1 =
                        makeExpenseEntry "entry1" 1000 defaultExpenseData

                    entry2 =
                        makeExpenseEntry "entry2" 1001 defaultExpenseData

                    state =
                        GroupState.applyEvents
                            [ makeEnvelope "e1" 1000 "admin" (EntryAdded entry1)
                            , makeEnvelope "e2" 1001 "admin" (EntryAdded entry2)
                            , makeEnvelope "e3" 2000 "admin" (EntryDeleted { rootId = "entry1" })
                            ]
                in
                Expect.equal 1 (List.length (GroupState.activeEntries state))
        , test "delete non-existent entry is ignored" <|
            \_ ->
                let
                    state =
                        GroupState.applyEvents
                            [ makeEnvelope "e1" 1000 "admin" (EntryDeleted { rootId = "ghost" }) ]
                in
                Expect.equal 0 (Dict.size state.entries)
        ]


concurrentModificationTests : Test
concurrentModificationTests =
    describe "Concurrent modification resolution"
        [ test "deeper chain wins over shallower" <|
            \_ ->
                let
                    originalEntry =
                        makeExpenseEntry "entry1" 1000 defaultExpenseData

                    -- depth 1: entry1 -> v2
                    mod1 =
                        Entry.replace originalEntry.meta "v2" (Expense { defaultExpenseData | description = "Mod by Alice" })

                    -- depth 2: entry1 -> v2 -> v3
                    mod2 =
                        Entry.replace mod1.meta "v3" (Expense { defaultExpenseData | description = "Mod by Bob" })

                    state =
                        GroupState.applyEvents
                            [ makeEnvelope "e1" 1000 "admin" (EntryAdded originalEntry)
                            , makeEnvelope "e2" 2000 "alice" (EntryModified mod1)
                            , makeEnvelope "e3" 3000 "bob" (EntryModified mod2)
                            ]
                in
                Dict.get "entry1" state.entries
                    |> Maybe.map (.currentVersion >> .meta >> .id)
                    |> Expect.equal (Just "v3")
        , test "id breaks tie at same depth" <|
            \_ ->
                let
                    originalEntry =
                        makeExpenseEntry "entry1" 1000 defaultExpenseData

                    -- Both at depth 1 (concurrent edits of the same parent)
                    mod1 =
                        Entry.replace originalEntry.meta "v-aaa" (Expense { defaultExpenseData | description = "Mod A" })

                    mod2 =
                        Entry.replace originalEntry.meta "v-zzz" (Expense { defaultExpenseData | description = "Mod Z" })

                    state =
                        GroupState.applyEvents
                            [ makeEnvelope "e1" 1000 "admin" (EntryAdded originalEntry)
                            , makeEnvelope "e2" 2000 "alice" (EntryModified mod1)
                            , makeEnvelope "e3" 2000 "bob" (EntryModified mod2)
                            ]
                in
                -- "v-zzz" > "v-aaa" lexicographically, so v-zzz wins
                Dict.get "entry1" state.entries
                    |> Maybe.map (.currentVersion >> .meta >> .id)
                    |> Expect.equal (Just "v-zzz")
        ]


rejectionTests : Test
rejectionTests =
    describe "Rejection tracking"
        [ test "duplicate entry id is rejected with reason" <|
            \_ ->
                let
                    entry =
                        makeExpenseEntry "entry1" 1000 defaultExpenseData

                    state =
                        GroupState.applyEvents
                            [ makeEnvelope "e1" 1000 "admin" (EntryAdded entry)
                            , makeEnvelope "e2" 2000 "admin" (EntryAdded entry)
                            ]
                in
                state.rejectedEntries
                    |> List.map Tuple.second
                    |> Expect.equal [ DuplicateEntryId ]
        , test "new entry with previousVersionId is rejected" <|
            \_ ->
                let
                    entry =
                        makeExpenseEntry "entry1" 1000 defaultExpenseData
                            |> (\e ->
                                    let
                                        meta =
                                            e.meta
                                    in
                                    { e | meta = { meta | previousVersionId = Just "other" } }
                               )

                    state =
                        GroupState.applyEvents
                            [ makeEnvelope "e1" 1000 "admin" (EntryAdded entry) ]
                in
                state.rejectedEntries
                    |> List.map Tuple.second
                    |> Expect.equal [ NewEntryHasPreviousVersion ]
        , test "modification of non-existent root is rejected" <|
            \_ ->
                let
                    orphanEntry =
                        makeExpenseEntry "entry2" 2000 defaultExpenseData
                            |> (\e ->
                                    let
                                        meta =
                                            e.meta
                                    in
                                    { e | meta = { meta | rootId = "entry1" } }
                               )

                    state =
                        GroupState.applyEvents
                            [ makeEnvelope "e1" 2000 "admin" (EntryModified orphanEntry) ]
                in
                state.rejectedEntries
                    |> List.map Tuple.second
                    |> Expect.equal [ RootEntryNotFound ]
        , test "valid entries produce no rejections" <|
            \_ ->
                let
                    entry =
                        makeExpenseEntry "entry1" 1000 defaultExpenseData

                    modified =
                        Entry.replace entry.meta "entry2" (Expense { defaultExpenseData | description = "Modified" })

                    state =
                        GroupState.applyEvents
                            [ makeEnvelope "e1" 1000 "admin" (EntryAdded entry)
                            , makeEnvelope "e2" 2000 "admin" (EntryModified modified)
                            ]
                in
                Expect.equal [] state.rejectedEntries
        , test "multiple rejections are accumulated" <|
            \_ ->
                let
                    entry =
                        makeExpenseEntry "entry1" 1000 defaultExpenseData

                    orphan1 =
                        makeExpenseEntry "orphan1" 2000 defaultExpenseData
                            |> (\e ->
                                    let
                                        meta =
                                            e.meta
                                    in
                                    { e | meta = { meta | rootId = "ghost1" } }
                               )

                    orphan2 =
                        makeExpenseEntry "orphan2" 3000 defaultExpenseData
                            |> (\e ->
                                    let
                                        meta =
                                            e.meta
                                    in
                                    { e | meta = { meta | rootId = "ghost2" } }
                               )

                    state =
                        GroupState.applyEvents
                            [ makeEnvelope "e1" 1000 "admin" (EntryAdded entry)
                            , makeEnvelope "e2" 2000 "admin" (EntryModified orphan1)
                            , makeEnvelope "e3" 3000 "admin" (EntryModified orphan2)
                            ]
                in
                Expect.equal 2 (List.length state.rejectedEntries)
        ]
