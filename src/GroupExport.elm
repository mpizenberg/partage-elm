module GroupExport exposing (ExportData, decoder, encode)

{-| Encode and decode group export payloads for backup and sharing.
-}

import Domain.Event as Event
import Json.Decode as Decode
import Json.Encode as Encode
import Storage exposing (GroupSummary)
import Time


{-| All data needed to export or import a group.
-}
type alias ExportData =
    { group : GroupSummary
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
        , ( "group", Storage.encodeGroupSummary data.group )
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
                        (Decode.field "group" Storage.groupSummaryDecoder)
                        (Decode.field "groupKey" (Decode.nullable Decode.string))
                        (Decode.field "events" (Decode.list Event.envelopeDecoder))

                else
                    Decode.fail ("Unknown format: " ++ format)
            )


maybeEncode : (a -> Encode.Value) -> Maybe a -> Encode.Value
maybeEncode enc maybe =
    case maybe of
        Just val ->
            enc val

        Nothing ->
            Encode.null
