module Infra.Server exposing
    ( CompactOutcome(..)
    , Error(..)
    , PullResult
    , ServerContext
    , SyncData
    , SyncResult
    , compact
    , createGroupOnServer
    , errorToString
    , fetchEventOrder
    , isNetworkError
    , isNotFound
    , isQuotaExceeded
    , isRateLimited
    , isUnauthorized
    , serverEventDecoder
    , subscribeToGroup
    , sync
    , unsubscribeFromGroup
    )

{-| Relay server sync module.

Handles encrypted event push/pull and live-update subscriptions against the
Partage relay (see packages/relay). There is no session: every request
carries a bearer secret derived from the group key.

-}

import ConcurrentTask exposing (ConcurrentTask)
import ConcurrentTask.Http as Http
import Dict exposing (Dict)
import Domain.Compaction as Compaction
import Domain.Event as Event
import Domain.Group as Group
import Infra.Compression as Compression
import Infra.Crypto as Crypto
import Infra.PushServer as PushServer
import Json.Decode as Decode
import Json.Encode as Encode
import Set exposing (Set)
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
                    case meta.statusCode of
                        507 ->
                            "Group storage limit reached (507)"

                        429 ->
                            "Data rate limit exceeded (429)"

                        code ->
                            "Server error (" ++ String.fromInt code ++ ")"

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


{-| True when the group is full: its append exceeded the relay's storage quota
(§14.8). Surfaced so the user can compact or export instead of retrying.
-}
isQuotaExceeded : Error -> Bool
isQuotaExceeded =
    isStatus 507


{-| True when the group's recent append volume exceeded the relay's monthly
rate limit (§14.8). Transient — syncing resumes once the window rolls.
-}
isRateLimited : Error -> Bool
isRateLimited =
    isStatus 429


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
    , syncCursor : Maybe Group.SyncCursor
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
sync ctx actorId { unpushedEvents, syncCursor, notifyContext } =
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
                            (pullEvents ctx secret syncCursor)
                        )
            )



-- Event pull


{-| Pull result with decrypted events and the new sync cursor.
`undecodable` counts skipped items: records that failed to decrypt plus
envelopes whose JSON shape could not be decoded. Skipping instead of
failing keeps one bad record from bricking the group's sync forever.
`didReset` is set when the pull restarted from 0 — on a `resetCursor`, or on
an epoch change (the relay's group row was purged and re-created, so the seq
cursor belongs to a dead incarnation) — the relay lost events this client has
seen, so the caller re-pushes the gap. `epoch` is the incarnation the pull was
served under; the caller stores it beside the new cursor.
`recordCount` is the relay's total record count for the group, the
compaction-trigger signal (spec §14.9). `forgedAuthors` lists the claimed
author id of every envelope the caller's signature verification later dropped
(spec §11.7); the pull itself never fills it, so it starts empty.
-}
type alias PullResult =
    { events : List Event.Envelope
    , cursor : Int
    , epoch : String
    , undecodable : Int
    , didReset : Bool
    , recordCount : Int
    , forgedAuthors : List String
    }


{-| Pull events from the server since the given cursor. Decrypts each event.

The pull restarts from 0 when the server signals `resetCursor` (it no longer
holds events up to our cursor — same-incarnation truncation) or when the
served epoch differs from the stored one (the group row was purged and
re-created; fresh appends can sit above a stale cursor, so only the epoch
reveals the loss). At most one restart per sync so a misbehaving server
cannot loop us forever. The caller's dedup-by-event-id merge makes the
restart loss-free.

-}
pullEvents : ServerContext -> String -> Maybe Group.SyncCursor -> ConcurrentTask Error PullResult
pullEvents ctx secret maybeSync =
    pullAllPages ctx
        secret
        { allowReset = True, storedEpoch = Maybe.map .epoch maybeSync }
        (maybeSync |> Maybe.map .seq |> Maybe.withDefault 0)
        { events = [], undecodable = 0, didReset = False }


