module Compression exposing (EncryptedBatch, compressAndDownload, decompress, decryptJson, encodeEventData, encryptJson)

{-| Conditional gzip compression combined with AES-256-GCM encryption.

Compresses JSON payloads before encryption when gzip achieves at least 30%
size reduction. Falls back to uncompressed encryption otherwise.
Uses CompressionStream/DecompressionStream Web APIs via ConcurrentTask.

-}

import ConcurrentTask exposing (ConcurrentTask)
import Json.Decode as Decode
import Json.Encode as Encode
import WebCrypto
import WebCrypto.Symmetric as Symmetric


{-| Encrypted data with a compression flag.
The ciphertext may contain gzipped bytes (if compressed) or raw UTF-8 bytes.
-}
type alias EncryptedBatch =
    { ciphertext : String
    , iv : String
    , compressed : Bool
    }


{-| Compress (if beneficial) and encrypt a JSON value.
Compression is applied when gzip reduces the payload by at least 30%.
-}
encryptJson : Symmetric.Key -> Encode.Value -> ConcurrentTask WebCrypto.Error EncryptedBatch
encryptJson key json =
    ConcurrentTask.define
        { function = "compression:encryptJson"
        , expect = ConcurrentTask.expectJson encryptedBatchDecoder
        , errors = ConcurrentTask.expectErrors WebCrypto.errorDecoder
        , args =
            Encode.object
                [ ( "key", Encode.string (Symmetric.exportKey key) )
                , ( "json", Encode.string (Encode.encode 0 json) )
                , ( "threshold", Encode.float 0.7 )
                ]
        }


{-| Decrypt and decompress (if needed) to a typed value.
-}
decryptJson : Symmetric.Key -> Decode.Decoder a -> EncryptedBatch -> ConcurrentTask WebCrypto.Error a
decryptJson key decoder batch =
    ConcurrentTask.define
        { function = "compression:decryptJson"
        , expect = ConcurrentTask.expectString
        , errors = ConcurrentTask.expectErrors WebCrypto.errorDecoder
        , args =
            Encode.object
                [ ( "key", Encode.string (Symmetric.exportKey key) )
                , ( "ciphertext", Encode.string batch.ciphertext )
                , ( "iv", Encode.string batch.iv )
                , ( "compressed", Encode.bool batch.compressed )
                ]
        }
        |> ConcurrentTask.andThen
            (\jsonStr ->
                case Decode.decodeString decoder jsonStr of
                    Ok val ->
                        ConcurrentTask.succeed val

                    Err err ->
                        ConcurrentTask.fail (WebCrypto.DecryptionFailed ("JSON decode error: " ++ Decode.errorToString err))
            )


{-| Decode an EncryptedBatch from JSON.
-}
encryptedBatchDecoder : Decode.Decoder EncryptedBatch
encryptedBatchDecoder =
    Decode.map3 EncryptedBatch
        (Decode.field "ciphertext" Decode.string)
        (Decode.field "iv" Decode.string)
        (Decode.field "compressed" Decode.bool)


{-| Compress a JSON string with gzip and trigger a file download.
-}
compressAndDownload : String -> String -> ConcurrentTask String ()
compressAndDownload json filename =
    ConcurrentTask.define
        { function = "export:compressAndDownload"
        , expect = ConcurrentTask.expectString
        , errors = ConcurrentTask.expectErrors Decode.string
        , args =
            Encode.object
                [ ( "json", Encode.string json )
                , ( "filename", Encode.string filename )
                ]
        }
        |> ConcurrentTask.map (\_ -> ())


{-| Decompress a base64-encoded gzip payload to a string.
-}
decompress : String -> ConcurrentTask String String
decompress base64 =
    ConcurrentTask.define
        { function = "export:decompress"
        , expect = ConcurrentTask.expectString
        , errors = ConcurrentTask.expectErrors Decode.string
        , args =
            Encode.object
                [ ( "base64", Encode.string base64 )
                ]
        }


{-| Encode just the ciphertext and IV for storage in the eventData field.
The compressed flag is stored separately on the PocketBase record.
-}
encodeEventData : EncryptedBatch -> Encode.Value
encodeEventData batch =
    Encode.object
        [ ( "ciphertext", Encode.string batch.ciphertext )
        , ( "iv", Encode.string batch.iv )
        ]
