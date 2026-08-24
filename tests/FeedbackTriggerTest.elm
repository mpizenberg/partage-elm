module FeedbackTriggerTest exposing (suite)

import Domain.Currency exposing (Currency(..))
import Domain.Entry as Entry exposing (Beneficiary(..), Kind(..))
import Domain.Event exposing (Envelope, Payload(..))
import Domain.FeedbackMoment as FeedbackMoment exposing (Trigger(..))
import Domain.GroupState as GroupState exposing (GroupState)
import Domain.Member as Member
import Expect
import Test exposing (Test, describe, test)
import TestHelpers exposing (makeEnvelope)
import Time


now : Time.Posix
now =
    Time.millisToPosix (400 * dayMs)


dayMs : Int
dayMs =
    24 * 60 * 60 * 1000


{-| Every group starts with a genesis by "admin" and the given members, all
real unless the name starts with "ghost".
-}
groupOf : List Member.Id -> List Envelope
groupOf memberIds =
    makeEnvelope "genesis" 0 "admin" (GroupCreated { name = "Trip", defaultCurrency = EUR })
        :: List.indexedMap
            (\index memberId ->
                makeEnvelope ("member-" ++ memberId)
                    (index + 1)
                    "admin"
                    (MemberCreated
                        { memberId = memberId
                        , name = memberId
                        , memberType =
                            if String.startsWith "ghost" memberId then
                                Member.Virtual

                            else
                                Member.Real
                        , addedBy = "admin"
                        }
                    )
            )
            memberIds


{-| An expense whose payer and only beneficiary is its author, so it moves no
balance and leaves the settlement plan empty.
-}
neutralExpense : Int -> Member.Id -> Envelope
neutralExpense index author =
    let
        base : Entry.ExpenseData
        base =
            TestHelpers.defaultExpenseData

        entryId : String
        entryId =
            "entry-" ++ String.fromInt index ++ "-" ++ author

        createdAt : Int
        createdAt =
            Time.posixToMillis now - dayMs - index
    in
    makeEnvelope ("ev-" ++ entryId)
        createdAt
        author
        (EntryAdded
            { meta = Entry.newMetadata entryId author (Time.millisToPosix createdAt)
            , kind =
                Expense
                    { base
                        | payers = [ { memberId = author, amount = 1000 } ]
                        , beneficiaries = [ ShareBeneficiary { memberId = author, shares = 1 } ]
                    }
            }
        )


{-| An expense one member paid for two, which leaves exactly one transaction in
the settlement plan.
-}
debtExpense : Int -> Member.Id -> Member.Id -> Envelope
debtExpense index payer debtor =
    let
        base : Entry.ExpenseData
        base =
            TestHelpers.defaultExpenseData

        entryId : String
        entryId =
            "debt-" ++ String.fromInt index

        createdAt : Int
        createdAt =
            Time.posixToMillis now - dayMs - index
    in
    makeEnvelope ("ev-" ++ entryId)
        createdAt
        payer
        (EntryAdded
            { meta = Entry.newMetadata entryId payer (Time.millisToPosix createdAt)
            , kind =
                Expense
                    { base
                        | payers = [ { memberId = payer, amount = 1000 } ]
                        , beneficiaries =
                            [ ShareBeneficiary { memberId = payer, shares = 1 }
                            , ShareBeneficiary { memberId = debtor, shares = 1 }
                            ]
                    }
            }
        )


stateOf : List Envelope -> GroupState
stateOf events =
    GroupState.applyEvents events GroupState.empty


detectFor : Member.Id -> Bool -> GroupState -> Maybe Trigger
detectFor selfRootId justAddedTransfer state =
    FeedbackMoment.detect
        { now = now, selfRootId = selfRootId, justAddedTransfer = justAddedTransfer }
        state


{-| Four claimed members, one who never joined, ten entries, nothing left to
settle — the shape trigger C is looking for.
-}
refusalGroup : List Envelope
refusalGroup =
    groupOf [ "admin", "alice", "bob", "carol", "ghost" ]
        ++ List.map (\index -> neutralExpense index "alice") (List.range 1 10)


