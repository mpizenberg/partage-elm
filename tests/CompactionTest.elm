module CompactionTest exposing (suite)

import Domain.Compaction as Compaction
import Domain.Event as Event exposing (Payload(..))
import Domain.Member as Member
import Expect
import Json.Decode as Decode
import Test exposing (Test, describe, test)
import TestHelpers exposing (makeEnvelope)


{-| Envelopes built by decoding wire JSON, so `raw` is the received value —
including fields this app version does not know about.
-}
wireEnvelopes : List String -> List Event.Envelope
wireEnvelopes =
    List.filterMap (Decode.decodeString Event.envelopeDecoder >> Result.toMaybe)


e1 : String
e1 =
    """{"id":"e1","ts":100,"by":"m1","p":{"t":"ed","r":"x"},"sig":"s1"}"""


e2 : String
e2 =
    """{"id":"e2","ts":200,"by":"m2","p":{"t":"zz","future":42},"sig":"s2","extra":true}"""


e3 : String
e3 =
    """{"id":"e3","ts":300,"by":"m1","p":{"t":"eu","r":"x"},"sig":"s3"}"""


suite : Test
suite =
    describe "Compaction"
        [ manifestTests
        , pendingApprovalTests
        ]


manifestTests : Test
manifestTests =
    describe "manifest"
        [ test "concatenates raw envelope JSON in sort order, newline-terminated" <|
            \_ ->
                Compaction.manifest "e2" (wireEnvelopes [ e3, e1, e2 ])
                    |> Expect.equal
                        (Just { input = e1 ++ "\n" ++ e2 ++ "\n", eventCount = 2 })
        , test "boundary at the head of history includes only that event" <|
            \_ ->
                Compaction.manifest "e1" (wireEnvelopes [ e2, e3, e1 ])
                    |> Expect.equal (Just { input = e1 ++ "\n", eventCount = 1 })
        , test "boundary at the last event covers the full log" <|
            \_ ->
                Compaction.manifest "e3" (wireEnvelopes [ e2, e1, e3 ])
                    |> Expect.equal
                        (Just { input = e1 ++ "\n" ++ e2 ++ "\n" ++ e3 ++ "\n", eventCount = 3 })
        , test "unknown boundary id yields Nothing" <|
            \_ ->
                Compaction.manifest "missing" (wireEnvelopes [ e1, e2, e3 ])
                    |> Expect.equal Nothing
        , test "sort ties on timestamp break by event id" <|
            \_ ->
                let
                    tieA : String
                    tieA =
                        """{"id":"a","ts":100,"by":"m1","p":{"t":"ed","r":"x"},"sig":"sa"}"""

                    tieB : String
                    tieB =
                        """{"id":"b","ts":100,"by":"m1","p":{"t":"ed","r":"y"},"sig":"sb"}"""
                in
                Compaction.manifest "b" (wireEnvelopes [ tieB, tieA ])
                    |> Expect.equal
                        (Just { input = tieA ++ "\n" ++ tieB ++ "\n", eventCount = 2 })
        ]


{-| alice's phone is "aliceDev"; everyone else authors under their root id.
-}
resolveRoot : Member.Id -> Maybe Member.Id
resolveRoot memberId =
    case memberId of
        "aliceDev" ->
            Just "alice"

        "alice" ->
            Just "alice"

        "bob" ->
            Just "bob"

        _ ->
            Nothing


{-| e1 by alice and e2 by bob, then bob proposes compacting up to e2.
-}
baseLog : List Event.Envelope
baseLog =
    [ makeEnvelope "e1" 100 "alice" (Event.EntryDeleted { rootId = "x" })
    , makeEnvelope "e2" 200 "bob" (Event.EntryDeleted { rootId = "y" })
    , proposal 2
    ]


proposal : Int -> Event.Envelope
proposal eventCount =
    makeEnvelope "p1"
        300
        "bob"
        (CompactionProposed { uptoEventId = "e2", eventCount = eventCount, manifestHash = "H" })


expectedInput : String
expectedInput =
    Compaction.manifest "e2" baseLog
        |> Maybe.map .input
        |> Maybe.withDefault ""


pendingApprovalTests : Test
pendingApprovalTests =
    describe "pendingApprovals"
        [ test "an involved non-proposer has a pending approval" <|
            \_ ->
                Compaction.pendingApprovals resolveRoot "alice" baseLog
                    |> Expect.equal
                        [ { proposalId = "p1", claimedHash = "H", manifestInput = expectedInput } ]
        , test "the proposer's own proposal is not pending for them" <|
            \_ ->
                Compaction.pendingApprovals resolveRoot "bob" baseLog
                    |> Expect.equal []
        , test "already approved via any of my devices is not pending" <|
            \_ ->
                Compaction.pendingApprovals resolveRoot
                    "alice"
                    (baseLog ++ [ makeEnvelope "a1" 400 "aliceDev" (CompactionApproved { proposalId = "p1" }) ])
                    |> Expect.equal []
        , test "someone else's approval leaves mine pending" <|
            \_ ->
                Compaction.pendingApprovals resolveRoot
                    "alice"
                    (baseLog ++ [ makeEnvelope "a1" 400 "bob" (CompactionApproved { proposalId = "p1" }) ])
                    |> List.map .proposalId
                    |> Expect.equal [ "p1" ]
        , test "an uninvolved member has nothing to approve" <|
            \_ ->
                let
                    bobOnlyRange : List Event.Envelope
                    bobOnlyRange =
                        [ makeEnvelope "e1" 100 "bob" (Event.EntryDeleted { rootId = "x" })
                        , makeEnvelope "e2" 200 "bob" (Event.EntryDeleted { rootId = "y" })
                        , makeEnvelope "p2" 300 "bob" (CompactionProposed { uptoEventId = "e2", eventCount = 2, manifestHash = "H" })
                        , makeEnvelope "e3" 400 "alice" (Event.EntryDeleted { rootId = "z" })
                        ]
                in
                Compaction.pendingApprovals resolveRoot "alice" bobOnlyRange
                    |> Expect.equal []
        , test "a claimed event count that disagrees with the local log is not approvable" <|
            \_ ->
                Compaction.pendingApprovals resolveRoot
                    "alice"
                    [ makeEnvelope "e1" 100 "alice" (Event.EntryDeleted { rootId = "x" })
                    , makeEnvelope "e2" 200 "bob" (Event.EntryDeleted { rootId = "y" })
                    , proposal 3
                    ]
                    |> Expect.equal []
        , test "an unknown boundary is not approvable" <|
            \_ ->
                Compaction.pendingApprovals resolveRoot
                    "alice"
                    [ makeEnvelope "e1" 100 "alice" (Event.EntryDeleted { rootId = "x" })
                    , makeEnvelope "p1" 300 "bob" (CompactionProposed { uptoEventId = "missing", eventCount = 1, manifestHash = "H" })
                    ]
                    |> Expect.equal []
        ]