{-| `allowReset` is cleared after one restart; `storedEpoch` is `Nothing` when
this device never synced, in which case only the server's `resetCursor` can
trigger a restart.
-}
pullAllPages : ServerContext -> String -> { allowReset : Bool, storedEpoch : Maybe String } -> Int -> { events : List Event.Envelope, undecodable : Int, didReset : Bool } -> ConcurrentTask Error PullResult
pullAllPages ctx secret resetCheck cursor acc =
    Http.get
        { url = eventsUrl ctx ++ "?since=" ++ String.fromInt cursor
        , headers = [ authHeader secret ]
        , expect = Http.expectJson pullPageDecoder
        , timeout = Nothing
        }
        |> ConcurrentTask.mapError HttpError
        |> ConcurrentTask.andThen
            (\page ->
                let
                    epochChanged : Bool
                    epochChanged =
                        resetCheck.storedEpoch
                            |> Maybe.map ((/=) page.groupEpoch)
                            |> Maybe.withDefault False
                in
                if resetCheck.allowReset && (page.resetCursor || epochChanged) then
                    pullAllPages ctx secret { resetCheck | allowReset = False } 0 { acc | didReset = True }

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
                                    pullAllPages ctx secret resetCheck newCursor newAcc

                                else
                                    ConcurrentTask.succeed
                                        { events = newAcc.events
                                        , cursor = newCursor
                                        , epoch = page.groupEpoch
                                        , undecodable = newAcc.undecodable
                                        , didReset = newAcc.didReset
                                        , recordCount = page.recordCount
                                        , forgedAuthors = []
                                        }
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


pullPageDecoder : Decode.Decoder { events : List ServerEventRecord, hasMore : Bool, resetCursor : Bool, recordCount : Int, groupEpoch : String }
pullPageDecoder =
    Decode.map5 (\events hasMore resetCursor recordCount groupEpoch -> { events = events, hasMore = hasMore, resetCursor = resetCursor, recordCount = recordCount, groupEpoch = groupEpoch })
        (Decode.field "events" (Decode.list serverEventRecordDecoder))
        (Decode.field "hasMore" Decode.bool)
        (Decode.oneOf [ Decode.field "resetCursor" Decode.bool, Decode.succeed False ])
        (Decode.oneOf [ Decode.field "recordCount" Decode.int, Decode.succeed 0 ])
        (Decode.field "groupEpoch" Decode.string)


serverEventRecordDecoder : Decode.Decoder ServerEventRecord
serverEventRecordDecoder =
    Decode.map3 ServerEventRecord
        (Decode.field "seq" Decode.int)
        (Decode.field "eventData" Decode.string)
        (Decode.field "compressed" Decode.bool)



-- Compaction


{-| Result of a compact call: the relay's new max seq (the executor may
fast-forward its cursor to it — the appended records hold exactly what it
sent), or a lost race (the relay's history moved; reconsidered next sync).
-}
type CompactOutcome
    = Compacted Int
    | CompactRaced


{-| The plaintext-bytes bound per consolidation batch. Guarantees the
encrypted record stays under the relay's 1 MB cap even for incompressible
content (base64 expands by a third).
-}
maxChunkBytes : Int
maxChunkBytes =
    512 * 1024


{-| Execute a quorumed compaction (spec §14.9): re-pull the full record
list to learn `uptoSeq` and what rides beyond the manifest boundary, then
atomically replace everything with the consolidated history — the sorted
manifested prefix re-packed into large batches, plus every pulled event
outside the manifest as riders, so no deleted record loses an event.
Undecodable records cannot contribute events and are dropped with the
compaction.
-}
compact : ServerContext -> String -> List Event.Envelope -> ConcurrentTask Error CompactOutcome
compact ctx actorId prefix =
    let
        manifestIds : Set String
        manifestIds =
            Set.fromList (List.map .id prefix)
    in
    Crypto.deriveRelaySecret ctx.groupKey
        |> ConcurrentTask.mapError CryptoError
        |> ConcurrentTask.andThen
            (\secret ->
                pullTaggedRecords ctx secret 0 []
                    |> ConcurrentTask.andThen
                        (\records ->
                            case List.maximum (List.map .seq records) of
                                Nothing ->
                                    ConcurrentTask.succeed CompactRaced

                                Just uptoSeq ->
                                    let
                                        riders : List Event.Envelope
                                        riders =
                                            records
                                                |> List.concatMap .events
                                                |> List.filter (\e -> not (Set.member e.id manifestIds))
                                                |> dedupById
                                                |> Event.sortEvents
                                    in
                                    (Compaction.chunkEnvelopes maxChunkBytes prefix ++ Compaction.chunkEnvelopes maxChunkBytes riders)
                                        |> List.map (packRecord ctx.groupKey actorId)
                                        |> ConcurrentTask.batch
                                        |> ConcurrentTask.andThen
                                            (postCompact ctx secret { uptoSeq = uptoSeq, expectedCount = List.length records })
                        )
            )


{-| Pull the group's full history and pair each event id with the server `seq`
of the batch it arrived in — the relay's ingestion order, which (unlike the
payload timestamp) an event's author cannot forge. Migration curation uses it to
bound an excluded identity's history to what it authored before a given batch. A
duplicated id keeps its earliest seq. Decrypts every record, so it is only worth
calling for a rare operation like migration.
-}
fetchEventOrder : ServerContext -> ConcurrentTask Error (Dict Event.Id Int)
fetchEventOrder ctx =
    Crypto.deriveRelaySecret ctx.groupKey
        |> ConcurrentTask.mapError CryptoError
        |> ConcurrentTask.andThen (\secret -> pullTaggedRecords ctx secret 0 [])
        |> ConcurrentTask.map
            (List.foldl
                (\record acc ->
                    List.foldl
                        (\envelope -> Dict.update envelope.id (\existing -> Just (min record.seq (Maybe.withDefault record.seq existing))))
                        acc
                        record.events
                )
                Dict.empty
            )


