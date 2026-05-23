module StableSettlementIntegrationTest exposing (suite)

{-| Integration tests for the anchor cache (`anchorEntries`, `anchorBalances`,
`anchorPrefs`) maintained by `Domain.GroupState`. They check that anchor-mover
events trigger a re-snapshot while non-anchor-mover events leave the cache
untouched. See `Domain.GroupState.isAnchorMover` for the classification.
-}

import Dict
import Domain.Entry as Entry
import Domain.Event exposing (Envelope, Payload(..))
import Domain.GroupState as GroupState
import Domain.Member as Member
import Expect
import Test exposing (Test, describe, test)
import TestHelpers
    exposing
        ( bootstrapMembers
        , defaultExpenseData
        , defaultTransferData
        , makeEnvelope
        , makeExpenseEntry
        , makeTransferEntry
        )



-- TIMELINE BUILDING


{-| State after applying `bootstrapMembers` (admin, alice, bob) + one expense
that fixes a non-trivial anchor: alice paid 1000, split 50/50.
-}
afterFirstExpense : GroupState.GroupState
afterFirstExpense =
    GroupState.applyEvents
        (bootstrapMembers
            ++ [ makeEnvelope "e-exp-1"
                    10
                    "alice"
                    (EntryAdded (makeExpenseEntry "exp-1" 10 defaultExpenseData))
               ]
        )
        GroupState.empty


suite : Test
suite =
    describe "StableSettlement anchor cache (GroupState wiring)"
        [ expenseEventTests
        , transferEventTests
        , preferenceTests
        , memberMetadataTests
        , preAnchorTransferEditDeviationTest
        ]


expenseEventTests : Test
expenseEventTests =
    describe "Non-transfer entry events are anchor-movers"
        [ test "first expense snapshots anchor matching current state" <|
            \_ ->
                let
                    state : GroupState.GroupState
                    state =
                        afterFirstExpense
                in
                Expect.equal state.balances state.anchorBalances
        , test "adding a second expense resnapshots" <|
            \_ ->
                let
                    state : GroupState.GroupState
                    state =
                        GroupState.applyEvents
                            [ makeEnvelope "e-exp-2"
                                20
                                "bob"
                                (EntryAdded
                                    (makeExpenseEntry "exp-2"
                                        20
                                        { defaultExpenseData
                                            | description = "Second"
                                            , amount = 400
                                            , payers = [ { memberId = "bob", amount = 400 } ]
                                        }
                                    )
                                )
                            ]
                            afterFirstExpense
                in
                Expect.equal state.balances state.anchorBalances
        , test "deleting an expense resnapshots" <|
            \_ ->
                let
                    state : GroupState.GroupState
                    state =
                        GroupState.applyEvents
                            [ makeEnvelope "e-del" 30 "alice" (EntryDeleted { rootId = "exp-1" })
                            ]
                            afterFirstExpense
                in
                Expect.equal state.balances state.anchorBalances
        ]


transferEventTests : Test
transferEventTests =
    describe "Transfer events are NOT anchor-movers"
        [ test "adding a transfer leaves the anchor untouched" <|
            \_ ->
                let
                    baseAnchorEntries =
                        afterFirstExpense.anchorEntries

                    state : GroupState.GroupState
                    state =
                        GroupState.applyEvents
                            [ makeEnvelope "e-trf-1"
                                20
                                "bob"
                                (EntryAdded (makeTransferEntry "trf-1" 20 defaultTransferData))
                            ]
                            afterFirstExpense
                in
                Expect.all
                    [ \_ -> Expect.equal baseAnchorEntries state.anchorEntries
                    , \_ -> Expect.equal afterFirstExpense.anchorBalances state.anchorBalances
                    , \_ -> Expect.notEqual state.balances state.anchorBalances
                    ]
                    ()
        , test "editing a (post-anchor) transfer leaves the anchor untouched" <|
            \_ ->
                let
                    stateWithTransfer : GroupState.GroupState
                    stateWithTransfer =
                        GroupState.applyEvents
                            [ makeEnvelope "e-trf-1"
                                20
                                "bob"
                                (EntryAdded (makeTransferEntry "trf-1" 20 defaultTransferData))
                            ]
                            afterFirstExpense

                    baseAnchorEntries =
                        stateWithTransfer.anchorEntries

                    edited : Entry.Entry
                    edited =
                        Entry.replace
                            (makeTransferEntry "trf-1" 20 defaultTransferData).meta
                            "trf-1-v2"
                            (.kind (makeTransferEntry "trf-1" 20 { defaultTransferData | amount = 200 }))

                    state : GroupState.GroupState
                    state =
                        GroupState.applyEvents
                            [ makeEnvelope "e-trf-1-edit" 30 "bob" (EntryModified edited) ]
                            stateWithTransfer
                in
                Expect.equal baseAnchorEntries state.anchorEntries
        , test "deleting a transfer leaves the anchor untouched" <|
            \_ ->
                let
                    stateWithTransfer : GroupState.GroupState
                    stateWithTransfer =
                        GroupState.applyEvents
                            [ makeEnvelope "e-trf-1"
                                20
                                "bob"
                                (EntryAdded (makeTransferEntry "trf-1" 20 defaultTransferData))
                            ]
                            afterFirstExpense

                    baseAnchorEntries =
                        stateWithTransfer.anchorEntries

                    state : GroupState.GroupState
                    state =
                        GroupState.applyEvents
                            [ makeEnvelope "e-trf-1-del" 30 "bob" (EntryDeleted { rootId = "trf-1" })
                            ]
                            stateWithTransfer
                in
                Expect.equal baseAnchorEntries state.anchorEntries
        ]


