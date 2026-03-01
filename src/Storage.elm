module Storage exposing
    ( GroupSummary
    , InitData
    , deleteGroup
    , errorToString
    , init
    , loadAllGroups
    , loadGroupEvents
    , loadGroupKey
    , loadIdentity
    , open
    , saveEvents
    , saveGroupKey
    , saveGroupSummary
    , saveIdentity
    )

import ConcurrentTask exposing (ConcurrentTask)
import Dict exposing (Dict)
import Domain.Currency as Currency exposing (Currency)
import Domain.Event as Event
import Domain.Group as Group
import Identity exposing (Identity)
import IndexedDb as Idb
import Json.Decode as Decode
import Json.Encode as Encode
import Time


{-| Data loaded from IndexedDB during app initialization.
-}
type alias InitData =
    { db : Idb.Db
    , identity : Maybe Identity
    , groups : Dict Group.Id GroupSummary
    }


{-| Summary of a group for the home page list.
-}
type alias GroupSummary =
    { id : Group.Id
    , name : String
    , defaultCurrency : Currency
    }



-- Schema


dbSchema : Idb.Schema
dbSchema =
    Idb.schema "partage" 1
        |> Idb.withStore identityStore
        |> Idb.withStore groupsStore
        |> Idb.withStore groupKeysStore
        |> Idb.withStore eventsStore


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



-- Operations


open : ConcurrentTask Idb.Error Idb.Db
open =
    Idb.open dbSchema


init : Idb.Db -> ConcurrentTask Idb.Error InitData
init db =
    ConcurrentTask.map2 (InitData db)
        (loadIdentity db)
        (loadAllGroups db)


saveIdentity : Idb.Db -> Identity -> ConcurrentTask Idb.Error ()
saveIdentity db identity =
    Idb.putAt db identityStore (Idb.StringKey "default") (Identity.encode identity)


loadIdentity : Idb.Db -> ConcurrentTask Idb.Error (Maybe Identity)
loadIdentity db =
    Idb.get db identityStore (Idb.StringKey "default") Identity.decoder


saveGroupSummary : Idb.Db -> GroupSummary -> ConcurrentTask Idb.Error Idb.Key
saveGroupSummary db summary =
    Idb.put db groupsStore (encodeGroupSummary summary)


loadAllGroups : Idb.Db -> ConcurrentTask Idb.Error (Dict Group.Id GroupSummary)
loadAllGroups db =
    Idb.getAll db groupsStore groupSummaryDecoder
        |> ConcurrentTask.map (List.map (\( _, s ) -> ( s.id, s )) >> Dict.fromList)


saveGroupKey : Idb.Db -> Group.Id -> String -> ConcurrentTask Idb.Error ()
saveGroupKey db groupId key =
    Idb.putAt db groupKeysStore (Idb.StringKey groupId) (Encode.string key)


loadGroupKey : Idb.Db -> Group.Id -> ConcurrentTask Idb.Error (Maybe String)
loadGroupKey db groupId =
    Idb.get db groupKeysStore (Idb.StringKey groupId) Decode.string


saveEvents : Idb.Db -> Group.Id -> List Event.Envelope -> ConcurrentTask Idb.Error ()
saveEvents db groupId envelopes =
    Idb.putMany db eventsStore (List.map (encodeEventForStorage groupId) envelopes)


loadGroupEvents : Idb.Db -> Group.Id -> ConcurrentTask Idb.Error (List Event.Envelope)
loadGroupEvents db groupId =
    Idb.getByIndex db eventsStore byGroupIdIndex (Idb.only (Idb.StringKey groupId)) Event.envelopeDecoder
        |> ConcurrentTask.map (List.map Tuple.second)


deleteGroup : Idb.Db -> Group.Id -> ConcurrentTask Idb.Error ()
deleteGroup db groupId =
    ConcurrentTask.batch
        -- Delete group summary
        [ Idb.delete db groupsStore (Idb.StringKey groupId)

        -- Delete group key
        , Idb.delete db groupKeysStore (Idb.StringKey groupId)

        -- Delete group events
        , Idb.getKeysByIndex db eventsStore byGroupIdIndex (Idb.only (Idb.StringKey groupId))
            |> ConcurrentTask.andThen (\keys -> Idb.deleteMany db eventsStore keys)
        ]
        |> ConcurrentTask.map (\_ -> ())



-- Internal codecs


encodeGroupSummary : GroupSummary -> Encode.Value
encodeGroupSummary summary =
    Encode.object
        [ ( "id", Encode.string summary.id )
        , ( "name", Encode.string summary.name )
        , ( "defaultCurrency", Currency.encodeCurrency summary.defaultCurrency )
        ]


groupSummaryDecoder : Decode.Decoder GroupSummary
groupSummaryDecoder =
    Decode.map3 GroupSummary
        (Decode.field "id" Decode.string)
        (Decode.field "name" Decode.string)
        (Decode.field "defaultCurrency" Currency.currencyDecoder)


encodeEventForStorage : Group.Id -> Event.Envelope -> Encode.Value
encodeEventForStorage groupId envelope =
    Encode.object
        [ ( "id", Encode.string envelope.id )
        , ( "groupId", Encode.string groupId )
        , ( "clientTimestamp", Encode.int (Time.posixToMillis envelope.clientTimestamp) )
        , ( "triggeredBy", Encode.string envelope.triggeredBy )
        , ( "payload", Event.encodePayload envelope.payload )
        ]



-- Helper functions


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
