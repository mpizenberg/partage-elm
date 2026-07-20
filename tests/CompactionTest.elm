module CompactionTest exposing (suite)

import Domain.Compaction as Compaction
import Domain.Event as Event
import Expect
import Json.Decode as Decode
import Test exposing (Test, describe, test)


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
    describe "Compaction.manifest"
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