preferenceTests : Test
preferenceTests =
    describe "SettlementPreferencesUpdated is an anchor-mover"
        [ test "preference change resnapshots anchorPrefs" <|
            \_ ->
                let
                    state : GroupState.GroupState
                    state =
                        GroupState.applyEvents
                            [ makeEnvelope "e-pref"
                                20
                                "bob"
                                (SettlementPreferencesUpdated
                                    { memberRootId = "bob", preferredRecipients = [ "alice" ] }
                                )
                            ]
                            afterFirstExpense
                in
                Expect.equal state.settlementPreferences state.anchorPrefs
        , test "preference change resnapshots after a transfer (anchor catches up)" <|
            \_ ->
                let
                    stateAfterTransfer : GroupState.GroupState
                    stateAfterTransfer =
                        GroupState.applyEvents
                            [ makeEnvelope "e-trf"
                                20
                                "bob"
                                (EntryAdded (makeTransferEntry "trf-1" 20 defaultTransferData))
                            ]
                            afterFirstExpense

                    state : GroupState.GroupState
                    state =
                        GroupState.applyEvents
                            [ makeEnvelope "e-pref"
                                30
                                "bob"
                                (SettlementPreferencesUpdated
                                    { memberRootId = "bob", preferredRecipients = [ "alice" ] }
                                )
                            ]
                            stateAfterTransfer
                in
                Expect.equal state.balances state.anchorBalances
        ]


memberMetadataTests : Test
memberMetadataTests =
    describe "Member events are NOT anchor-movers"
        [ test "member rename leaves the anchor untouched" <|
            \_ ->
                let
                    baseAnchorEntries =
                        afterFirstExpense.anchorEntries

                    state : GroupState.GroupState
                    state =
                        GroupState.applyEvents
                            [ makeEnvelope "e-rename"
                                15
                                "alice"
                                (MemberRenamed { rootId = "alice", oldName = "Alice", newName = "Alicia" })
                            ]
                            afterFirstExpense
                in
                Expect.equal baseAnchorEntries state.anchorEntries
        , test "member metadata update leaves the anchor untouched" <|
            \_ ->
                let
                    baseAnchorEntries =
                        afterFirstExpense.anchorEntries

                    state : GroupState.GroupState
                    state =
                        GroupState.applyEvents
                            [ makeEnvelope "e-meta"
                                15
                                "alice"
                                (MemberMetadataUpdated
                                    { rootId = "alice", metadata = Member.emptyMetadata }
                                )
                            ]
                            afterFirstExpense
                in
                Expect.equal baseAnchorEntries state.anchorEntries
        ]


preAnchorTransferEditDeviationTest : Test
preAnchorTransferEditDeviationTest =
    describe "Pre-anchor transfer edit is NOT an anchor-mover"
        [ test "pre-anchor transfer edit leaves the anchor untouched; vector update absorbs the diff" <|
            \_ ->
                -- Timeline: bootstrap, expense (anchor1), transfer1, expense2 (anchor2), edit transfer1.
                -- The edit of transfer1 is a transfer event → not anchor-mover.
                let
                    timeline : List Envelope
                    timeline =
                        bootstrapMembers
                            ++ [ makeEnvelope "e-exp-1"
                                    10
                                    "alice"
                                    (EntryAdded (makeExpenseEntry "exp-1" 10 defaultExpenseData))
                               , makeEnvelope "e-trf-1"
                                    20
                                    "bob"
                                    (EntryAdded (makeTransferEntry "trf-1" 20 defaultTransferData))
                               , makeEnvelope "e-exp-2"
                                    30
                                    "alice"
                                    (EntryAdded
                                        (makeExpenseEntry "exp-2"
                                            30
                                            { defaultExpenseData
                                                | description = "Second"
                                                , amount = 400
                                                , payers = [ { memberId = "alice", amount = 400 } ]
                                            }
                                        )
                                    )
                               ]

                    stateBeforeEdit : GroupState.GroupState
                    stateBeforeEdit =
                        GroupState.applyEvents timeline GroupState.empty

                    baseAnchorEntries =
                        stateBeforeEdit.anchorEntries

                    editedTransfer : Entry.Entry
                    editedTransfer =
                        Entry.replace
                            (makeTransferEntry "trf-1" 20 defaultTransferData).meta
                            "trf-1-v2"
                            (.kind (makeTransferEntry "trf-1" 20 { defaultTransferData | amount = 200 }))

                    stateAfterEdit : GroupState.GroupState
                    stateAfterEdit =
                        GroupState.applyEvents
                            [ makeEnvelope "e-trf-edit" 40 "bob" (EntryModified editedTransfer) ]
                            stateBeforeEdit
                in
                Expect.all
                    [ \_ -> Expect.equal baseAnchorEntries stateAfterEdit.anchorEntries
                    , \_ -> Expect.equal stateBeforeEdit.anchorBalances stateAfterEdit.anchorBalances
                    , -- Balance for alice should reflect the new transfer amount, not the old.
                      \_ ->
                        Dict.get "alice" stateAfterEdit.balances
                            |> Maybe.map .netBalance
                            |> Expect.notEqual
                                (Dict.get "alice" stateBeforeEdit.balances
                                    |> Maybe.map .netBalance
                                )
                    ]
                    ()
        ]
