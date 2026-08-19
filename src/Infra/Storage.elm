module Infra.Storage exposing
    ( InitData
    , PushState(..)
    , clearActivityMarker
    , deleteExchangeRates
    , deleteGroup
    , deleteNotifyTopic
    , errorToString
    , errorToText
    , exchangeRateKeys
    , init
    , loadActivityMarkers
    , loadAllNotifyTopics
    , loadExchangeRate
    , loadGroup
    , loadGroupEvents
    , loadGroupKey
    , loadNotifyTopic
    , loadUsageStats
    , open
    , resetUsageStats
    , saveDevMode
    , saveEvents
    , saveExchangeRate
    , saveGroup
    , saveGroupSummary
    , saveIdentity
    , saveJoinedGroup
    , saveLanguage
    , saveNotificationTranslations
    , saveNotifyTopic
    , savePushServerUrl
    , saveSelfProfile
    , saveSuspicionDismissals
    , saveSyncCursor
    , saveTamperSignals
    , saveUsageStats
    )

import ConcurrentTask exposing (ConcurrentTask)
import Dict exposing (Dict)
import Domain.Event as Event
import Domain.Group as Group
import Domain.Member as Member
import Domain.TamperSignals as TamperSignals exposing (TamperSignals)
import IndexedDb as Idb
import Infra.Identity as Identity exposing (Identity)
import Infra.UsageStats as UsageStats exposing (UsageStats)
import Json.Decode as Decode
import Json.Encode as Encode
import Set exposing (Set)
import Translations as T exposing (I18n)
import WebCrypto.Symmetric as Symmetric


{-| Data loaded from IndexedDB during app initialization.
-}
type alias InitData =
    { db : Idb.Db
    , identity : Maybe Identity
    , groups : Dict Group.Id Group.Summary
    , savedLanguage : Maybe String
    , selfProfile : Member.Metadata
    , devMode : Bool
    , activityMarkers : Set Group.Id
    , pushServerUrl : Maybe String
    }



-- Schema


dbSchema : Idb.Schema
dbSchema =
    Idb.schema "partage" 11
        |> Idb.withStore identityStore
        |> Idb.withStore groupsStore
        |> Idb.withStore groupKeysStore
        |> Idb.withStore eventsStore
        |> Idb.withStore syncCursorsStore
        |> Idb.withStore usageStatsStore
        |> Idb.withStore exchangeRatesStore
        |> Idb.withStore tamperSignalsStore
        |> Idb.withStore suspicionDismissalsStore
        |> Idb.withStore notifyTopicsStore
        |> Idb.withStore activityMarkersStore


identityStore : Idb.Store Idb.ExplicitKey
identityStore =
    Idb.defineStore "identity"


groupsStore : Idb.Store Idb.InlineKey
groupsStore =
    Idb.defineStore "groups"
        |> Idb.withKeyPath "id"


groupKeysStore : Idb.Store Idb.ExplicitKey
groupKeysStore =
    Idb.defineStore "groupKeys"


eventsStore : Idb.Store Idb.InlineKey
eventsStore =
    Idb.defineStore "events"
        |> Idb.withKeyPath "id"
        |> Idb.withIndex byGroupIdIndex


byGroupIdIndex : Idb.Index
byGroupIdIndex =
    Idb.defineIndex "byGroupId" "groupId"


syncCursorsStore : Idb.Store Idb.ExplicitKey
syncCursorsStore =
    Idb.defineStore "syncCursors"


usageStatsStore : Idb.Store Idb.ExplicitKey
usageStatsStore =
    Idb.defineStore "usageStats"


exchangeRatesStore : Idb.Store Idb.ExplicitKey
exchangeRatesStore =
    Idb.defineStore "exchangeRates"


tamperSignalsStore : Idb.Store Idb.ExplicitKey
tamperSignalsStore =
    Idb.defineStore "tamperSignals"


suspicionDismissalsStore : Idb.Store Idb.ExplicitKey
suspicionDismissalsStore =
    Idb.defineStore "suspicionDismissals"


