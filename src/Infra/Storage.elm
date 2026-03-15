module Infra.Storage exposing
    ( InitData
    , addUnpushedIds
    , deleteGroup
    , errorToString
    , init
    , loadGroup
    , loadGroupEvents
    , loadGroupKey
    , loadGroupKeyRequired
    , loadUsageStats
    , open
    , resetUsageStats
    , saveEvents
    , saveGroup
    , saveGroupKey
    , saveGroupSummary
    , saveIdentity
    , saveLanguage
    , saveNotificationTranslations
    , saveSyncCursor
    , saveUnpushedIds
    , saveUsageStats
    )

import ConcurrentTask exposing (ConcurrentTask)
import Dict exposing (Dict)
import Domain.Event as Event
import Domain.Group as Group
import IndexedDb as Idb
import Infra.Identity as Identity exposing (Identity)
import Infra.UsageStats as UsageStats exposing (UsageStats)
import Json.Decode as Decode
import Json.Encode as Encode
import Set exposing (Set)
import Time
import WebCrypto.Symmetric as Symmetric


{-| Data loaded from IndexedDB during app initialization.
-}
type alias InitData =
    { db : Idb.Db
    , identity : Maybe Identity
    , groups : Dict Group.Id Group.Summary
    , savedLanguage : Maybe String
    }



-- Schema


dbSchema : Idb.Schema
dbSchema =
    Idb.schema "partage" 4
        |> Idb.withStore identityStore
        |> Idb.withStore groupsStore
        |> Idb.withStore groupKeysStore
        |> Idb.withStore eventsStore
        |> Idb.withStore syncCursorsStore
        |> Idb.withStore unpushedIdsStore
        |> Idb.withStore usageStatsStore


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


unpushedIdsStore : Idb.Store Idb.ExplicitKey
unpushedIdsStore =
    Idb.defineStore "unpushedIds"


usageStatsStore : Idb.Store Idb.ExplicitKey
usageStatsStore =
    Idb.defineStore "usageStats"



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
    ConcurrentTask.map3 (InitData db)
        (loadIdentity db)
        (loadAllGroups db)
        (loadLanguage db)


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


{-| Save notification translations for the service worker to use.
Stored in the identity store under the "notificationTranslations" key.
-}
saveNotificationTranslations : Idb.Db -> Encode.Value -> ConcurrentTask Idb.Error ()
saveNotificationTranslations db translations =
    Idb.putAt db identityStore (Idb.StringKey "notificationTranslations") translations


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


{-| Save a list of event envelopes for a group.
-}
saveEvents : Idb.Db -> Group.Id -> List Event.Envelope -> ConcurrentTask Idb.Error ()
saveEvents db groupId envelopes =
    Idb.putMany db eventsStore (List.map (encodeEventForStorage groupId) envelopes)


{-| Load all event envelopes for a group.
-}
loadGroupEvents : Idb.Db -> Group.Id -> ConcurrentTask Idb.Error (List Event.Envelope)
loadGroupEvents db groupId =
    Idb.getByIndex db eventsStore byGroupIdIndex (Idb.only (Idb.StringKey groupId)) Event.envelopeDecoder
        |> ConcurrentTask.map (List.map Tuple.second)


{-| Save a sync cursor for a group.
-}
saveSyncCursor : Idb.Db -> Group.Id -> String -> ConcurrentTask Idb.Error ()
saveSyncCursor db groupId cursor =
    Idb.putAt db syncCursorsStore (Idb.StringKey groupId) (Encode.string cursor)


{-| Load the sync cursor for a group, if it exists.
-}
loadSyncCursor : Idb.Db -> Group.Id -> ConcurrentTask Idb.Error (Maybe String)
loadSyncCursor db groupId =
    Idb.get db syncCursorsStore (Idb.StringKey groupId) Decode.string


{-| Save unpushed event IDs for a group.
-}
saveUnpushedIds : Idb.Db -> Group.Id -> Set String -> ConcurrentTask Idb.Error ()
saveUnpushedIds db groupId ids =
    Idb.putAt db unpushedIdsStore (Idb.StringKey groupId) (Encode.set Encode.string ids)


