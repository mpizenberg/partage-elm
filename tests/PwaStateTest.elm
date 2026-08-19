module PwaStateTest exposing (suite)

import Expect
import PwaState
import Test exposing (Test, describe, test)


base : PwaState.Model
base =
    PwaState.init { isOnline = True, installHint = "none" }


suite : Test
suite =
    describe "PwaState push configuration"
        [ test "the last known push server is available before any fetch answers" <|
            \_ ->
                base
                    |> PwaState.withCachedPushServer (Just "https://push.example.com")
                    |> PwaState.pushServerUrl
                    |> Expect.equal (Just "https://push.example.com")
        , test "a remembered push server does not read as unreachable" <|
            \_ ->
                base
                    |> PwaState.withCachedPushServer (Just "https://push.example.com")
                    |> PwaState.notificationUnavailable
                    |> Expect.equal False
        , test "nothing remembered leaves the deployment without push" <|
            \_ ->
                base
                    |> PwaState.withCachedPushServer Nothing
                    |> PwaState.pushServerUrl
                    |> Expect.equal Nothing
        ]