{-| Blinded push topics, keyed by group id. A record exists exactly while the
group's notifications are subscribed; the value is the topic registered on the
push server, kept so a fresh push subscription can re-register every
subscribed group without loading any group's events.
-}
notifyTopicsStore : Idb.Store Idb.ExplicitKey
notifyTopicsStore =
    Idb.defineStore "notifyTopics"


{-| Unseen push activity, written by the service worker while the app is
closed: one record per notified group, keyed by group id when the worker
could decrypt the payload and by the raw topic otherwise. Never exported and
never synced; read at startup and cleared when the group is opened.
-}
activityMarkersStore : Idb.Store Idb.ExplicitKey
activityMarkersStore =
    Idb.defineStore "activityMarkers"



-- Operations


{-| Open the IndexedDB database, creating stores if needed.
-}
open : ConcurrentTask Idb.Error Idb.Db
open =
    Idb.open dbSchema


{-| Load initial data (identity and all groups) from the database.
-}
init : Idb.Db -> ConcurrentTask Idb.Error InitData
init db =
    ConcurrentTask.succeed (InitData db)
        |> ConcurrentTask.andMap (loadIdentity db)
        |> ConcurrentTask.andMap (loadAllGroups db)
        |> ConcurrentTask.andMap (loadLanguage db)
        |> ConcurrentTask.andMap (loadSelfProfile db |> ConcurrentTask.map (Maybe.withDefault Member.emptyMetadata))
        |> ConcurrentTask.andMap (loadDevMode db)
        |> ConcurrentTask.andMap (loadActivityMarkers db)
        |> ConcurrentTask.andMap (loadPushServerUrl db)


{-| Save the user's identity to the database.
-}
saveIdentity : Idb.Db -> Identity -> ConcurrentTask Idb.Error ()
saveIdentity db identity =
    Idb.putAt db identityStore (Idb.StringKey "default") (Identity.encode identity)


{-| Load the user's identity from the database, if it exists.
-}
loadIdentity : Idb.Db -> ConcurrentTask Idb.Error (Maybe Identity)
loadIdentity db =
    Idb.get db identityStore (Idb.StringKey "default") Identity.decoder


{-| Load the saved language preference, if any.
-}
loadLanguage : Idb.Db -> ConcurrentTask Idb.Error (Maybe String)
loadLanguage db =
    Idb.get db identityStore (Idb.StringKey "language") Decode.string


{-| Save the user's language preference.
-}
saveLanguage : Idb.Db -> String -> ConcurrentTask Idb.Error ()
saveLanguage db lang =
    Idb.putAt db identityStore (Idb.StringKey "language") (Encode.string lang)


{-| Remember the push server the relay last reported. The app starts from it so
the notification surfaces do not appear a round-trip late on every launch, and
stay put when the app starts offline; the next successful fetch overwrites it.
-}
savePushServerUrl : Idb.Db -> Maybe String -> ConcurrentTask Idb.Error ()
savePushServerUrl db url =
    Idb.putAt db
        identityStore
        (Idb.StringKey "pushServerUrl")
        (Encode.string (Maybe.withDefault "" url))


loadPushServerUrl : Idb.Db -> ConcurrentTask Idb.Error (Maybe String)
loadPushServerUrl db =
    Idb.get db identityStore (Idb.StringKey "pushServerUrl") Decode.string
        |> ConcurrentTask.map (Maybe.andThen nonEmpty)


nonEmpty : String -> Maybe String
nonEmpty text =
    if String.isEmpty text then
        Nothing

    else
        Just text


{-| Save the notification bundle (phrase templates and locale number
formatting) for the service worker to assemble notifications from.
Stored in the identity store under the "notificationTranslations" key.
-}
saveNotificationTranslations : Idb.Db -> Encode.Value -> ConcurrentTask Idb.Error ()
saveNotificationTranslations db translations =
    Idb.putAt db identityStore (Idb.StringKey "notificationTranslations") translations


saveNotifyTopic : Idb.Db -> Group.Id -> String -> ConcurrentTask Idb.Error ()
saveNotifyTopic db groupId topic =
    Idb.putAt db notifyTopicsStore (Idb.StringKey groupId) (Encode.string topic)


