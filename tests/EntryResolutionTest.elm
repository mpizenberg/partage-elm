module EntryResolutionTest exposing (..)

import Dict
import Domain.Entry as Entry exposing (Beneficiary(..), Kind(..))
import Domain.Event as Event exposing (Payload(..))
import Domain.GroupState as GroupState
import Expect
import Test exposing (..)
import TestHelpers exposing (..)
import Time


suite : Test
suite =
    describe "Entry resolution"
        [ singleVersionTests
        , modificationTests
        , deletionTests
        , concurrentModificationTests
        ]


singleVersionTests : Test
singleVersionTests =
    describe "Single version"
        [ test "added entry becomes current version" <|
            \_ ->
                let
                    entry =
                        makeExpenseEntry "entry1" "entry1" 1000 defaultExpenseData

                    events =
                        [ makeEnvelope "e1"
                            1000
                            "admin"
                            (EntryAdded entry)
                        ]

                    state =
                        GroupState.applyEvents events
                in
                case Dict.get "entry1" state.entries of
                    Just entryState ->
                        Expect.all
                            [ \es -> Expect.equal "entry1" es.currentVersion.meta.id
                            , \es -> Expect.equal False es.isDeleted
                            , \es -> Expect.equal 1 (Dict.size es.allVersions)
                            ]
                            entryState

                    Nothing ->
                        Expect.fail "Entry should exist"
        ]


modificationTests : Test
modificationTests =
    describe "Modifications"
        [ test "modified entry updates current version" <|
            \_ ->
                let
                    originalEntry =
                        makeExpenseEntry "entry1" "entry1" 1000 defaultExpenseData

                    modifiedData =
                        { defaultExpenseData | description = "Modified expense", amount = 2000 }

                    modifiedEntry =
                        { meta =
                            { id = "entry2"
                            , rootId = "entry1"
                            , previousVersionId = Just "entry1"
                            , notes = Nothing
                            , isDeleted = False
                            , createdBy = "admin"
                            , createdAt = Time.millisToPosix 2000
                            }
                        , kind = Expense modifiedData
                        }

                    events =
                        [ makeEnvelope "e1" 1000 "admin" (EntryAdded originalEntry)
                        , makeEnvelope "e2" 2000 "admin" (EntryModified modifiedEntry)
                        ]

                    state =
                        GroupState.applyEvents events
                in
                case Dict.get "entry1" state.entries of
                    Just entryState ->
                        Expect.all
                            [ \es -> Expect.equal "entry2" es.currentVersion.meta.id
                            , \es -> Expect.equal 2 (Dict.size es.allVersions)
                            ]
                            entryState

                    Nothing ->
                        Expect.fail "Entry should exist"
        , test "modification of non-existent entry is ignored" <|
            \_ ->
                let
                    modifiedEntry =
                        makeExpenseEntry "entry2" "entry1" 2000 defaultExpenseData

                    events =
                        [ makeEnvelope "e1" 2000 "admin" (EntryModified modifiedEntry)
                        ]

                    state =
                        GroupState.applyEvents events
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
                        makeExpenseEntry "entry1" "entry1" 1000 defaultExpenseData

                    events =
                        [ makeEnvelope "e1" 1000 "admin" (EntryAdded entry)
                        , makeEnvelope "e2" 2000 "admin" (EntryDeleted { rootId = "entry1" })
                        ]

                    state =
                        GroupState.applyEvents events
                in
                case Dict.get "entry1" state.entries of
                    Just entryState ->
                        Expect.equal True entryState.isDeleted

                    Nothing ->
                        Expect.fail "Entry should exist"
        , test "undeleted entry is restored" <|
            \_ ->
                let
                    entry =
                        makeExpenseEntry "entry1" "entry1" 1000 defaultExpenseData

                    events =
                        [ makeEnvelope "e1" 1000 "admin" (EntryAdded entry)
                        , makeEnvelope "e2" 2000 "admin" (EntryDeleted { rootId = "entry1" })
                        , makeEnvelope "e3" 3000 "admin" (EntryUndeleted { rootId = "entry1" })
                        ]

                    state =
                        GroupState.applyEvents events
                in
                case Dict.get "entry1" state.entries of
                    Just entryState ->
                        Expect.equal False entryState.isDeleted

                    Nothing ->
                        Expect.fail "Entry should exist"
        , test "deleted entries excluded from active entries" <|
            \_ ->
                let
                    entry1 =
                        makeExpenseEntry "entry1" "entry1" 1000 defaultExpenseData

                    entry2 =
                        makeExpenseEntry "entry2" "entry2" 1001 defaultExpenseData

                    events =
                        [ makeEnvelope "e1" 1000 "admin" (EntryAdded entry1)
                        , makeEnvelope "e2" 1001 "admin" (EntryAdded entry2)
                        , makeEnvelope "e3" 2000 "admin" (EntryDeleted { rootId = "entry1" })
                        ]

                    state =
                        GroupState.applyEvents events

                    active =
                        GroupState.activeEntries state
                in
                Expect.equal 1 (List.length active)
        , test "delete non-existent entry is ignored" <|
            \_ ->
                let
                    events =
                        [ makeEnvelope "e1" 1000 "admin" (EntryDeleted { rootId = "ghost" })
                        ]

                    state =
                        GroupState.applyEvents events
                in
                Expect.equal 0 (Dict.size state.entries)
        ]


