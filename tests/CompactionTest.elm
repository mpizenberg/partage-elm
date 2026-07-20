module CompactionTest exposing (suite)

import Domain.Compaction as Compaction
import Domain.Event as Event exposing (Payload(..))
import Domain.Member as Member
import Expect
import Json.Decode as Decode
import Test exposing (Test, describe, test)
import TestHelpers exposing (makeEnvelope)
import Time


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
        , executableProposalTests
        , quorumedProposalTests
        , proposalDraftTests
        , chunkTests
        , attestationTests
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


{-| alice, bob and carol each authored one event in the compacted range;
alice proposed.
-}
threeActorLog : List Event.Envelope
threeActorLog =
    [ makeEnvelope "e1" 100 "alice" (Event.EntryDeleted { rootId = "x" })
    , makeEnvelope "e2" 200 "bob" (Event.EntryDeleted { rootId = "y" })
    , makeEnvelope "e3" 300 "carol" (Event.EntryDeleted { rootId = "z" })
    , makeEnvelope "p1" 400 "alice" (CompactionProposed { uptoEventId = "e3", eventCount = 3, manifestHash = "H" })
    ]


threeActors : { resolveRoot : Member.Id -> Maybe Member.Id, isRetired : Member.Id -> Bool }
threeActors =
    { resolveRoot =
        \memberId ->
            if List.member memberId [ "alice", "bob", "carol" ] then
                Just memberId

            else
                Nothing
    , isRetired = \_ -> False
    }


approval : String -> Member.Id -> Int -> Event.Envelope
approval eventId by timestamp =
    makeEnvelope eventId timestamp by (CompactionApproved { proposalId = "p1" })


executableProposalTests : Test
executableProposalTests =
    describe "executableProposal"
        [ test "proposer alone is 1 of 3 — no quorum" <|
            \_ ->
                Compaction.executableProposal threeActors threeActorLog
                    |> Expect.equal Nothing
        , test "proposer plus one approval is 2 of 3 — quorum" <|
            \_ ->
                Compaction.executableProposal threeActors (threeActorLog ++ [ approval "a1" "bob" 500 ])
                    |> Maybe.map (\ex -> ( ex.proposalId, ex.claimedHash, List.map .id ex.prefix ))
                    |> Expect.equal (Just ( "p1", "H", [ "e1", "e2", "e3" ] ))
        , test "an approval from an uninvolved member carries no weight" <|
            \_ ->
                let
                    withDave : { resolveRoot : Member.Id -> Maybe Member.Id, isRetired : Member.Id -> Bool }
                    withDave =
                        { threeActors | resolveRoot = \m -> Just m }
                in
                Compaction.executableProposal withDave (threeActorLog ++ [ approval "a1" "dave" 500 ])
                    |> Expect.equal Nothing
        , test "a retired member leaves the denominator" <|
            \_ ->
                -- carol retired: alice (proposer) is 1 of 2 — still no quorum;
                -- with bob's approval it is 2 of 2.
                let
                    carolRetired : { resolveRoot : Member.Id -> Maybe Member.Id, isRetired : Member.Id -> Bool }
                    carolRetired =
                        { threeActors | isRetired = (==) "carol" }
                in
                ( Compaction.executableProposal carolRetired threeActorLog
                , Compaction.executableProposal carolRetired (threeActorLog ++ [ approval "a1" "bob" 500 ])
                    |> Maybe.map .proposalId
                )
                    |> Expect.equal ( Nothing, Just "p1" )
        , test "a claimed event count mismatch disqualifies the proposal" <|
            \_ ->
                let
                    badCount : List Event.Envelope
                    badCount =
                        [ makeEnvelope "e1" 100 "alice" (Event.EntryDeleted { rootId = "x" })
                        , makeEnvelope "p1" 400 "alice" (CompactionProposed { uptoEventId = "e1", eventCount = 2, manifestHash = "H" })
                        , approval "a1" "bob" 500
                        ]
                in
                Compaction.executableProposal threeActors badCount
                    |> Expect.equal Nothing
        , test "the newest quorumed proposal wins" <|
            \_ ->
                let
                    twoProposals : List Event.Envelope
                    twoProposals =
                        [ makeEnvelope "e1" 100 "alice" (Event.EntryDeleted { rootId = "x" })
                        , makeEnvelope "e2" 200 "bob" (Event.EntryDeleted { rootId = "y" })
                        , makeEnvelope "p1" 300 "alice" (CompactionProposed { uptoEventId = "e1", eventCount = 1, manifestHash = "H1" })
                        , makeEnvelope "p2" 400 "alice" (CompactionProposed { uptoEventId = "e2", eventCount = 2, manifestHash = "H2" })
                        , makeEnvelope "a1" 500 "bob" (CompactionApproved { proposalId = "p1" })
                        , makeEnvelope "a2" 600 "bob" (CompactionApproved { proposalId = "p2" })
                        ]
                in
                Compaction.executableProposal threeActors twoProposals
                    |> Maybe.map .proposalId
                    |> Expect.equal (Just "p2")
        ]