loadNotifyTopic : Idb.Db -> Group.Id -> ConcurrentTask Idb.Error (Maybe String)
loadNotifyTopic db groupId =
    Idb.get db notifyTopicsStore (Idb.StringKey groupId) Decode.string


deleteNotifyTopic : Idb.Db -> Group.Id -> ConcurrentTask Idb.Error ()
deleteNotifyTopic db groupId =
    Idb.delete db notifyTopicsStore (Idb.StringKey groupId)


{-| Every subscribed group's registered push topic, as (group id, topic).
-}
loadAllNotifyTopics : Idb.Db -> ConcurrentTask Idb.Error (List ( Group.Id, String ))
loadAllNotifyTopics db =
    Idb.getAll db notifyTopicsStore Decode.string
        |> ConcurrentTask.map (List.filterMap (\( key, topic ) -> Maybe.map (\gid -> ( gid, topic )) (stringKey key)))


stringKey : Idb.Key -> Maybe String
stringKey key =
    case key of
        Idb.StringKey str ->
            Just str

        _ ->
            Nothing


{-| Group ids with unseen push activity. A marker written under a raw topic
(the service worker could not decrypt that payload) is resolved through the
notifyTopics store; an unresolvable key is assumed to be a group id.
-}
loadActivityMarkers : Idb.Db -> ConcurrentTask Idb.Error (Set Group.Id)
loadActivityMarkers db =
    ConcurrentTask.map2
        (\markerKeys topics ->
            let
                topicToGroup : Dict String Group.Id
                topicToGroup =
                    topics |> List.map (\( gid, topic ) -> ( topic, gid )) |> Dict.fromList
            in
            markerKeys
                |> List.filterMap stringKey
                |> List.map (\key -> Dict.get key topicToGroup |> Maybe.withDefault key)
                |> Set.fromList
        )
        (Idb.getAllKeys db activityMarkersStore)
        (loadAllNotifyTopics db)


{-| Clear a group's activity marker, under both keys the service worker may
have used. Succeeds with the group's registered topic so outstanding OS
notifications (tagged with it) can be closed too.
-}
clearActivityMarker : Idb.Db -> Group.Id -> ConcurrentTask Idb.Error (Maybe String)
clearActivityMarker db groupId =
    loadNotifyTopic db groupId
        |> ConcurrentTask.andThen
            (\maybeTopic ->
                (Idb.delete db activityMarkersStore (Idb.StringKey groupId)
                    :: (case maybeTopic of
                            Just topic ->
                                [ Idb.delete db activityMarkersStore (Idb.StringKey topic) ]

                            Nothing ->
                                []
                       )
                )
                    |> ConcurrentTask.batch
                    |> ConcurrentTask.map (\_ -> maybeTopic)
            )


{-| Save the user's local self profile (contact info and payment handles
remembered across groups). Stored in the identity store.
-}
saveSelfProfile : Idb.Db -> Member.Metadata -> ConcurrentTask Idb.Error ()
saveSelfProfile db meta =
    Idb.putAt db identityStore (Idb.StringKey "selfProfile") (Member.encodeMetadata meta)


{-| Load the user's local self profile, if any.
-}
loadSelfProfile : Idb.Db -> ConcurrentTask Idb.Error (Maybe Member.Metadata)
loadSelfProfile db =
    Idb.get db identityStore (Idb.StringKey "selfProfile") Member.metadataDecoder


{-| Save the developer-mode preference (gates the diagnostics pages).
-}
saveDevMode : Idb.Db -> Bool -> ConcurrentTask Idb.Error ()
saveDevMode db enabled =
    Idb.putAt db identityStore (Idb.StringKey "devMode") (Encode.bool enabled)


loadDevMode : Idb.Db -> ConcurrentTask Idb.Error Bool
loadDevMode db =
    Idb.get db identityStore (Idb.StringKey "devMode") Decode.bool
        |> ConcurrentTask.map (Maybe.withDefault False)


{-| Save a group summary to the database.
-}
saveGroupSummary : Idb.Db -> Group.Summary -> ConcurrentTask Idb.Error Idb.Key
saveGroupSummary db summary =
    Idb.put db groupsStore (Group.encodeSummary summary)


