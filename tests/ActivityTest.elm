module ActivityTest exposing (suite)

import Domain.Activity as Activity exposing (ChangedField(..), Detail(..), StateContext)
import Domain.Entry as Entry exposing (Beneficiary(..), Entry)
import Domain.Event exposing (Payload(..))
import Domain.Member as Member
import Expect
import Test exposing (Test, describe, test)
import TestHelpers


changesFor : Entry -> Entry -> Maybe (List ChangedField)
changesFor previous current =
    Activity.fromEnvelope (contextWithPrevious previous)
        (TestHelpers.makeEnvelope "modify" 2 "alice" (EntryModified current))
        |> Maybe.andThen
            (\activity ->
                case activity.detail of
                    EntryModifiedDetail data ->
                        Just data.changes

                    TransferModifiedDetail data ->
                        Just data.changes

                    _ ->
                        Nothing
            )


contextWithPrevious : Entry -> StateContext
contextWithPrevious previous =
    { resolveName = identity
    , memberMetadata = always Member.emptyMetadata
    , entryDescription = always ""
    , entryCurrentVersion = always Nothing
    , previousVersion = always (Just previous)
    , groupMeta = { name = "Group", subtitle = Nothing, description = Nothing, links = [] }
    , settlementPreference = always []
    }


suite : Test
suite =
    describe "activity entry change detection"
        [ test "tracks allocation, converted amount and location changes in expenses" <|
            \_ ->
                let
                    baseData : Entry.ExpenseData
                    baseData =
                        TestHelpers.defaultExpenseData

                    oldData : Entry.ExpenseData
                    oldData =
                        { baseData
                            | defaultCurrencyAmount = Just 1000
                            , payers =
                                [ { memberId = "alice", amount = 600 }
                                , { memberId = "bob", amount = 400 }
                                ]
                            , location = Just "Old place"
                        }

                    newData : Entry.ExpenseData
                    newData =
                        { oldData
                            | defaultCurrencyAmount = Just 1100
                            , payers =
                                [ { memberId = "alice", amount = 500 }
                                , { memberId = "bob", amount = 500 }
                                ]
                            , beneficiaries =
                                [ ShareBeneficiary { memberId = "alice", shares = 2 }
                                , ShareBeneficiary { memberId = "bob", shares = 1 }
                                ]
                            , location = Just "New place"
                        }
                in
                changesFor
                    (TestHelpers.makeExpenseEntry "entry-v1" 0 oldData)
                    (TestHelpers.makeExpenseEntry "entry-v2" 1 newData)
                    |> Expect.equal (Just [ AmountField, PayersField, BeneficiariesField, LocationField ])
        , test "treats a transfer converted-amount change as an amount change" <|
            \_ ->
                let
                    baseData : Entry.TransferData
                    baseData =
                        TestHelpers.defaultTransferData

                    oldData : Entry.TransferData
                    oldData =
                        { baseData | defaultCurrencyAmount = Just 500 }

                    newData : Entry.TransferData
                    newData =
                        { oldData | defaultCurrencyAmount = Just 550 }
                in
                changesFor
                    (TestHelpers.makeTransferEntry "entry-v1" 0 oldData)
                    (TestHelpers.makeTransferEntry "entry-v2" 1 newData)
                    |> Expect.equal (Just [ AmountField ])
        , test "gives income receiver and converted-amount changes typed identities" <|
            \_ ->
                let
                    baseData : Entry.IncomeData
                    baseData =
                        TestHelpers.defaultIncomeData

                    oldData : Entry.IncomeData
                    oldData =
                        { baseData | defaultCurrencyAmount = Just 1000 }

                    newData : Entry.IncomeData
                    newData =
                        { oldData | defaultCurrencyAmount = Just 1100, receivedBy = "bob" }
                in
                changesFor
                    (TestHelpers.makeIncomeEntry "entry-v1" 0 oldData)
                    (TestHelpers.makeIncomeEntry "entry-v2" 1 newData)
                    |> Expect.equal (Just [ AmountField, ReceivedByField ])
        ]
