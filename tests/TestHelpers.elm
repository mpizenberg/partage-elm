module TestHelpers exposing
    ( defaultExpenseData
    , defaultTransferData
    , makeEntry
    , makeEntryMeta
    , makeEnvelope
    , makeExpenseEntry
    , makeTransferEntry
    , memberIdFuzzer
    , timestampFuzzer
    )

import Domain.Currency exposing (Currency(..))
import Domain.Entry as Entry exposing (Beneficiary(..), Category(..), Entry, Kind(..))
import Domain.Event exposing (Envelope, Payload(..))
import Domain.Member as Member
import Fuzz exposing (Fuzzer)
import Time


memberIdFuzzer : Fuzzer String
memberIdFuzzer =
    Fuzz.map (\i -> "member-" ++ String.fromInt (abs i)) Fuzz.int


timestampFuzzer : Fuzzer Time.Posix
timestampFuzzer =
    Fuzz.map (\i -> Time.millisToPosix (abs i)) Fuzz.int


makeEnvelope : String -> Int -> Member.Id -> Payload -> Envelope
makeEnvelope eventId timestamp triggeredBy payload =
    { id = eventId
    , clientTimestamp = Time.millisToPosix timestamp
    , triggeredBy = triggeredBy
    , payload = payload
    }


makeEntryMeta : String -> String -> Int -> Entry.Metadata
makeEntryMeta entryId rootId timestamp =
    { id = entryId
    , rootId = rootId
    , previousVersionId = Nothing
    , notes = Nothing
    , isDeleted = False
    , createdBy = "creator"
    , createdAt = Time.millisToPosix timestamp
    }


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
    }


defaultTransferData : Entry.TransferData
defaultTransferData =
    { amount = 500
    , currency = EUR
    , defaultCurrencyAmount = Nothing
    , date = { year = 2025, month = 1, day = 1 }
    , from = "alice"
    , to = "bob"
    }


makeEntry : Entry.Metadata -> Kind -> Entry
makeEntry meta kind =
    { meta = meta, kind = kind }


makeExpenseEntry : String -> String -> Int -> Entry.ExpenseData -> Entry
makeExpenseEntry entryId rootId timestamp expenseData =
    { meta = makeEntryMeta entryId rootId timestamp
    , kind = Expense expenseData
    }


makeTransferEntry : String -> String -> Int -> Entry.TransferData -> Entry
makeTransferEntry entryId rootId timestamp transferData =
    { meta = makeEntryMeta entryId rootId timestamp
    , kind = Transfer transferData
    }