{-| Load all group summaries from the database as a dictionary keyed by group ID.
-}
loadAllGroups : Idb.Db -> ConcurrentTask Idb.Error (Dict Group.Id Group.Summary)
loadAllGroups db =
    Idb.getAll db groupsStore Group.summaryDecoder
        |> ConcurrentTask.map (List.map (\( _, s ) -> ( s.id, s )) >> Dict.fromList)


{-| Save an encryption key for a group.
-}
saveGroupKey : Idb.Db -> Group.Id -> String -> ConcurrentTask Idb.Error ()
saveGroupKey db groupId key =
    Idb.putAt db groupKeysStore (Idb.StringKey groupId) (Encode.string key)


{-| Load the encryption key for a group, if it exists.
-}
loadGroupKey : Idb.Db -> Group.Id -> ConcurrentTask Idb.Error (Maybe String)
loadGroupKey db groupId =
    Idb.get db groupKeysStore (Idb.StringKey groupId) Decode.string


{-| Load the group encryption key. Fails if the key is missing.
-}
loadGroupKeyRequired : Idb.Db -> Group.Id -> ConcurrentTask Idb.Error Symmetric.Key
loadGroupKeyRequired db groupId =
    loadGroupKey db groupId
        |> ConcurrentTask.andThen
            (\maybeKeyStr ->
                case maybeKeyStr of
                    Just keyStr ->
                        ConcurrentTask.succeed (Symmetric.importKey keyStr)

                    Nothing ->
                        ConcurrentTask.fail (Idb.DatabaseError ("Missing encryption key for group " ++ groupId))
            )


{-| Whether an event still owes the relay a push.

Stored on the event record rather than in a queue of its own, so writing an
event and recording that it needs pushing is one `putMany` — a single
transaction. An event that exists without its queue state is unrepresentable,
and concurrent writers touch disjoint records instead of one shared set.

-}
type PushState
    = Unpushed
    | Pushed


{-| Save a list of event envelopes for a group, all in the given push state.
Also the way to change that state: `putMany` overwrites.
-}
saveEvents : Idb.Db -> Group.Id -> PushState -> List Event.Envelope -> ConcurrentTask Idb.Error ()
saveEvents db groupId pushState envelopes =
    saveEventRecords db groupId (List.map (Tuple.pair pushState) envelopes)


saveEventRecords : Idb.Db -> Group.Id -> List ( PushState, Event.Envelope ) -> ConcurrentTask Idb.Error ()
saveEventRecords db groupId records =
    Idb.putMany db
        eventsStore
        (List.map (\( pushState, envelope ) -> encodeEventForStorage groupId pushState envelope) records)


{-| Load all event envelopes for a group.
-}
loadGroupEvents : Idb.Db -> Group.Id -> ConcurrentTask Idb.Error (List Event.Envelope)
loadGroupEvents db groupId =
    loadStoredEvents db groupId |> ConcurrentTask.map (List.map .envelope)


loadStoredEvents : Idb.Db -> Group.Id -> ConcurrentTask Idb.Error (List { envelope : Event.Envelope, pushState : PushState })
loadStoredEvents db groupId =
    Idb.getByIndex db eventsStore byGroupIdIndex (Idb.only (Idb.StringKey groupId)) storedEventDecoder
        |> ConcurrentTask.map (List.map Tuple.second)


{-| Save a sync cursor for a group. Seq and epoch are one record: a seq is
only meaningful within the group incarnation it was issued under.
-}
saveSyncCursor : Idb.Db -> Group.Id -> Group.SyncCursor -> ConcurrentTask Idb.Error ()
saveSyncCursor db groupId cursor =
    Idb.putAt db
        syncCursorsStore
        (Idb.StringKey groupId)
        (Encode.object [ ( "seq", Encode.int cursor.seq ), ( "epoch", Encode.string cursor.epoch ) ])


