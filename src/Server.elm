module Server exposing
    ( Error(..)
    , PullResult
    , ServerContext
    , SyncResult
    , authenticate
    , createGroupOnServer
    , errorToString
    , subscribeToGroup
    , syncGroup
    )

{-| PocketBase server sync module.

Handles authentication, encrypted event push/pull, and realtime subscriptions.
All operations are ConcurrentTasks that compose with the existing task pool.

-}

import ConcurrentTask exposing (ConcurrentTask)
import Crypto
import Domain.Event as Event
import Domain.Group as Group
import Json.Decode as Decode
import Json.Encode as Encode
import PocketBase
import PocketBase.Auth
import PocketBase.Collection
import PocketBase.Custom
import PocketBase.Realtime
import WebCrypto
import WebCrypto.ProofOfWork as PoW
import WebCrypto.Symmetric as Symmetric


{-| Context for server operations on a specific group.
-}
type alias ServerContext =
    { client : PocketBase.Client
    , groupId : Group.Id
    , groupKey : Symmetric.Key
    }


{-| A server event record from the "events" PocketBase collection.
-}
type alias ServerEventRecord =
    { id : String
    , groupId : String
    , actorId : String
    , eventData : String
    , created : String
    }


{-| Combined error type for server operations that involve both PocketBase and WebCrypto.
-}
type Error
    = PbError PocketBase.Error
    | CryptoError WebCrypto.Error


{-| Convert a server error to a human-readable string.
-}
errorToString : Error -> String
errorToString err =
    case err of
        PbError pbErr ->
            case pbErr of
                PocketBase.NotFound ->
                    "Not found"

                PocketBase.Unauthorized ->
                    "Unauthorized"

                PocketBase.Forbidden ->
                    "Forbidden"

                PocketBase.BadRequest msg ->
                    "Bad request: " ++ msg

                PocketBase.Conflict ->
                    "Conflict"

                PocketBase.TooManyRequests ->
                    "Too many requests"

                PocketBase.ServerError msg ->
                    "Server error: " ++ msg

                PocketBase.NetworkError msg ->
                    "Network error: " ++ msg

        CryptoError cryptoErr ->
            case cryptoErr of
                WebCrypto.EncryptionFailed msg ->
                    "Encryption failed: " ++ msg

                WebCrypto.DecryptionFailed msg ->
                    "Decryption failed: " ++ msg

                _ ->
                    "Crypto error"



-- Authentication


{-| Authenticate to the server for a group.
Derives password from group key and authenticates as `group_{groupId}`.
-}
authenticate : PocketBase.Client -> { groupId : Group.Id, groupKey : Symmetric.Key } -> ConcurrentTask Error ()
authenticate client { groupId, groupKey } =
    Crypto.derivePassword groupKey
        |> ConcurrentTask.mapError CryptoError
        |> ConcurrentTask.andThen
            (\password ->
                PocketBase.Auth.authWithPassword client
                    { collection = "users"
                    , identity = "group_" ++ groupId
                    , password = password
                    , decoder = Decode.succeed ()
                    }
                    |> ConcurrentTask.mapError PbError
            )



-- Group creation


{-| Create a group on the server: solve PoW, create group record, create user account, authenticate.
-}
createGroupOnServer :
    PocketBase.Client
    -> { groupId : Group.Id, groupKey : Symmetric.Key, createdBy : String }
    -> ConcurrentTask Error ()
createGroupOnServer client { groupId, groupKey, createdBy } =
    -- Step 1: Get and solve PoW challenge
    fetchPowChallenge client
        |> ConcurrentTask.andThen
            (\challenge ->
                PoW.solveChallenge challenge
                    |> ConcurrentTask.mapError CryptoError
            )
        |> ConcurrentTask.andThen
            (\solution ->
                -- Step 2: Create group record with PoW solution
                PocketBase.Collection.create client
                    { collection = "groups"
                    , body =
                        Encode.object
                            [ ( "id", Encode.string groupId )
                            , ( "createdBy", Encode.string createdBy )
                            , ( "pow_challenge", Encode.string solution.pow_challenge )
                            , ( "pow_timestamp", Encode.int solution.pow_timestamp )
                            , ( "pow_difficulty", Encode.int solution.pow_difficulty )
                            , ( "pow_signature", Encode.string solution.pow_signature )
                            , ( "pow_solution", Encode.string solution.pow_solution )
                            ]
                    , decoder = Decode.succeed ()
                    }
                    |> ConcurrentTask.mapError PbError
            )
        |> ConcurrentTask.andThen
            (\() ->
                -- Step 3: Create user account
                Crypto.derivePassword groupKey
                    |> ConcurrentTask.mapError CryptoError
                    |> ConcurrentTask.andThen
                        (\password ->
                            PocketBase.Auth.createAccount client
                                { collection = "users"
                                , body =
                                    Encode.object
                                        [ ( "username", Encode.string ("group_" ++ groupId) )
                                        , ( "password", Encode.string password )
                                        , ( "passwordConfirm", Encode.string password )
                                        , ( "groupId", Encode.string groupId )
                                        ]
                                , decoder = Decode.succeed ()
                                }
                                |> ConcurrentTask.mapError PbError
                        )
            )
        |> ConcurrentTask.andThen
            (\() ->
                -- Step 4: Authenticate
                authenticate client { groupId = groupId, groupKey = groupKey }
            )


fetchPowChallenge : PocketBase.Client -> ConcurrentTask Error PoW.Challenge
fetchPowChallenge client =
    PocketBase.Custom.fetch client
        { method = "GET"
        , path = "/api/pow/challenge"
        , body = Nothing
        , decoder = PoW.challengeDecoder
        }
        |> ConcurrentTask.mapError PbError