{-| Five claimed members and ten entries, one of which leaves a single debt.
-}
concludedGroup : List Envelope
concludedGroup =
    groupOf [ "admin", "alice", "bob", "carol", "dave" ]
        ++ (debtExpense 0 "alice" "bob"
                :: List.map (\index -> neutralExpense index "alice") (List.range 1 9)
           )


suite : Test
suite =
    describe "FeedbackMoment.detect"
        [ describe "C — a group some members refused to join"
            [ test "asks the creator" <|
                \_ ->
                    stateOf refusalGroup
                        |> detectFor "admin" False
                        |> Expect.equal (Just Refusal)
            , test "asks nobody else" <|
                \_ ->
                    stateOf refusalGroup
                        |> detectFor "alice" False
                        |> Expect.equal Nothing
            , test "stays quiet when every member joined" <|
                \_ ->
                    stateOf
                        (groupOf [ "admin", "alice", "bob", "carol" ]
                            ++ List.map (\index -> neutralExpense index "alice") (List.range 1 10)
                        )
                        |> detectFor "admin" False
                        |> Expect.equal Nothing
            , test "stays quiet when the genesis event was compacted away" <|
                \_ ->
                    stateOf (List.drop 1 refusalGroup)
                        |> detectFor "admin" False
                        |> Expect.equal Nothing
            , test "stays quiet once the creator has left the group" <|
                \_ ->
                    stateOf (refusalGroup ++ [ makeEnvelope "retire" 500 "alice" (MemberRetired { rootId = "admin" }) ])
                        |> detectFor "admin" False
                        |> Expect.equal Nothing
            ]
        , describe "A — a group that just concluded"
            [ test "asks the member who just recorded a transfer" <|
                \_ ->
                    stateOf concludedGroup
                        |> detectFor "carol" True
                        |> Expect.equal (Just Concluded)
            , test "asks nobody who merely opens the group afterwards" <|
                \_ ->
                    stateOf concludedGroup
                        |> detectFor "carol" False
                        |> Expect.equal Nothing
            , test "stays quiet while more than a fifth of the group is unsettled" <|
                \_ ->
                    stateOf
                        (groupOf [ "admin", "alice", "bob", "carol", "dave" ]
                            ++ (debtExpense 0 "alice" "bob"
                                    :: debtExpense 1 "carol" "dave"
                                    :: List.map (\index -> neutralExpense index "alice") (List.range 2 10)
                               )
                        )
                        |> detectFor "carol" True
                        |> Expect.equal Nothing
            ]
        , describe "B — the member carrying the group"
            [ test "asks the strict top author" <|
                \_ ->
                    stateOf (prolificGroup 60 40)
                        |> detectFor "alice" False
                        |> Expect.equal (Just Prolific)
            , test "asks nobody when two members are tied" <|
                \_ ->
                    stateOf (prolificGroup 50 50)
                        |> detectFor "alice" False
                        |> Expect.equal Nothing
            , test "asks nobody below a hundred entries" <|
                \_ ->
                    stateOf (prolificGroup 60 39)
                        |> detectFor "alice" False
                        |> Expect.equal Nothing
            ]
        , test "a group nobody has written to in a week says nothing" <|
            \_ ->
                stateOf refusalGroup
                    |> FeedbackMoment.detect
                        { now = Time.millisToPosix (Time.posixToMillis now + 8 * dayMs)
                        , selfRootId = "admin"
                        , justAddedTransfer = False
                        }
                    |> Expect.equal Nothing
        ]


prolificGroup : Int -> Int -> List Envelope
prolificGroup fromAlice fromBob =
    groupOf [ "admin", "alice", "bob", "carol", "dave" ]
        ++ List.map (\index -> neutralExpense index "alice") (List.range 1 fromAlice)
        ++ List.map (\index -> neutralExpense (1000 + index) "bob") (List.range 1 fromBob)