{-| Load the sync cursor for a group, if it exists.
Cursors written by earlier schema generations (bare relay ints, PocketBase
timestamp strings) carry no epoch and read back as "never synced".
-}
loadSyncCursor : Idb.Db -> Group.Id -> ConcurrentTask Idb.Error (Maybe Group.SyncCursor)
loadSyncCursor db groupId =
    Idb.get db
        syncCursorsStore
        (Idb.StringKey groupId)
        (Decode.oneOf
            [ Decode.map Just
                (Decode.map2 Group.SyncCursor
                    (Decode.field "seq" Decode.int)
                    (Decode.field "epoch" Decode.string)
                )
            , Decode.succeed Nothing
            ]
        )
        |> ConcurrentTask.map (Maybe.andThen identity)


{-| Save a group's tamper-signal counters.
-}
saveTamperSignals : Idb.Db -> Group.Id -> TamperSignals -> ConcurrentTask Idb.Error ()
saveTamperSignals db groupId signals =
    Idb.putAt db tamperSignalsStore (Idb.StringKey groupId) (TamperSignals.encode signals)


{-| Load a group's tamper-signal counters, defaulting to none.
-}
loadTamperSignals : Idb.Db -> Group.Id -> ConcurrentTask Idb.Error TamperSignals
loadTamperSignals db groupId =
    Idb.get db tamperSignalsStore (Idb.StringKey groupId) TamperSignals.decoder
        |> ConcurrentTask.map (Maybe.withDefault TamperSignals.empty)


{-| Save the locally-dismissed suspicion-finding keys for a group.
Kept per-device and never synced, so acting on a flag leaks no signal.
-}
saveSuspicionDismissals : Idb.Db -> Group.Id -> Set String -> ConcurrentTask Idb.Error ()
saveSuspicionDismissals db groupId keys =
    Idb.putAt db suspicionDismissalsStore (Idb.StringKey groupId) (Encode.set Encode.string keys)


loadSuspicionDismissals : Idb.Db -> Group.Id -> ConcurrentTask Idb.Error (Set String)
loadSuspicionDismissals db groupId =
    Idb.get db suspicionDismissalsStore (Idb.StringKey groupId) (Decode.list Decode.string)
        |> ConcurrentTask.map (Maybe.map Set.fromList >> Maybe.withDefault Set.empty)


{-| Load all data needed for a group: events, encryption key, sync cursor,
unpushed IDs, and tamper-signal counters.
-}
loadGroup : Idb.Db -> Group.Id -> ConcurrentTask Idb.Error { events : List Event.Envelope, groupKey : Symmetric.Key, syncCursor : Maybe Group.SyncCursor, unpushedIds : Set String, tamperSignals : TamperSignals, suspicionDismissals : Set String }
loadGroup db groupId =
    ConcurrentTask.map4
        (\stored key cursor ( signals, dismissals ) ->
            { events = List.map .envelope stored
            , groupKey = key
            , syncCursor = cursor
            , unpushedIds =
                List.filterMap
                    (\e ->
                        if e.pushState == Unpushed then
                            Just e.envelope.id

                        else
                            Nothing
                    )
                    stored
                    |> Set.fromList
            , tamperSignals = signals
            , suspicionDismissals = dismissals
            }
        )
        (loadStoredEvents db groupId)
        (loadGroupKeyRequired db groupId)
        (loadSyncCursor db groupId)
        (ConcurrentTask.map2 Tuple.pair (loadTamperSignals db groupId) (loadSuspicionDismissals db groupId))


{-| Delete a group and all its associated data (summary, key, events, sync cursor).

The summary is what lists a group and makes it openable, so it goes first: an
interrupted delete then leaves unreferenced rows rather than a group the user
can still see but that no longer has the key to open it.

-}
deleteGroup : Idb.Db -> Group.Id -> ConcurrentTask Idb.Error ()
deleteGroup db groupId =
    Idb.delete db groupsStore (Idb.StringKey groupId)
        |> ConcurrentTask.andThen
            (\_ ->
                ConcurrentTask.batch
                    [ Idb.delete db groupKeysStore (Idb.StringKey groupId)
                    , Idb.delete db syncCursorsStore (Idb.StringKey groupId)
                    , Idb.delete db tamperSignalsStore (Idb.StringKey groupId)
                    , Idb.delete db suspicionDismissalsStore (Idb.StringKey groupId)
                    , Idb.delete db notifyTopicsStore (Idb.StringKey groupId)
                    , Idb.delete db activityMarkersStore (Idb.StringKey groupId)
                    , Idb.getKeysByIndex db eventsStore byGroupIdIndex (Idb.only (Idb.StringKey groupId))
                        |> ConcurrentTask.andThen (\keys -> Idb.deleteMany db eventsStore keys)
                    ]
            )
        |> ConcurrentTask.map (\_ -> ())


