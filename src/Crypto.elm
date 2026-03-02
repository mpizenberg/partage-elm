module Crypto exposing (generateGroupKey)

{-| Cryptographic helpers for group key management.
-}

import ConcurrentTask exposing (ConcurrentTask)
import WebCrypto.Symmetric as Symmetric


{-| Generate a new AES-256-GCM group key.
-}
generateGroupKey : ConcurrentTask a Symmetric.Key
generateGroupKey =
    Symmetric.generateKey
        |> ConcurrentTask.mapError never