{-| One pull page at a time, keeping each record's seq with its decrypted
events. Runs from 0 so no reset handling applies.
-}
pullTaggedRecords : ServerContext -> String -> Int -> List { seq : Int, events : List Event.Envelope } -> ConcurrentTask Error (List { seq : Int, events : List Event.Envelope })
pullTaggedRecords ctx secret cursor acc =
    Http.get
        { url = eventsUrl ctx ++ "?since=" ++ String.fromInt cursor
        , headers = [ authHeader secret ]
        , expect = Http.expectJson pullPageDecoder
        , timeout = Nothing
        }
        |> ConcurrentTask.mapError HttpError
        |> ConcurrentTask.andThen
            (\page ->
                page.events
                    |> List.map
                        (\record ->
                            decryptServerEventBatch ctx.groupKey record
                                |> ConcurrentTask.map (\decrypted -> { seq = record.seq, events = decrypted.events })
                        )
                    |> ConcurrentTask.batch
                    |> ConcurrentTask.andThen
                        (\decrypted ->
                            let
                                newAcc : List { seq : Int, events : List Event.Envelope }
                                newAcc =
                                    acc ++ decrypted
                            in
                            if page.hasMore then
                                let
                                    newCursor : Int
                                    newCursor =
                                        List.head (List.reverse page.events)
                                            |> Maybe.map .seq
                                            |> Maybe.withDefault cursor
                                in
                                pullTaggedRecords ctx secret newCursor newAcc

                            else
                                ConcurrentTask.succeed newAcc
                        )
            )


dedupById : List Event.Envelope -> List Event.Envelope
dedupById envelopes =
    List.foldl
        (\envelope ( seen, kept ) ->
            if Set.member envelope.id seen then
                ( seen, kept )

            else
                ( Set.insert envelope.id seen, envelope :: kept )
        )
        ( Set.empty, [] )
        envelopes
        |> Tuple.second
        |> List.reverse


{-| Encrypt one consolidation batch, with the same content-derived
recordId as regular pushes so retries and racing executors dedup.
-}
packRecord : Symmetric.Key -> String -> List Event.Envelope -> ConcurrentTask Error Encode.Value
packRecord groupKey actorId envelopes =
    ConcurrentTask.map2
        (\recordId result ->
            Encode.object
                [ ( "actorId", Encode.string actorId )
                , ( "recordId", Encode.string recordId )
                , ( "eventData", Encode.string (Encode.encode 0 (Compression.encodeEventData result)) )
                , ( "compressed", Encode.bool result.compressed )
                ]
        )
        (WebCrypto.sha256 (String.join "\n" (List.sort (List.map .id envelopes))))
        (Compression.encryptJson groupKey (Encode.list Event.encodeEnvelope envelopes))
        |> ConcurrentTask.mapError CryptoError


{-| `expectedCount` is how many records the executor's snapshot held at or
below `uptoSeq` — the relay refuses the compact when the range no longer
holds exactly that many, so a stale snapshot can never blindly rewrite a
history someone else just consolidated.
-}
postCompact : ServerContext -> String -> { uptoSeq : Int, expectedCount : Int } -> List Encode.Value -> ConcurrentTask Error CompactOutcome
postCompact ctx secret { uptoSeq, expectedCount } records =
    Http.post
        { url = ctx.serverUrl ++ "/api/groups/" ++ ctx.groupId ++ "/compact"
        , headers = [ authHeader secret ]
        , body =
            Http.jsonBody
                (Encode.object
                    [ ( "uptoSeq", Encode.int uptoSeq )
                    , ( "expectedCount", Encode.int expectedCount )
                    , ( "records", Encode.list identity records )
                    ]
                )
        , expect = Http.expectJson (Decode.field "maxSeq" Decode.int)
        , timeout = Nothing
        }
        |> ConcurrentTask.mapError HttpError
        |> ConcurrentTask.map Compacted
        |> ConcurrentTask.onError
            (\err ->
                if isStatus 409 err then
                    ConcurrentTask.succeed CompactRaced

                else
                    ConcurrentTask.fail err
            )



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


{-| Close the live-update WebSocket for a group, if one is open, and stop
reconnecting. Archived groups must produce no network activity.
-}
unsubscribeFromGroup : String -> ConcurrentTask x ()
unsubscribeFromGroup groupId =
    ConcurrentTask.define
        { function = "relay:unsubscribe"
        , expect = ConcurrentTask.expectWhatever
        , errors = ConcurrentTask.expectNoErrors
        , args = Encode.object [ ( "groupId", Encode.string groupId ) ]
        }


{-| Decode a live-update notification from the onServerEvent port.
-}
serverEventDecoder : Decode.Decoder { groupId : String }
serverEventDecoder =
    Decode.map (\gid -> { groupId = gid })
        (Decode.field "groupId" Decode.string)