{-| Save a group summary, events, optional encryption key, and optional sync cursor.

The summary lands last. It is what makes a group visible and openable, while
the key and events are what make it work — writing it first would let an
interrupted save leave a group the user can see but that fails to open, since
loading one requires its key. Landing it last leaves invisible orphan rows
instead.

-}
saveGroup : Idb.Db -> Group.Summary -> Maybe String -> PushState -> List Event.Envelope -> Maybe Group.SyncCursor -> ConcurrentTask Idb.Error ()
saveGroup db summary maybeKey pushState events maybeCursor =
    let
        saveKeyTask : ConcurrentTask Idb.Error ()
        saveKeyTask =
            case maybeKey of
                Just key ->
                    saveGroupKey db summary.id key

                Nothing ->
                    ConcurrentTask.succeed ()

        saveCursorTask : ConcurrentTask Idb.Error ()
        saveCursorTask =
            case maybeCursor of
                Just cursor ->
                    saveSyncCursor db summary.id cursor

                Nothing ->
                    ConcurrentTask.succeed ()
    in
    ConcurrentTask.batch
        [ saveEvents db summary.id pushState events
        , saveKeyTask
        , saveCursorTask
        ]
        |> ConcurrentTask.andThen (\_ -> saveGroupSummary db summary)
        |> ConcurrentTask.map (\_ -> ())


{-| Save accepted history and its local membership event in one events-store
transaction. The final summary lands only after the group key and cursor, while
existing local events retain whether they still owe the relay a push.
-}
saveJoinedGroup : Idb.Db -> Group.Summary -> String -> List Event.Envelope -> Set Event.Id -> Event.Envelope -> Maybe Group.SyncCursor -> ConcurrentTask Idb.Error ()
saveJoinedGroup db summary groupKey events unpushedIds membershipEvent maybeCursor =
    let
        importedRecords : List ( PushState, Event.Envelope )
        importedRecords =
            List.map
                (\envelope ->
                    ( if Set.member envelope.id unpushedIds then
                        Unpushed

                      else
                        Pushed
                    , envelope
                    )
                )
                events

        saveCursorTask : ConcurrentTask Idb.Error ()
        saveCursorTask =
            case maybeCursor of
                Just cursor ->
                    saveSyncCursor db summary.id cursor

                Nothing ->
                    ConcurrentTask.succeed ()
    in
    ConcurrentTask.batch
        [ saveEventRecords db summary.id (importedRecords ++ [ ( Unpushed, membershipEvent ) ])
        , saveGroupKey db summary.id groupKey
        , saveCursorTask
        ]
        |> ConcurrentTask.andThen (\_ -> saveGroupSummary db summary)
        |> ConcurrentTask.map (\_ -> ())



-- Usage stats


{-| Load usage statistics, if they exist. The bytes-transferred counter lives in
its own "transfer" record, written only by the JS byte-counter; it is merged
into the Elm-owned "stats" record here so neither writer clobbers the other.
-}
loadUsageStats : Idb.Db -> ConcurrentTask Idb.Error (Maybe UsageStats)
loadUsageStats db =
    ConcurrentTask.map2
        (\maybeStats transferred ->
            Maybe.map (\stats -> { stats | totalBytesTransferred = transferred }) maybeStats
        )
        (Idb.get db usageStatsStore (Idb.StringKey "stats") UsageStats.decoder)
        (Idb.get db usageStatsStore (Idb.StringKey "transfer") Decode.int
            |> ConcurrentTask.map (Maybe.withDefault 0)
        )


