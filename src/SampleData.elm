module SampleData exposing (currentUserId, groupId, groupState, resolveName)

{-| Hardcoded sample data for Phase 2 static UI development.
4 members (Alice, Bob, Carol, Dave) with expenses and a transfer.
-}

import Dict
import Domain.Currency exposing (Currency(..))
import Domain.Entry as Entry exposing (Beneficiary(..), Kind(..))
import Domain.Event exposing (Envelope, Payload(..))
import Domain.GroupState as GroupState exposing (GroupState)
import Domain.Member as Member
import Time


groupId : String
groupId =
    "sample-group-001"


currentUserId : Member.Id
currentUserId =
    "member-alice"


groupState : GroupState
groupState =
    GroupState.applyEvents sampleEvents


resolveName : Member.Id -> String
resolveName memberId =
    case Dict.get memberId groupState.members of
        Just member ->
            member.name

        Nothing ->
            memberId



-- EVENTS


sampleEvents : List Envelope
sampleEvents =
    [ -- Group metadata
      envelope "evt-01" 1000 currentUserId <|
        GroupMetadataUpdated
            { name = Just "Trip to Paris"
            , subtitle = Just (Just "Summer 2025")
            , description = Just (Just "Expenses for our Paris trip")
            , links = Nothing
            }

    -- Members
    , envelope "evt-02" 1001 currentUserId <|
        MemberCreated
            { memberId = "member-alice"
            , name = "Alice"
            , memberType = Member.Real
            , addedBy = "member-alice"
            }
    , envelope "evt-03" 1002 currentUserId <|
        MemberCreated
            { memberId = "member-bob"
            , name = "Bob"
            , memberType = Member.Real
            , addedBy = "member-alice"
            }
    , envelope "evt-04" 1003 currentUserId <|
        MemberCreated
            { memberId = "member-carol"
            , name = "Carol"
            , memberType = Member.Virtual
            , addedBy = "member-alice"
            }
    , envelope "evt-05" 1004 currentUserId <|
        MemberCreated
            { memberId = "member-dave"
            , name = "Dave"
            , memberType = Member.Real
            , addedBy = "member-alice"
            }

    -- Expense 1: Dinner - Alice paid 8000 cents (80.00 EUR), split 4 ways
    , envelope "evt-06" 2000 currentUserId <|
        EntryAdded
            { meta = Entry.newMetadata "entry-001" "member-alice" (Time.millisToPosix 2000)
            , kind =
                Expense
                    { description = "Dinner at Le Comptoir"
                    , amount = 8000
                    , currency = EUR
                    , defaultCurrencyAmount = Nothing
                    , date = { year = 2025, month = 7, day = 15 }
                    , payers = [ { memberId = "member-alice", amount = 8000 } ]
                    , beneficiaries =
                        [ ShareBeneficiary { memberId = "member-alice", shares = 1 }
                        , ShareBeneficiary { memberId = "member-bob", shares = 1 }
                        , ShareBeneficiary { memberId = "member-carol", shares = 1 }
                        , ShareBeneficiary { memberId = "member-dave", shares = 1 }
                        ]
                    , category = Just Entry.Food
                    , location = Just "Paris"
                    , notes = Nothing
                    }
            }

    -- Expense 2: Metro tickets - Bob paid 3200 cents (32.00 EUR), split 4 ways
    , envelope "evt-07" 3000 "member-bob" <|
        EntryAdded
            { meta = Entry.newMetadata "entry-002" "member-bob" (Time.millisToPosix 3000)
            , kind =
                Expense
                    { description = "Metro tickets"
                    , amount = 3200
                    , currency = EUR
                    , defaultCurrencyAmount = Nothing
                    , date = { year = 2025, month = 7, day = 15 }
                    , payers = [ { memberId = "member-bob", amount = 3200 } ]
                    , beneficiaries =
                        [ ShareBeneficiary { memberId = "member-alice", shares = 1 }
                        , ShareBeneficiary { memberId = "member-bob", shares = 1 }
                        , ShareBeneficiary { memberId = "member-carol", shares = 1 }
                        , ShareBeneficiary { memberId = "member-dave", shares = 1 }
                        ]
                    , category = Just Entry.Transport
                    , location = Just "Paris"
                    , notes = Nothing
                    }
            }

    -- Expense 3: Museum - Carol paid 4800 cents (48.00 EUR), split 4 ways
    , envelope "evt-08" 4000 "member-carol" <|
        EntryAdded
            { meta = Entry.newMetadata "entry-003" "member-carol" (Time.millisToPosix 4000)
            , kind =
                Expense
                    { description = "Louvre Museum"
                    , amount = 4800
                    , currency = EUR
                    , defaultCurrencyAmount = Nothing
                    , date = { year = 2025, month = 7, day = 16 }
                    , payers = [ { memberId = "member-carol", amount = 4800 } ]
                    , beneficiaries =
                        [ ShareBeneficiary { memberId = "member-alice", shares = 1 }
                        , ShareBeneficiary { memberId = "member-bob", shares = 1 }
                        , ShareBeneficiary { memberId = "member-carol", shares = 1 }
                        , ShareBeneficiary { memberId = "member-dave", shares = 1 }
                        ]
                    , category = Just Entry.Entertainment
                    , location = Just "Paris"
                    , notes = Nothing
                    }
            }

    -- Expense 4: Groceries - Alice paid 2400 cents (24.00 EUR), split 4 ways
    , envelope "evt-09" 5000 currentUserId <|
        EntryAdded
            { meta = Entry.newMetadata "entry-004" "member-alice" (Time.millisToPosix 5000)
            , kind =
                Expense
                    { description = "Groceries"
                    , amount = 2400
                    , currency = EUR
                    , defaultCurrencyAmount = Nothing
                    , date = { year = 2025, month = 7, day = 16 }
                    , payers = [ { memberId = "member-alice", amount = 2400 } ]
                    , beneficiaries =
                        [ ShareBeneficiary { memberId = "member-alice", shares = 1 }
                        , ShareBeneficiary { memberId = "member-bob", shares = 1 }
                        , ShareBeneficiary { memberId = "member-carol", shares = 1 }
                        , ShareBeneficiary { memberId = "member-dave", shares = 1 }
                        ]
                    , category = Just Entry.Groceries
                    , location = Nothing
                    , notes = Nothing
                    }
            }

    -- Transfer: Dave pays Alice 10.00 EUR
    , envelope "evt-10" 6000 "member-dave" <|
        EntryAdded
            { meta = Entry.newMetadata "entry-005" "member-dave" (Time.millisToPosix 6000)
            , kind =
                Transfer
                    { amount = 1000
                    , currency = EUR
                    , defaultCurrencyAmount = Nothing
                    , date = { year = 2025, month = 7, day = 17 }
                    , from = "member-dave"
                    , to = "member-alice"
                    , notes = Just "Partial settlement"
                    }
            }
    ]


envelope : String -> Int -> Member.Id -> Payload -> Envelope
envelope id timestamp triggeredBy payload =
    { id = id
    , clientTimestamp = Time.millisToPosix timestamp
    , triggeredBy = triggeredBy
    , payload = payload
    }
