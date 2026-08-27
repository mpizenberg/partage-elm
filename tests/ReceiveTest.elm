module ReceiveTest exposing (suite)

import Domain.Member as Member
import Expect
import Infra.Handoff as Handoff
import Infra.Identity exposing (Identity)
import Json.Encode as Encode
import Page.Receive as Receive
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Page.Receive"
        [ test "ignores a payload re-delivered while the first apply is in flight" <|
            \_ ->
                let
                    ( applying, firstEffect ) =
                        Receive.payloadArrived encodedPayload Receive.init

                    ( _, secondEffect ) =
                        Receive.payloadArrived encodedPayload applying
                in
                case ( firstEffect, secondEffect ) of
                    ( Receive.Apply _, Receive.NoEffect ) ->
                        Expect.pass

                    _ ->
                        Expect.fail "Expected exactly the first delivery to start applying"
        ]


encodedPayload : String
encodedPayload =
    Handoff.encode
        { identity = identity
        , groups = []
        , selfProfile = Member.emptyMetadata
        , language = Nothing
        , lastSeenChangelog = Nothing
        }
        |> Encode.encode 0


identity : Identity
identity =
    { publicKeyHash = "source-device"
    , signingKeyPair =
        { publicKey = "public-key"
        , privateKey = "private-key"
        }
    , previousDeviceIds = []
    }
