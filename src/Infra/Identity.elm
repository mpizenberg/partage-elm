module Infra.Identity exposing (Identity, decoder, encode, generate, rekey)

import ConcurrentTask exposing (ConcurrentTask)
import Json.Decode as Decode
import Json.Encode as Encode
import WebCrypto
import WebCrypto.Signature as Signature


{-| A user's identity: the current device's signing key pair, its public-key hash
(the device id), and the ids of keys it has replaced. `previousDeviceIds` lets a
migration still recognise events this device authored under an old, compromised
key as "you".
-}
type alias Identity =
    { publicKeyHash : String
    , signingKeyPair : Signature.SerializedSigningKeyPair
    , previousDeviceIds : List String
    }


{-| Generate a new identity by creating a signing key pair and hashing the public key.
-}
generate : ConcurrentTask WebCrypto.Error Identity
generate =
    Signature.generateSigningKeyPair
        |> ConcurrentTask.mapError never
        |> ConcurrentTask.andThen
            (\kp ->
                let
                    serialized : Signature.SerializedSigningKeyPair
                    serialized =
                        Signature.exportSigningKeyPair kp
                in
                WebCrypto.sha256 serialized.publicKey
                    |> ConcurrentTask.map
                        (\hash ->
                            { publicKeyHash = hash
                            , signingKeyPair = serialized
                            , previousDeviceIds = []
                            }
                        )
            )


{-| Mint a fresh signing key for this device, remembering the id it replaces. The
old key stays valid in every un-migrated group until this device re-links there, so
re-keying only sheds a compromise when paired with per-group migration + re-link.
-}
rekey : Identity -> ConcurrentTask WebCrypto.Error Identity
rekey current =
    generate
        |> ConcurrentTask.map
            (\fresh -> { fresh | previousDeviceIds = current.publicKeyHash :: current.previousDeviceIds })


{-| Encode an Identity to JSON.
-}
encode : Identity -> Encode.Value
encode identity =
    Encode.object
        [ ( "publicKeyHash", Encode.string identity.publicKeyHash )
        , ( "signingKeyPair", Signature.encodeSerializedSigningKeyPair identity.signingKeyPair )
        , ( "previousDeviceIds", Encode.list Encode.string identity.previousDeviceIds )
        ]


{-| Decode an Identity from JSON. `previousDeviceIds` defaults to empty so
identities stored before re-key existed still decode.
-}
decoder : Decode.Decoder Identity
decoder =
    Decode.map3 Identity
        (Decode.field "publicKeyHash" Decode.string)
        (Decode.field "signingKeyPair" Signature.serializedSigningKeyPairDecoder)
        (Decode.oneOf
            [ Decode.field "previousDeviceIds" (Decode.list Decode.string)
            , Decode.succeed []
            ]
        )
