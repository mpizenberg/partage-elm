module TestHelpers exposing
    ( bootstrapMembers
    , defaultExpenseData
    , defaultTransferData
    , makeEnvelope
    , makeExpenseEntry
    , makeTransferEntry
    )

import Domain.Currency exposing (Currency(..))
import Domain.Entry as Entry exposing (Beneficiary(..), Entry, Kind(..))
import Domain.Event exposing (Envelope, Payload(..))
import Domain.Member as Member
import Time


{-| Bootstrap events creating admin, alice, and bob as members.
Use this at the start of test event lists so that isAuthorized passes.
-}
bootstrapMembers : List Envelope
bootstrapMembers =
    [ makeEnvelope "boot-admin" 0 "admin" (MemberCreated { memberId = "admin", name = "Admin", memberType = Member.Real, addedBy = "admin" })
    , makeEnvelope "boot-alice" 1 "admin" (MemberCreated { memberId = "alice", name = "Alice", memberType = Member.Real, addedBy = "admin" })
    , makeEnvelope "boot-bob" 2 "admin" (MemberCreated { memberId = "bob", name = "Bob", memberType = Member.Real, addedBy = "admin" })
    ]


makeEnvelope : String -> Int -> Member.Id -> Payload -> Envelope
makeEnvelope eventId timestamp triggeredBy payload =
    { id = eventId
    , clientTimestamp = Time.millisToPosix timestamp
    , triggeredBy = triggeredBy
    , payload = payload
    }


makeEntryMeta : String -> Int -> Entry.Metadata
makeEntryMeta entryId timestamp =
    Entry.newMetadata entryId "creator" (Time.millisToPosix timestamp)


defaultExpenseData : Entry.ExpenseData
defaultExpenseData =
    { description = "Test expense"
    , amount = 1000
    , currency = EUR
    , defaultCurrencyAmount = Nothing
    , date = { year = 2025, month = 1, day = 1 }
    , payers = [ { memberId = "alice", amount = 1000 } ]
    , beneficiaries =
        [ ShareBeneficiary { memberId = "alice", shares = 1 }
        , ShareBeneficiary { memberId = "bob", shares = 1 }
        ]
    , category = Nothing
    , location = Nothing
    , notes = Nothing
    }


defaultTransferData : Entry.TransferData
defaultTransferData =
    { amount = 500
    , currency = EUR
    , defaultCurrencyAmount = Nothing
    , date = { year = 2025, month = 1, day = 1 }
    , from = "alice"
    , to = "bob"
    , notes = Nothing
    }


makeExpenseEntry : String -> Int -> Entry.ExpenseData -> Entry
makeExpenseEntry entryId timestamp expenseData =
    { meta = makeEntryMeta entryId timestamp
    , kind = Expense expenseData
    }


makeTransferEntry : String -> Int -> Entry.TransferData -> Entry
makeTransferEntry entryId timestamp transferData =
    { meta = makeEntryMeta entryId timestamp
    , kind = Transfer transferData
    }
