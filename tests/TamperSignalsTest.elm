module TamperSignalsTest exposing (suite)

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
                        ]
        , test "recording forged signatures bumps the count, stamps the time, and raises the banner" <|
            \_ ->
                let
                    at : Time.Posix
                    at =
                        Time.millisToPosix 1234
                in
                TamperSignals.recordForgedSignatures 2 at TamperSignals.empty
                    |> Expect.all
                        [ .forgedSignatures >> Expect.equal 2
                        , .lastDetectedAt >> Expect.equal (Just at)
                        , TamperSignals.isClean >> Expect.equal False
                        , TamperSignals.bannerWorthy >> Expect.equal True
                        ]
        , test "recording zero (or fewer) forged signatures is a no-op that leaves no timestamp" <|
            \_ ->
                TamperSignals.recordForgedSignatures 0 (Time.millisToPosix 9) TamperSignals.empty
                    |> Expect.equal TamperSignals.empty
        , test "forged counts accumulate across recordings" <|
            \_ ->
                TamperSignals.empty
                    |> TamperSignals.recordForgedSignatures 1 (Time.millisToPosix 1)
                    |> TamperSignals.recordForgedSignatures 3 (Time.millisToPosix 5)
                    |> Expect.all
                        [ .forgedSignatures >> Expect.equal 4
                        , .lastDetectedAt >> Expect.equal (Just (Time.millisToPosix 5))
                        ]
        , test "encode/decode round-trips a non-empty record" <|
            \_ ->
                let
                    signals : TamperSignals.TamperSignals
                    signals =
                        TamperSignals.recordForgedSignatures 7 (Time.millisToPosix 42) TamperSignals.empty
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
