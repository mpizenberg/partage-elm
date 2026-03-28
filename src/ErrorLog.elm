module ErrorLog exposing (Entry, Model, Severity(..), Source(..), empty, log, sourceToString, toJsonValue)

{-| In-memory error log for debugging.

Stores error entries newest-first, capped at ~1000 entries.
Consecutive duplicate entries are deduplicated with a count.

-}

import Json.Encode as Encode
import Time


type alias Entry =
    { timestamp : Time.Posix
    , source : Source
    , severity : Severity
    , message : String
    , count : Int
    }


type Source
    = SyncSource
    | StorageSource
    | ServerSource
    | PushSource
    | PwaSource
    | ImportExportSource
    | IdentitySource


type Severity
    = Err


type alias Model =
    { entries : List Entry
    , size : Int
    }


empty : Model
empty =
    { entries = [], size = 0 }


{-| Log a new error entry with deduplication and trimming.

If the new entry matches the head (same source, severity, message),
increment the count and update the timestamp instead of prepending.
Trim only when size exceeds 1100, dropping back to 1000.

-}
log : Time.Posix -> Source -> Severity -> String -> Model -> Model
log timestamp source severity message model =
    case model.entries of
        head :: rest ->
            if head.source == source && head.severity == severity && head.message == message then
                { model
                    | entries = { head | timestamp = timestamp, count = head.count + 1 } :: rest
                }

            else
                let
                    newSize : Int
                    newSize =
                        model.size + 1

                    newEntries : List Entry
                    newEntries =
                        { timestamp = timestamp, source = source, severity = severity, message = message, count = 1 }
                            :: model.entries
                in
                if newSize > 1100 then
                    { entries = List.take 1000 newEntries, size = 1000 }

                else
                    { entries = newEntries, size = newSize }

        [] ->
            { entries = [ { timestamp = timestamp, source = source, severity = severity, message = message, count = 1 } ]
            , size = 1
            }


sourceToString : Source -> String
sourceToString source =
    case source of
        SyncSource ->
            "sync"

        StorageSource ->
            "storage"

        ServerSource ->
            "server"

        PushSource ->
            "push"

        PwaSource ->
            "pwa"

        ImportExportSource ->
            "import-export"

        IdentitySource ->
            "identity"


severityToString : Severity -> String
severityToString severity =
    case severity of
        Err ->
            "error"


toJsonValue : Model -> Encode.Value
toJsonValue model =
    Encode.list encodeEntry model.entries


encodeEntry : Entry -> Encode.Value
encodeEntry entry =
    let
        base : List ( String, Encode.Value )
        base =
            [ ( "timestamp", Encode.int (Time.posixToMillis entry.timestamp) )
            , ( "source", Encode.string (sourceToString entry.source) )
            , ( "severity", Encode.string (severityToString entry.severity) )
            , ( "message", Encode.string entry.message )
            ]
    in
    if entry.count > 1 then
        Encode.object (( "count", Encode.int entry.count ) :: base)

    else
        Encode.object base
