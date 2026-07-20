module Infra.Server exposing
    ( Error(..)
    , PullResult
    , ServerContext
    , SyncData
    , SyncResult
    , createGroupOnServer
    , errorToString
    , isNetworkError
    , isNotFound
    , isUnauthorized
    , serverEventDecoder
    , subscribeToGroup
    , sync
    )

{-| Relay server sync module.

Handles encrypted event push/pull and live-update subscriptions against the
Partage relay (see packages/relay). There is no session: every request
carries a bearer secret derived from the group key.

-}

import ConcurrentTask exposing (ConcurrentTask)
import ConcurrentTask.Http as Http
import Domain.Event as Event
import Domain.Group as Group
import Infra.Compression as Compression
import Infra.Crypto as Crypto
import Infra.PushServer as PushServer
import Json.Decode as Decode
import Json.Encode as Encode
import WebCrypto
import WebCrypto.ProofOfWork as PoW
import WebCrypto.Symmetric as Symmetric


{-| Context for server operations on a specific group.
-}
type alias ServerContext =
    { serverUrl : String
    , groupId : Group.Id
    , groupKey : Symmetric.Key
    }


{-| An encrypted event record pulled from the relay.
-}
type alias ServerEventRecord =
    { seq : Int
    , eventData : String
    , compressed : Bool
    }


{-| Combined error type for server operations.
-}
type Error
    = HttpError Http.Error
    | CryptoError WebCrypto.Error
    | InternalError String


{-| Convert a server error to a human-readable string.
-}
errorToString : Error -> String
errorToString err =
    case err of
        HttpError httpErr ->
            case httpErr of
                Http.BadUrl url ->
                    "Bad URL: " ++ url

                Http.Timeout ->
                    "Request timed out"

                Http.NetworkError ->
                    "Network error"

                Http.BadStatus meta _ ->
                    "Server error (" ++ String.fromInt meta.statusCode ++ ")"

                Http.BadBody _ _ _ ->
                    "Invalid server response"

        CryptoError cryptoErr ->
            case cryptoErr of
                WebCrypto.EncryptionFailed msg ->
                    "Encryption failed: " ++ msg

                WebCrypto.DecryptionFailed msg ->
                    "Decryption failed: " ++ msg

                _ ->
                    "Crypto error"

        InternalError msg ->
            msg


{-| True when the server says the group does not exist.
-}
isNotFound : Error -> Bool
isNotFound =
    isStatus 404


{-| Connectivity-shaped failures (no network, or a link so bad the request
timed out). Expected during offline use and retried automatically, so they
should not be surfaced as errors.
-}
isNetworkError : Error -> Bool
isNetworkError err =
    case err of
        HttpError Http.NetworkError ->
            True

        HttpError Http.Timeout ->
            True

        _ ->
            False


{-| True when the server rejected the group credentials.
-}
isUnauthorized : Error -> Bool
isUnauthorized =
    isStatus 401


isStatus : Int -> Error -> Bool
isStatus code err =
    case err of
        HttpError (Http.BadStatus meta _) ->
            meta.statusCode == code

        _ ->
            False


authHeader : String -> Http.Header
authHeader secret =
    Http.header "Authorization" ("Bearer " ++ secret)


eventsUrl : ServerContext -> String
eventsUrl ctx =
    ctx.serverUrl ++ "/api/groups/" ++ ctx.groupId ++ "/events"



-- Group creation


{-| Create a group on the server: solve PoW, then register the group with its
auth verifier.
-}
createGroupOnServer :
    { serverUrl : String, groupId : Group.Id, groupKey : Symmetric.Key, createdBy : String }
    -> ConcurrentTask Error ()
createGroupOnServer { serverUrl, groupId, groupKey, createdBy } =
    let
        solvedChallenge : ConcurrentTask Error PoW.Solution
        solvedChallenge =
            Http.get
                { url = serverUrl ++ "/api/pow/challenge?groupId=" ++ groupId
                , headers = []
                , expect = Http.expectJson PoW.challengeDecoder
                , timeout = Nothing
                }
                |> ConcurrentTask.mapError HttpError
                |> ConcurrentTask.andThen
                    (\challenge ->
                        PoW.solveChallenge challenge
                            |> ConcurrentTask.mapError CryptoError
                    )
    in
    ConcurrentTask.map2 Tuple.pair
        solvedChallenge
        (Crypto.deriveAuthVerifier groupKey |> ConcurrentTask.mapError CryptoError)
        |> ConcurrentTask.andThen
            (\( solution, verifier ) ->
                Http.post
                    { url = serverUrl ++ "/api/groups"
                    , headers = []
                    , body =
                        Http.jsonBody
                            (Encode.object
                                [ ( "groupId", Encode.string groupId )
                                , ( "createdBy", Encode.string createdBy )
                                , ( "authVerifier", Encode.string verifier )
                                , ( "pow_challenge", Encode.string solution.pow_challenge )
                                , ( "pow_timestamp", Encode.int solution.pow_timestamp )
                                , ( "pow_difficulty", Encode.int solution.pow_difficulty )
                                , ( "pow_signature", Encode.string solution.pow_signature )
                                , ( "pow_solution", Encode.string solution.pow_solution )
                                ]
                            )
                    , expect = Http.expectWhatever
                    , timeout = Nothing
                    }
                    |> ConcurrentTask.mapError HttpError
            )