-- Event push


{-| Push local events to the server. Encrypts each event with the group key.
-}
pushEvents : ServerContext -> String -> List Event.Envelope -> ConcurrentTask Error ()
pushEvents ctx actorId envelopes =
    envelopes
        |> List.map (pushSingleEvent ctx actorId)
        |> ConcurrentTask.batch
        |> ConcurrentTask.map (\_ -> ())


pushSingleEvent : ServerContext -> String -> Event.Envelope -> ConcurrentTask Error ()
pushSingleEvent ctx actorId envelope =
    Symmetric.encryptJson ctx.groupKey (Event.encodeEnvelope envelope)
        |> ConcurrentTask.mapError CryptoError
        |> ConcurrentTask.andThen
            (\encrypted ->
                PocketBase.Collection.create ctx.client
                    { collection = "events"
                    , body =
                        Encode.object
                            [ ( "groupId", Encode.string ctx.groupId )
                            , ( "actorId", Encode.string actorId )
                            , ( "eventData", Encode.string (Encode.encode 0 (Symmetric.encodeEncryptedData encrypted)) )
                            ]
                    , decoder = Decode.succeed ()
                    }
                    |> ConcurrentTask.mapError PbError
            )



-- Bidirectional sync


{-| Result of a sync operation with push count and pull result.
-}
type alias SyncResult =
    { pullResult : PullResult
    , pushedCount : Int
    }


{-| Sync a group: push unpushed events, then pull new events from the server.
-}
syncGroup :
    ServerContext
    -> String
    -> { unpushedEvents : List Event.Envelope, pullCursor : Maybe String }
    -> ConcurrentTask Error SyncResult
syncGroup ctx actorId { unpushedEvents, pullCursor } =
    let
        pushedCount : Int
        pushedCount =
            List.length unpushedEvents
    in
    pushEvents ctx actorId unpushedEvents
        |> ConcurrentTask.andThen
            (\() ->
                pullEvents ctx pullCursor
                    |> ConcurrentTask.map (\pull -> { pullResult = pull, pushedCount = pushedCount })
            )



-- Event pull


{-| Pull result with decrypted events and the new sync cursor.
-}
type alias PullResult =
    { events : List Event.Envelope
    , cursor : String
    }


{-| Pull events from the server since the given cursor. Decrypts each event.
-}
pullEvents : ServerContext -> Maybe String -> ConcurrentTask Error PullResult
pullEvents ctx maybeCursor =
    pullAllPages ctx maybeCursor 1 []


pullAllPages : ServerContext -> Maybe String -> Int -> List Event.Envelope -> ConcurrentTask Error PullResult
pullAllPages ctx maybeCursor page accEvents =
    let
        filter : String
        filter =
            case maybeCursor of
                Just cursor ->
                    "groupId=\"" ++ ctx.groupId ++ "\" && created>\"" ++ cursor ++ "\""

                Nothing ->
                    "groupId=\"" ++ ctx.groupId ++ "\""
    in
    PocketBase.Collection.getList ctx.client
        { collection = "events"
        , page = page
        , perPage = 200
        , filter = Just filter
        , sort = Just "+created"
        , decoder = serverEventRecordDecoder
        }
        |> ConcurrentTask.mapError PbError
        |> ConcurrentTask.andThen
            (\result ->
                decryptServerEvents ctx.groupKey result.items
                    |> ConcurrentTask.andThen
                        (\decryptedEvents ->
                            let
                                allEvents : List Event.Envelope
                                allEvents =
                                    accEvents ++ decryptedEvents
                            in
                            if page < result.totalPages then
                                pullAllPages ctx maybeCursor (page + 1) allEvents

                            else
                                let
                                    lastCursor : String
                                    lastCursor =
                                        List.head (List.reverse result.items)
                                            |> Maybe.map .created
                                            |> Maybe.withDefault (Maybe.withDefault "" maybeCursor)
                                in
                                ConcurrentTask.succeed { events = allEvents, cursor = lastCursor }
                        )
            )


decryptServerEvents : Symmetric.Key -> List ServerEventRecord -> ConcurrentTask Error (List Event.Envelope)
decryptServerEvents key records =
    records
        |> List.map (decryptServerEvent key)
        |> ConcurrentTask.batch


decryptServerEvent : Symmetric.Key -> ServerEventRecord -> ConcurrentTask Error Event.Envelope
decryptServerEvent key record =
    case Decode.decodeString Symmetric.encryptedDataDecoder record.eventData of
        Ok encrypted ->
            Symmetric.decryptJson key Event.envelopeDecoder encrypted
                |> ConcurrentTask.mapError CryptoError

        Err err ->
            ConcurrentTask.fail (CryptoError (WebCrypto.DecryptionFailed ("Invalid eventData JSON: " ++ Decode.errorToString err)))


serverEventRecordDecoder : Decode.Decoder ServerEventRecord
serverEventRecordDecoder =
    Decode.map5 ServerEventRecord
        (Decode.field "id" Decode.string)
        (Decode.field "groupId" Decode.string)
        (Decode.field "actorId" Decode.string)
        (Decode.field "eventData" Decode.string)
        (Decode.field "created" Decode.string)



-- Realtime subscriptions


{-| Subscribe to realtime events for the "events" collection.
Events arrive via the onPocketbaseEvent port.
-}
subscribeToGroup : PocketBase.Client -> ConcurrentTask Never ()
subscribeToGroup client =
    PocketBase.Realtime.subscribe client "events"