concurrentModificationTests : Test
concurrentModificationTests =
    describe "Concurrent modification resolution"
        [ test "later timestamp wins" <|
            \_ ->
                let
                    originalEntry =
                        makeExpenseEntry "entry1" "entry1" 1000 defaultExpenseData

                    mod1Data =
                        { defaultExpenseData | description = "Mod by Alice" }

                    mod1 =
                        { meta =
                            { id = "v2"
                            , rootId = "entry1"
                            , previousVersionId = Just "entry1"
                            , notes = Nothing
                            , isDeleted = False
                            , createdBy = "alice"
                            , createdAt = Time.millisToPosix 2000
                            }
                        , kind = Expense mod1Data
                        }

                    mod2Data =
                        { defaultExpenseData | description = "Mod by Bob" }

                    mod2 =
                        { meta =
                            { id = "v3"
                            , rootId = "entry1"
                            , previousVersionId = Just "entry1"
                            , notes = Nothing
                            , isDeleted = False
                            , createdBy = "bob"
                            , createdAt = Time.millisToPosix 3000
                            }
                        , kind = Expense mod2Data
                        }

                    events =
                        [ makeEnvelope "e1" 1000 "admin" (EntryAdded originalEntry)
                        , makeEnvelope "e2" 2000 "alice" (EntryModified mod1)
                        , makeEnvelope "e3" 3000 "bob" (EntryModified mod2)
                        ]

                    state =
                        GroupState.applyEvents events
                in
                case Dict.get "entry1" state.entries of
                    Just entryState ->
                        Expect.equal "v3" entryState.currentVersion.meta.id

                    Nothing ->
                        Expect.fail "Entry should exist"
        , test "id breaks timestamp tie" <|
            \_ ->
                let
                    originalEntry =
                        makeExpenseEntry "entry1" "entry1" 1000 defaultExpenseData

                    mod1Data =
                        { defaultExpenseData | description = "Mod A" }

                    mod1 =
                        { meta =
                            { id = "v-aaa"
                            , rootId = "entry1"
                            , previousVersionId = Just "entry1"
                            , notes = Nothing
                            , isDeleted = False
                            , createdBy = "alice"
                            , createdAt = Time.millisToPosix 2000
                            }
                        , kind = Expense mod1Data
                        }

                    mod2Data =
                        { defaultExpenseData | description = "Mod B" }

                    mod2 =
                        { meta =
                            { id = "v-zzz"
                            , rootId = "entry1"
                            , previousVersionId = Just "entry1"
                            , notes = Nothing
                            , isDeleted = False
                            , createdBy = "bob"
                            , createdAt = Time.millisToPosix 2000
                            }
                        , kind = Expense mod2Data
                        }

                    events =
                        [ makeEnvelope "e1" 1000 "admin" (EntryAdded originalEntry)
                        , makeEnvelope "e2" 2000 "alice" (EntryModified mod1)
                        , makeEnvelope "e3" 2000 "bob" (EntryModified mod2)
                        ]

                    state =
                        GroupState.applyEvents events
                in
                case Dict.get "entry1" state.entries of
                    Just entryState ->
                        -- "v-zzz" > "v-aaa" lexicographically, so v-zzz wins
                        Expect.equal "v-zzz" entryState.currentVersion.meta.id

                    Nothing ->
                        Expect.fail "Entry should exist"
        ]
