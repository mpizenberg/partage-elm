module Server exposing
    ( Error(..)
    , PullResult
    , ServerContext
    , SyncData
    , SyncResult
    , authenticateAndSync
    , createGroupOnServer
    , errorToString
    , realtimeEventDecoder
    , subscribeToGroup
    )

{-| PocketBase server sync module.

Handles authentication, encrypted event push/pull, and realtime subscriptions.
All operations are ConcurrentTasks that compose with the existing task pool.

-}

import Compression
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
import PushServer
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
    , compressed : Bool
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


{-| Push local events to the server as a single encrypted batch.
Compresses the payload before encryption when gzip achieves at least 30% reduction.
-}
pushEvents : ServerContext -> String -> List Event.Envelope -> ConcurrentTask Error ()
pushEvents ctx actorId envelopes =
    if List.isEmpty envelopes then
        ConcurrentTask.succeed ()

    else
        Compression.encryptJson ctx.groupKey (Encode.list Event.encodeEnvelope envelopes)
            |> ConcurrentTask.mapError CryptoError
            |> ConcurrentTask.andThen
                (\result ->
                    PocketBase.Collection.create ctx.client
                        { collection = "events"
                        , body =
                            Encode.object
                                [ ( "groupId", Encode.string ctx.groupId )
                                , ( "actorId", Encode.string actorId )
                                , ( "eventData", Encode.string (Encode.encode 0 (Compression.encodeEventData result)) )
                                , ( "compressed", Encode.bool result.compressed )
                                ]
                        , decoder = Decode.succeed ()
                        }
                        |> ConcurrentTask.mapError PbError
                )



-- Bidirectional sync


type alias SyncData =
    { unpushedEvents : List Event.Envelope
    , pullCursor : Maybe String
    , notifyContext : Maybe PushServer.NotifyContext
    }


{-| Result of a sync operation with push count and pull result.
-}
type alias SyncResult =
    { pullResult : PullResult
    , pushedCount : Int
    }


{-| Authenticate then sync a group: push unpushed events, then pull new events from the server.
-}
authenticateAndSync : ServerContext -> String -> SyncData -> ConcurrentTask Error SyncResult
authenticateAndSync ctx actorId syncData =
    authenticate ctx.client { groupId = ctx.groupId, groupKey = ctx.groupKey }
        |> ConcurrentTask.andThenDo (syncGroup ctx actorId syncData)


syncGroup : ServerContext -> String -> SyncData -> ConcurrentTask Error SyncResult
syncGroup ctx actorId { unpushedEvents, pullCursor, notifyContext } =
    let
        pushedCount : Int
        pushedCount =
            List.length unpushedEvents

        notifyTask : ConcurrentTask PushServer.Error ()
        notifyTask =
            case notifyContext of
                Just nc ->
                    if List.isEmpty unpushedEvents then
                        ConcurrentTask.succeed ()

                    else
                        PushServer.notifyAffectedMembers nc unpushedEvents

                Nothing ->
                    ConcurrentTask.succeed ()
    in
    pushEvents ctx actorId unpushedEvents
        |> ConcurrentTask.andThenDo
            (ConcurrentTask.map2 (\_ pull -> { pullResult = pull, pushedCount = pushedCount })
                -- Discard errors on the notify task
                (ConcurrentTask.onError (\_ -> ConcurrentTask.succeed ()) notifyTask)
                -- Pull events
                (pullEvents ctx pullCursor)
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
        |> List.map (decryptServerEventBatch key)
        |> ConcurrentTask.batch
        |> ConcurrentTask.map List.concat


decryptServerEventBatch : Symmetric.Key -> ServerEventRecord -> ConcurrentTask Error (List Event.Envelope)
decryptServerEventBatch key record =
    case Decode.decodeString Symmetric.encryptedDataDecoder record.eventData of
        Ok encrypted ->
            Compression.decryptJson key
                (Decode.list Event.envelopeDecoder)
                { ciphertext = encrypted.ciphertext
                , iv = encrypted.iv
                , compressed = record.compressed
                }
                |> ConcurrentTask.mapError CryptoError

        Err err ->
            ConcurrentTask.fail (CryptoError (WebCrypto.DecryptionFailed ("Invalid eventData JSON: " ++ Decode.errorToString err)))


serverEventRecordDecoder : Decode.Decoder ServerEventRecord
serverEventRecordDecoder =
    Decode.map6 ServerEventRecord
        (Decode.field "id" Decode.string)
        (Decode.field "groupId" Decode.string)
        (Decode.field "actorId" Decode.string)
        (Decode.field "eventData" Decode.string)
        (Decode.field "compressed" Decode.bool)
        (Decode.field "created" Decode.string)



-- Realtime subscriptions


{-| Subscribe to realtime events for the "events" collection.
Events arrive via the onPocketbaseEvent port.
-}
subscribeToGroup : PocketBase.Client -> ConcurrentTask a ()
subscribeToGroup client =
    PocketBase.Realtime.subscribe client "events"
        |> ConcurrentTask.mapError never


{-| Decode the groupId and eventData fields from a realtime event record.
-}
realtimeEventDecoder : Decode.Decoder { groupId : String, eventData : String }
realtimeEventDecoder =
    Decode.map2 (\gid ed -> { groupId = gid, eventData = ed })
        (Decode.field "groupId" Decode.string)
        (Decode.field "eventData" Decode.string)