-- Event push


{-| Push local events to the server as a single encrypted batch.
Compresses the payload before encryption when gzip achieves at least 30% reduction.

The recordId is derived from the batched event ids (not generated fresh)
so that re-pushing the same batch — after a push whose response was lost —
hits the server's uniqueness check instead of storing a duplicate record.

-}
pushEvents : ServerContext -> String -> String -> List Event.Envelope -> ConcurrentTask Error ()
pushEvents ctx secret actorId envelopes =
    if List.isEmpty envelopes then
        ConcurrentTask.succeed ()

    else
        ConcurrentTask.map2 Tuple.pair
            (WebCrypto.sha256 (String.join "\n" (List.sort (List.map .id envelopes))))
            (Compression.encryptJson ctx.groupKey (Encode.list Event.encodeEnvelope envelopes))
            |> ConcurrentTask.mapError CryptoError
            |> ConcurrentTask.andThen
                (\( recordId, result ) ->
                    Http.post
                        { url = eventsUrl ctx
                        , headers = [ authHeader secret ]
                        , body =
                            Http.jsonBody
                                (Encode.object
                                    [ ( "actorId", Encode.string actorId )
                                    , ( "recordId", Encode.string recordId )
                                    , ( "eventData", Encode.string (Encode.encode 0 (Compression.encodeEventData result)) )
                                    , ( "compressed", Encode.bool result.compressed )
                                    ]
                                )
                        , expect = Http.expectWhatever
                        , timeout = Nothing
                        }
                        |> ConcurrentTask.mapError HttpError
                )



-- Bidirectional sync


type alias SyncData =
    { unpushedEvents : List Event.Envelope
    , pullCursor : Maybe Int
    , notifyContext : Maybe PushServer.NotifyContext
    }


{-| Result of a sync operation with push count and pull result.
-}
type alias SyncResult =
    { pullResult : PullResult
    , pushedCount : Int
    }


{-| Sync a group: push unpushed events, then pull new events from the server.
-}
sync : ServerContext -> String -> SyncData -> ConcurrentTask Error SyncResult
sync ctx actorId { unpushedEvents, pullCursor, notifyContext } =
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
    Crypto.deriveRelaySecret ctx.groupKey
        |> ConcurrentTask.mapError CryptoError
        |> ConcurrentTask.andThen
            (\secret ->
                pushEvents ctx secret actorId unpushedEvents
                    |> ConcurrentTask.andThenDo
                        (ConcurrentTask.map2 (\_ pull -> { pullResult = pull, pushedCount = pushedCount })
                            -- Discard errors on the notify task
                            (ConcurrentTask.onError (\_ -> ConcurrentTask.succeed ()) notifyTask)
                            -- Pull events
                            (pullEvents ctx secret pullCursor)
                        )
            )



-- Event pull


{-| Pull result with decrypted events and the new sync cursor.
`undecodable` counts skipped items: records that failed to decrypt plus
envelopes whose JSON shape could not be decoded. Skipping instead of
failing keeps one bad record from bricking the group's sync forever.
`didReset` is set when the pull restarted from 0 on a `resetCursor` — the
relay lost events this client has seen, so the caller re-pushes the gap.
-}
type alias PullResult =
    { events : List Event.Envelope
    , cursor : Int
    , undecodable : Int
    , didReset : Bool
    }


{-| Pull events from the server since the given cursor. Decrypts each event.

A `resetCursor` response (the server no longer holds events up to our
cursor — purge, compaction, or resurrection) restarts the pull from 0, at
most once per sync so a misbehaving server cannot loop us forever. The
caller's dedup-by-event-id merge makes the restart loss-free.

-}
pullEvents : ServerContext -> String -> Maybe Int -> ConcurrentTask Error PullResult
pullEvents ctx secret maybeCursor =
    pullAllPages ctx secret True (Maybe.withDefault 0 maybeCursor) { events = [], undecodable = 0, didReset = False }


