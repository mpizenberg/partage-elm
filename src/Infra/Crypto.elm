module Infra.Crypto exposing (derivePassword, generateGroupKey)

{-| Cryptographic helpers for group key management.
-}

import Bitwise
import ConcurrentTask exposing (ConcurrentTask)
import WebCrypto
import WebCrypto.Symmetric as Symmetric


{-| Generate a new AES-256-GCM group key.
-}
generateGroupKey : ConcurrentTask a Symmetric.Key
generateGroupKey =
    Symmetric.generateKey
        |> ConcurrentTask.mapError never


{-| Derive a server password from a group key: Base64URL(SHA-256(Base64(groupKey))).
-}
derivePassword : Symmetric.Key -> ConcurrentTask WebCrypto.Error String
derivePassword key =
    WebCrypto.sha256 (Symmetric.exportKey key)
        |> ConcurrentTask.map hexToBase64Url


{-| Convert a hex string to Base64URL encoding (no padding).
-}
hexToBase64Url : String -> String
hexToBase64Url hex =
    hexToByteList hex
        |> bytesToBase64Url


{-| Parse a hex string into a list of byte values.
-}
hexToByteList : String -> List Int
hexToByteList hex =
    hexToByteListHelper (String.toList hex) []
        |> List.reverse


hexToByteListHelper : List Char -> List Int -> List Int
hexToByteListHelper chars acc =
    case chars of
        hi :: lo :: rest ->
            hexToByteListHelper rest ((hexCharToInt hi * 16 + hexCharToInt lo) :: acc)

        _ ->
            acc


hexCharToInt : Char -> Int
hexCharToInt c =
    if c >= '0' && c <= '9' then
        Char.toCode c - Char.toCode '0'

    else if c >= 'a' && c <= 'f' then
        10 + Char.toCode c - Char.toCode 'a'

    else if c >= 'A' && c <= 'F' then
        10 + Char.toCode c - Char.toCode 'A'

    else
        0


{-| Encode a list of bytes as a Base64URL string (no padding).
-}
bytesToBase64Url : List Int -> String
bytesToBase64Url bytes =
    encodeBase64UrlHelper bytes []
        |> List.reverse
        |> String.fromList


encodeBase64UrlHelper : List Int -> List Char -> List Char
encodeBase64UrlHelper bytes acc =
    case bytes of
        a :: b :: c :: rest ->
            let
                n : Int
                n =
                    Bitwise.or (Bitwise.or (Bitwise.shiftLeftBy 16 a) (Bitwise.shiftLeftBy 8 b)) c
            in
            encodeBase64UrlHelper rest
                (base64UrlChar (Bitwise.and n 63)
                    :: base64UrlChar (Bitwise.and (Bitwise.shiftRightBy 6 n) 63)
                    :: base64UrlChar (Bitwise.and (Bitwise.shiftRightBy 12 n) 63)
                    :: base64UrlChar (Bitwise.and (Bitwise.shiftRightBy 18 n) 63)
                    :: acc
                )

        [ a, b ] ->
            let
                n : Int
                n =
                    Bitwise.or (Bitwise.shiftLeftBy 16 a) (Bitwise.shiftLeftBy 8 b)
            in
            base64UrlChar (Bitwise.and (Bitwise.shiftRightBy 6 n) 63)
                :: base64UrlChar (Bitwise.and (Bitwise.shiftRightBy 12 n) 63)
                :: base64UrlChar (Bitwise.and (Bitwise.shiftRightBy 18 n) 63)
                :: acc

        [ a ] ->
            let
                n : Int
                n =
                    Bitwise.shiftLeftBy 16 a
            in
            base64UrlChar (Bitwise.and (Bitwise.shiftRightBy 12 n) 63)
                :: base64UrlChar (Bitwise.and (Bitwise.shiftRightBy 18 n) 63)
                :: acc

        [] ->
            acc


base64UrlChar : Int -> Char
base64UrlChar i =
    case String.uncons (String.slice i (i + 1) "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_") of
        Just ( c, _ ) ->
            c

        Nothing ->
            'A'
