module GroupExport exposing (ExportData, ImportError(..), downloadGroup, validateImport)

{-| Encode and decode group export payloads for backup and sharing.
-}

import Domain.Event as Event
import Domain.Group as Group
import File.Download
import Json.Decode as Decode
import Json.Encode as Encode
import Set exposing (Set)
import Time


{-| All data needed to export or import a group.
-}
type alias ExportData =
    { group : Group.Summary
    , groupKey : Maybe String
    , events : List Event.Envelope
    }


{-| Encode an ExportData to a JSON string for file download.
-}
encode : Time.Posix -> ExportData -> String
encode now data =
    Encode.object
        [ ( "format", Encode.string "partage-group-v1" )
        , ( "exportedAt", Encode.int (Time.posixToMillis now) )
        , ( "group", Group.encodeSummary data.group )
        , ( "groupKey", maybeEncode Encode.string data.groupKey )
        , ( "events", Encode.list Event.encodeEnvelope data.events )
        ]
        |> Encode.encode 2


{-| Decode an ExportData from a JSON string.
-}
decoder : Decode.Decoder ExportData
decoder =
    Decode.field "format" Decode.string
        |> Decode.andThen
            (\format ->
                if format == "partage-group-v1" then
                    Decode.map3 ExportData
                        (Decode.field "group" Group.summaryDecoder)
                        (Decode.field "groupKey" (Decode.nullable Decode.string))
                        (Decode.field "events" (Decode.list Event.envelopeDecoder))

                else
                    Decode.fail ("Unknown format: " ++ format)
            )


{-| Download a group export as a JSON file.
-}
downloadGroup : Time.Posix -> Group.Summary -> List Event.Envelope -> Maybe String -> Cmd msg
downloadGroup now summary events maybeKey =
    let
        json : String
        json =
            encode now
                { group = summary
                , groupKey = maybeKey
                , events = events
                }

        filename : String
        filename =
            "partage-" ++ sanitizeFilename summary.name ++ ".json"
    in
    File.Download.string filename "application/json" json


{-| Errors that can occur when importing a group.
-}
type ImportError
    = AlreadyExists
    | InvalidFile


{-| Validate and decode a JSON string as an import, checking for duplicates.
-}
validateImport : Set Group.Id -> String -> Result ImportError ExportData
validateImport existingGroupIds jsonString =
    case Decode.decodeString decoder jsonString of
        Err _ ->
            Err InvalidFile

        Ok exportData ->
            if Set.member exportData.group.id existingGroupIds then
                Err AlreadyExists

            else
                Ok exportData


{-| Replace non-alphanumeric characters with hyphens for safe filenames.
-}
sanitizeFilename : String -> String
sanitizeFilename name =
    String.toList name
        |> List.map
            (\c ->
                if Char.isAlphaNum c then
                    c

                else
                    '-'
            )
        |> String.fromList


maybeEncode : (a -> Encode.Value) -> Maybe a -> Encode.Value
maybeEncode enc maybe =
    case maybe of
        Just val ->
            enc val

        Nothing ->
            Encode.null
