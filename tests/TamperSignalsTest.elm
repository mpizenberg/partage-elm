module TamperSignalsTest exposing (suite)

import Dict
import Domain.TamperSignals as TamperSignals
import Expect
import Json.Decode as Decode
import Test exposing (Test, describe, test)
import Time


suite : Test
suite =
    describe "Domain.TamperSignals"
        [ test "empty is clean and not banner-worthy" <|
            \_ ->
                TamperSignals.empty
                    |> Expect.all
                        [ TamperSignals.isClean >> Expect.equal True
                        , TamperSignals.bannerWorthy >> Expect.equal False
                        , TamperSignals.forgedCount >> Expect.equal 0
                        ]
        , test "recording forged authors tallies per claimed author, stamps the time, and raises the banner" <|
            \_ ->
                let
                    at : Time.Posix
                    at =
                        Time.millisToPosix 1234
                in
                TamperSignals.recordForgedAuthors [ "bob", "carol", "bob" ] at TamperSignals.empty
                    |> Expect.all
                        [ .forgedAuthors >> Expect.equal (Dict.fromList [ ( "bob", 2 ), ( "carol", 1 ) ])
                        , TamperSignals.forgedCount >> Expect.equal 3
                        , .lastDetectedAt >> Expect.equal (Just at)
                        , TamperSignals.isClean >> Expect.equal False
                        , TamperSignals.bannerWorthy >> Expect.equal True
                        ]
        , test "recording an empty author list is a no-op that leaves no timestamp" <|
            \_ ->
                TamperSignals.recordForgedAuthors [] (Time.millisToPosix 9) TamperSignals.empty
                    |> Expect.equal TamperSignals.empty
        , test "forged tallies accumulate across recordings" <|
            \_ ->
                TamperSignals.empty
                    |> TamperSignals.recordForgedAuthors [ "bob" ] (Time.millisToPosix 1)
                    |> TamperSignals.recordForgedAuthors [ "bob", "dave" ] (Time.millisToPosix 5)
                    |> Expect.all
                        [ .forgedAuthors >> Expect.equal (Dict.fromList [ ( "bob", 2 ), ( "dave", 1 ) ])
                        , .lastDetectedAt >> Expect.equal (Just (Time.millisToPosix 5))
                        ]
        , test "a rate-limit hit raises the banner" <|
            \_ ->
                TamperSignals.recordRateLimitHit (Time.millisToPosix 1) TamperSignals.empty
                    |> Expect.all
                        [ .rateLimitHits >> Expect.equal 1
                        , TamperSignals.bannerWorthy >> Expect.equal True
                        ]
        , test "advisory signals count but never raise the banner" <|
            \_ ->
                TamperSignals.empty
                    |> TamperSignals.recordResetWithLoss (Time.millisToPosix 1)
                    |> TamperSignals.recordManifestMismatch (Time.millisToPosix 2)
                    |> Expect.all
                        [ .resetsWithLoss >> Expect.equal 1
                        , .manifestMismatches >> Expect.equal 1
                        , TamperSignals.isClean >> Expect.equal False
                        , TamperSignals.bannerWorthy >> Expect.equal False
                        ]
        , test "encode/decode round-trips a populated record" <|
            \_ ->
                let
                    signals : TamperSignals.TamperSignals
                    signals =
                        TamperSignals.empty
                            |> TamperSignals.recordForgedAuthors [ "bob", "bob", "eve" ] (Time.millisToPosix 42)
                            |> TamperSignals.recordRateLimitHit (Time.millisToPosix 50)
                            |> TamperSignals.recordResetWithLoss (Time.millisToPosix 60)
                in
                TamperSignals.encode signals
                    |> Decode.decodeValue TamperSignals.decoder
                    |> Expect.equal (Ok signals)
        , test "decoder tolerates a record missing every field" <|
            \_ ->
                "{}"
                    |> Decode.decodeString TamperSignals.decoder
                    |> Expect.equal (Ok TamperSignals.empty)
        ]