pullAllPages : ServerContext -> String -> Bool -> Int -> { events : List Event.Envelope, undecodable : Int, didReset : Bool } -> ConcurrentTask Error PullResult
pullAllPages ctx secret allowReset cursor acc =
    Http.get
        { url = eventsUrl ctx ++ "?since=" ++ String.fromInt cursor
        , headers = [ authHeader secret ]
        , expect = Http.expectJson pullPageDecoder
        , timeout = Nothing
        }
        |> ConcurrentTask.mapError HttpError
        |> ConcurrentTask.andThen
            (\page ->
                if page.resetCursor && allowReset then
                    pullAllPages ctx secret False 0 { acc | didReset = True }

                else
                    decryptServerEvents ctx.groupKey page.events
                        |> ConcurrentTask.andThen
                            (\decrypted ->
                                let
                                    newAcc : { events : List Event.Envelope, undecodable : Int, didReset : Bool }
                                    newAcc =
                                        { acc
                                            | events = acc.events ++ decrypted.events
                                            , undecodable = acc.undecodable + decrypted.undecodable
                                        }

                                    newCursor : Int
                                    newCursor =
                                        List.head (List.reverse page.events)
                                            |> Maybe.map .seq
                                            |> Maybe.withDefault cursor
                                in
                                if page.hasMore then
                                    pullAllPages ctx secret allowReset newCursor newAcc

                                else
                                    ConcurrentTask.succeed { events = newAcc.events, cursor = newCursor, undecodable = newAcc.undecodable, didReset = newAcc.didReset }
                            )
            )


decryptServerEvents : Symmetric.Key -> List ServerEventRecord -> ConcurrentTask Error { events : List Event.Envelope, undecodable : Int }
decryptServerEvents key records =
    records
        |> List.map (decryptServerEventBatch key)
        |> ConcurrentTask.batch
        |> ConcurrentTask.map
            (\results ->
                { events = List.concatMap .events results
                , undecodable = List.sum (List.map .undecodable results)
                }
            )


{-| Decrypt one pulled record (an encrypted batch of envelopes). A record
that fails to decrypt, or an envelope that fails to decode, is counted and
skipped rather than failing the pull — the cursor must keep advancing past
corrupt or malicious records.
-}
decryptServerEventBatch : Symmetric.Key -> ServerEventRecord -> ConcurrentTask Error { events : List Event.Envelope, undecodable : Int }
decryptServerEventBatch key record =
    case Decode.decodeString Symmetric.encryptedDataDecoder record.eventData of
        Ok encrypted ->
            Compression.decryptJson key
                (Decode.list Decode.value)
                { ciphertext = encrypted.ciphertext
                , iv = encrypted.iv
                , compressed = record.compressed
                }
                |> ConcurrentTask.map
                    (\values ->
                        let
                            decoded : List (Result Decode.Error Event.Envelope)
                            decoded =
                                List.map (Decode.decodeValue Event.envelopeDecoder) values

                            events : List Event.Envelope
                            events =
                                List.filterMap Result.toMaybe decoded
                        in
                        { events = events
                        , undecodable = List.length decoded - List.length events
                        }
                    )
                |> ConcurrentTask.onError (\_ -> ConcurrentTask.succeed { events = [], undecodable = 1 })

        Err _ ->
            ConcurrentTask.succeed { events = [], undecodable = 1 }


pullPageDecoder : Decode.Decoder { events : List ServerEventRecord, hasMore : Bool, resetCursor : Bool }
pullPageDecoder =
    Decode.map3 (\events hasMore resetCursor -> { events = events, hasMore = hasMore, resetCursor = resetCursor })
        (Decode.field "events" (Decode.list serverEventRecordDecoder))
        (Decode.field "hasMore" Decode.bool)
        (Decode.oneOf [ Decode.field "resetCursor" Decode.bool, Decode.succeed False ])


serverEventRecordDecoder : Decode.Decoder ServerEventRecord
serverEventRecordDecoder =
    Decode.map3 ServerEventRecord
        (Decode.field "seq" Decode.int)
        (Decode.field "eventData" Decode.string)
        (Decode.field "compressed" Decode.bool)



-- Live updates


{-| Open (or keep open) the live-update WebSocket for a group.
Notifications arrive via the onServerEvent port; the JS side keeps a single
connection per group and reconnects automatically.
-}
subscribeToGroup : ServerContext -> ConcurrentTask Error ()
subscribeToGroup ctx =
    Crypto.deriveRelaySecret ctx.groupKey
        |> ConcurrentTask.mapError CryptoError
        |> ConcurrentTask.andThen
            (\secret ->
                ConcurrentTask.define
                    { function = "relay:subscribe"
                    , expect = ConcurrentTask.expectWhatever
                    , errors = ConcurrentTask.expectNoErrors
                    , args =
                        Encode.object
                            [ ( "url", Encode.string ctx.serverUrl )
                            , ( "groupId", Encode.string ctx.groupId )
                            , ( "secret", Encode.string secret )
                            ]
                    }
            )


{-| Decode a live-update notification from the onServerEvent port.
-}
serverEventDecoder : Decode.Decoder { groupId : String }
serverEventDecoder =
    Decode.map (\gid -> { groupId = gid })
        (Decode.field "groupId" Decode.string)