quorumedProposalTests : Test
quorumedProposalTests =
    describe "quorumedProposal"
        [ test "reports a quorumed proposal even when the count diverges" <|
            \_ ->
                let
                    divergent : List Event.Envelope
                    divergent =
                        [ makeEnvelope "e1" 100 "alice" (Event.EntryDeleted { rootId = "x" })
                        , makeEnvelope "e2" 200 "bob" (Event.EntryDeleted { rootId = "y" })
                        , makeEnvelope "p1" 400 "alice" (CompactionProposed { uptoEventId = "e2", eventCount = 1, manifestHash = "H" })
                        , makeEnvelope "a1" 500 "bob" (CompactionApproved { proposalId = "p1" })
                        ]
                in
                Compaction.quorumedProposal threeActors divergent
                    |> Maybe.map (\q -> ( q.claimedCount, q.prefixCount ))
                    |> Expect.equal (Just ( 1, 2 ))
        , test "no quorum means nothing to verify" <|
            \_ ->
                Compaction.quorumedProposal threeActors threeActorLog
                    |> Expect.equal Nothing
        ]


attestationTests : Test
attestationTests =
    describe "attestation"
        [ test "round-trips through the fragment tail" <|
            \_ ->
                Compaction.attestationTail (wireEnvelopes [ e2, e1 ])
                    |> Maybe.andThen Compaction.parseAttestation
                    |> Expect.equal (Just { eventCount = 2, headId = "e2" })
        , test "an empty log yields no attestation" <|
            \_ ->
                Compaction.attestationTail []
                    |> Expect.equal Nothing
        , test "head ids containing dashes survive the round trip" <|
            \_ ->
                Compaction.parseAttestation "7-0198c9c2-4a5b-7c33"
                    |> Expect.equal (Just { eventCount = 7, headId = "0198c9c2-4a5b-7c33" })
        , test "unknown tail formats parse as no attestation" <|
            \_ ->
                ( Compaction.parseAttestation "future", Compaction.parseAttestation "x-abc" )
                    |> Expect.equal ( Nothing, Nothing )
        , test "a history reaches the attestation with enough events and the head present" <|
            \_ ->
                Compaction.historyReaches { eventCount = 2, headId = "e2" } (wireEnvelopes [ e1, e2, e3 ])
                    |> Expect.equal True
        , test "a missing head means the history falls short" <|
            \_ ->
                Compaction.historyReaches { eventCount = 2, headId = "e9" } (wireEnvelopes [ e1, e2, e3 ])
                    |> Expect.equal False
        , test "too few events means the history falls short" <|
            \_ ->
                Compaction.historyReaches { eventCount = 3, headId = "e2" } (wireEnvelopes [ e1, e2 ])
                    |> Expect.equal False
        ]


proposalDraftTests : Test
proposalDraftTests =
    describe "proposalDraft"
        [ test "drafts over the full sorted log" <|
            \_ ->
                Compaction.proposalDraft (Time.millisToPosix 1000)
                    [ makeEnvelope "e2" 200 "bob" (Event.EntryDeleted { rootId = "y" })
                    , makeEnvelope "e1" 100 "alice" (Event.EntryDeleted { rootId = "x" })
                    ]
                    |> Maybe.map (\draft -> ( draft.uptoEventId, draft.eventCount ))
                    |> Expect.equal (Just ( "e2", 2 ))
        , test "an empty log yields no draft" <|
            \_ ->
                Compaction.proposalDraft (Time.millisToPosix 1000) []
                    |> Expect.equal Nothing
        , test "a proposal within the cooldown suppresses drafting" <|
            \_ ->
                Compaction.proposalDraft (Time.millisToPosix (100 + Compaction.proposalCooldownMs - 1)) threeActorLog
                    |> Expect.equal Nothing
        , test "an expired cooldown allows a fresh draft" <|
            \_ ->
                Compaction.proposalDraft (Time.millisToPosix (400 + Compaction.proposalCooldownMs)) threeActorLog
                    |> Maybe.map .uptoEventId
                    |> Expect.equal (Just "p1")
        ]


chunkTests : Test
chunkTests =
    describe "chunkEnvelopes"
        [ test "packs greedily under the byte bound, preserving order" <|
            \_ ->
                let
                    envelopes : List Event.Envelope
                    envelopes =
                        wireEnvelopes [ e1, e2, e3 ]

                    size : String -> Int
                    size json =
                        String.length json
                in
                Compaction.chunkEnvelopes (size e1 + size e2) envelopes
                    |> List.map (List.map .id)
                    |> Expect.equal [ [ "e1", "e2" ], [ "e3" ] ]
        , test "an oversized envelope gets its own chunk" <|
            \_ ->
                Compaction.chunkEnvelopes 1 (wireEnvelopes [ e1, e2 ])
                    |> List.map (List.map .id)
                    |> Expect.equal [ [ "e1" ], [ "e2" ] ]
        , test "an empty list yields no chunks" <|
            \_ ->
                Compaction.chunkEnvelopes 100 []
                    |> Expect.equal []
        ]
