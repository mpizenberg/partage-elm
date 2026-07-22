module IdentityTest exposing (suite)

import Expect
import Infra.Identity as Identity exposing (Identity)
import Json.Decode as Decode
import Test exposing (Test, describe, test)


sample : Identity
sample =
    { publicKeyHash = "hash-new"
    , signingKeyPair = { publicKey = "pub", privateKey = "priv" }
    , previousDeviceIds = [ "hash-old", "hash-older" ]
    }


suite : Test
suite =
    describe "Infra.Identity"
        [ test "encode then decode round-trips previousDeviceIds" <|
            \_ ->
                Identity.encode sample
                    |> Decode.decodeValue Identity.decoder
                    |> Expect.equal (Ok sample)
        , test "an identity stored before re-key decodes with no previous ids" <|
            \_ ->
                """{"publicKeyHash":"h","signingKeyPair":{"publicKey":"pub","privateKey":"priv"}}"""
                    |> Decode.decodeString Identity.decoder
                    |> Result.map .previousDeviceIds
                    |> Expect.equal (Ok [])
        ]