{-| Save usage statistics. The bytes-transferred counter is not written; it is
owned by the JS byte-counter's "transfer" record.
-}
saveUsageStats : Idb.Db -> UsageStats -> ConcurrentTask Idb.Error ()
saveUsageStats db stats =
    Idb.putAt db usageStatsStore (Idb.StringKey "stats") (UsageStats.encode stats)


{-| Delete usage statistics (reset), including the JS-owned byte counter.
-}
resetUsageStats : Idb.Db -> ConcurrentTask Idb.Error ()
resetUsageStats db =
    Idb.delete db usageStatsStore (Idb.StringKey "stats")
        |> ConcurrentTask.andThenDo (Idb.delete db usageStatsStore (Idb.StringKey "transfer"))



-- Exchange rates


{-| Cache a fetched exchange rate under the given key (e.g. "USD-EUR-2026-05-28").
-}
saveExchangeRate : Idb.Db -> String -> Float -> ConcurrentTask Idb.Error ()
saveExchangeRate db key rate =
    Idb.putAt db exchangeRatesStore (Idb.StringKey key) (Encode.float rate)


{-| Load a cached exchange rate by key, if present.
-}
loadExchangeRate : Idb.Db -> String -> ConcurrentTask Idb.Error (Maybe Float)
loadExchangeRate db key =
    Idb.get db exchangeRatesStore (Idb.StringKey key) Decode.float


{-| List all cached exchange-rate keys (used to sweep stale entries).
-}
exchangeRateKeys : Idb.Db -> ConcurrentTask Idb.Error (List String)
exchangeRateKeys db =
    Idb.getAllKeys db exchangeRatesStore
        |> ConcurrentTask.map
            (List.filterMap
                (\k ->
                    case k of
                        Idb.StringKey s ->
                            Just s

                        _ ->
                            Nothing
                )
            )


{-| Delete the given cached exchange-rate keys.
-}
deleteExchangeRates : Idb.Db -> List String -> ConcurrentTask Idb.Error ()
deleteExchangeRates db keys =
    Idb.deleteMany db exchangeRatesStore (List.map Idb.StringKey keys)



-- Internal codecs


encodeEventForStorage : Group.Id -> PushState -> Event.Envelope -> Encode.Value
encodeEventForStorage groupId pushState envelope =
    Encode.object
        [ ( "id", Encode.string envelope.id )
        , ( "groupId", Encode.string groupId )
        , ( "env", Event.encodeEnvelope envelope )
        , ( "unpushed", Encode.bool (pushState == Unpushed) )
        ]


storedEventDecoder : Decode.Decoder { envelope : Event.Envelope, pushState : PushState }
storedEventDecoder =
    Decode.map2 (\envelope pushState -> { envelope = envelope, pushState = pushState })
        (Decode.field "env" Event.envelopeDecoder)
        (Decode.oneOf
            [ Decode.field "unpushed" Decode.bool
                |> Decode.map
                    (\unpushed ->
                        if unpushed then
                            Unpushed

                        else
                            Pushed
                    )
            , Decode.succeed Pushed
            ]
        )



-- Helper functions


{-| Convert an IndexedDB error to a human-readable string.
-}
errorToString : Idb.Error -> String
errorToString err =
    case err of
        Idb.AlreadyExists ->
            "Record already exists"

        Idb.TransactionError errMsg ->
            "Transaction error: " ++ errMsg

        Idb.QuotaExceeded ->
            "Storage quota exceeded"

        Idb.DatabaseError errMsg ->
            "Database error: " ++ errMsg


{-| Localized, user-facing rendering of a storage error. `errorToString` stays
for the error log, where a stable English string is worth grepping for.
-}
errorToText : I18n -> Idb.Error -> String
errorToText i18n err =
    case err of
        Idb.AlreadyExists ->
            T.errorStorageExists i18n

        Idb.TransactionError _ ->
            T.errorStorageDatabase i18n

        Idb.QuotaExceeded ->
            T.errorStorageQuota i18n

        Idb.DatabaseError _ ->
            T.errorStorageDatabase i18n