{-| Load unpushed event IDs for a group.
-}
loadUnpushedIds : Idb.Db -> Group.Id -> ConcurrentTask Idb.Error (Set String)
loadUnpushedIds db groupId =
    Idb.get db unpushedIdsStore (Idb.StringKey groupId) (Decode.list Decode.string)
        |> ConcurrentTask.map (Maybe.map Set.fromList >> Maybe.withDefault Set.empty)


{-| Load all data needed for a group: events, encryption key, sync cursor, and unpushed IDs.
-}
loadGroup : Idb.Db -> Group.Id -> ConcurrentTask Idb.Error { events : List Event.Envelope, groupKey : Symmetric.Key, syncCursor : Maybe String, unpushedIds : Set String }
loadGroup db groupId =
    ConcurrentTask.map4 (\events key cursor unpushed -> { events = events, groupKey = key, syncCursor = cursor, unpushedIds = unpushed })
        (loadGroupEvents db groupId)
        (loadGroupKeyRequired db groupId)
        (loadSyncCursor db groupId)
        (loadUnpushedIds db groupId)


{-| Add event IDs to the unpushed set for a group (read-modify-write).
-}
addUnpushedIds : Idb.Db -> Group.Id -> List String -> ConcurrentTask Idb.Error ()
addUnpushedIds db groupId newIds =
    loadUnpushedIds db groupId
        |> ConcurrentTask.andThen
            (\existing ->
                saveUnpushedIds db groupId (List.foldl Set.insert existing newIds)
            )


{-| Delete a group and all its associated data (summary, key, events, sync cursor, unpushed IDs).
-}
deleteGroup : Idb.Db -> Group.Id -> ConcurrentTask Idb.Error ()
deleteGroup db groupId =
    ConcurrentTask.batch
        -- Delete group summary
        [ Idb.delete db groupsStore (Idb.StringKey groupId)

        -- Delete group key
        , Idb.delete db groupKeysStore (Idb.StringKey groupId)

        -- Delete sync cursor
        , Idb.delete db syncCursorsStore (Idb.StringKey groupId)

        -- Delete unpushed IDs
        , Idb.delete db unpushedIdsStore (Idb.StringKey groupId)

        -- Delete group events
        , Idb.getKeysByIndex db eventsStore byGroupIdIndex (Idb.only (Idb.StringKey groupId))
            |> ConcurrentTask.andThen (\keys -> Idb.deleteMany db eventsStore keys)
        ]
        |> ConcurrentTask.map (\_ -> ())


{-| Save a group summary, events, optional encryption key, and optional sync cursor.
-}
saveGroup : Idb.Db -> Group.Summary -> Maybe String -> List Event.Envelope -> Maybe String -> ConcurrentTask Idb.Error ()
saveGroup db summary maybeKey events maybeCursor =
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
        [ saveGroupSummary db summary |> ConcurrentTask.map (\_ -> ())
        , saveEvents db summary.id events
        , saveKeyTask
        , saveCursorTask
        ]
        |> ConcurrentTask.map (\_ -> ())



-- Usage stats


{-| Load usage statistics, if they exist.
-}
loadUsageStats : Idb.Db -> ConcurrentTask Idb.Error (Maybe UsageStats)
loadUsageStats db =
    Idb.get db usageStatsStore (Idb.StringKey "stats") UsageStats.decoder


{-| Save usage statistics.
-}
saveUsageStats : Idb.Db -> UsageStats -> ConcurrentTask Idb.Error ()
saveUsageStats db stats =
    Idb.putAt db usageStatsStore (Idb.StringKey "stats") (UsageStats.encode stats)


{-| Delete usage statistics (reset).
-}
resetUsageStats : Idb.Db -> ConcurrentTask Idb.Error ()
resetUsageStats db =
    Idb.delete db usageStatsStore (Idb.StringKey "stats")



-- Internal codecs


encodeEventForStorage : Group.Id -> Event.Envelope -> Encode.Value
encodeEventForStorage groupId envelope =
    Encode.object
        [ ( "id", Encode.string envelope.id )
        , ( "groupId", Encode.string groupId )
        , ( "ts", Encode.int (Time.posixToMillis envelope.clientTimestamp) )
        , ( "by", Encode.string envelope.triggeredBy )
        , ( "p", Event.encodePayload envelope.payload )
        ]



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
