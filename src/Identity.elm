module Identity exposing (Identity, decoder, encode, generate)

import ConcurrentTask exposing (ConcurrentTask)
import Json.Decode as Decode
import Json.Encode as Encode
import WebCrypto
import WebCrypto.Signature as Signature


type alias Identity =
    { publicKeyHash : String
    , signingKeyPair : Signature.SerializedSigningKeyPair
    }


generate : ConcurrentTask WebCrypto.Error Identity
generate =
    Signature.generateSigningKeyPair
        |> ConcurrentTask.mapError never
        |> ConcurrentTask.andThen
            (\kp ->
                let
                    serialized =
                        Signature.exportSigningKeyPair kp
                in
                WebCrypto.sha256 serialized.publicKey
                    |> ConcurrentTask.map
                        (\hash ->
                            { publicKeyHash = hash
                            , signingKeyPair = serialized
                            }
                        )
            )


encode : Identity -> Encode.Value
encode identity =
    Encode.object
        [ ( "publicKeyHash", Encode.string identity.publicKeyHash )
        , ( "signingKeyPair", Signature.encodeSerializedSigningKeyPair identity.signingKeyPair )
        ]


decoder : Decode.Decoder Identity
decoder =
    Decode.map2 Identity
        (Decode.field "publicKeyHash" Decode.string)
        (Decode.field "signingKeyPair" Signature.serializedSigningKeyPairDecoder)
