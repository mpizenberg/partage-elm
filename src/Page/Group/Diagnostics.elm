module Page.Group.Diagnostics exposing
    ( Model
    , Stats
    , formatBytes
    , histogram
    , init
    , isFresh
    , load
    , median
    , view
    )

{-| Hidden per-group diagnostics page (developer mode only).

Read-only measurement instrument: event counts, plaintext and compressed
sizes, sync state, device storage, and a timed full replay. Everything is
computed client-side — the relay only ever sees ciphertext.

-}

import ConcurrentTask exposing (ConcurrentTask)
import ConcurrentTask.Time
import Dict
import Domain.Event as Event
import Domain.Group as Group
import Domain.GroupState as GroupState
import GroupOps exposing (LoadedGroup)
import Infra.UsageStats as UsageStats
import Json.Decode as Decode
import Json.Encode as Encode
import Set
import Time
import Translations as T exposing (I18n)
import UI.Components
import UI.Theme as Theme
import Ui
import Ui.Font


{-| Async measurements for the group they were computed on. `Nothing` while
measuring. The pure metrics (counts, histogram, sync state) are read straight
from the loaded group at view time and need no model.
-}
type alias Model =
    Maybe Stats


type alias Stats =
    { groupId : Group.Id
    , forEventCount : Int
    , totalPlaintextBytes : Int
    , avgPlaintextBytes : Int
    , medianPlaintextBytes : Int
    , gzip : Maybe { wholeLogBytes : Int, perEventBytes : Int }
    , storage : UsageStats.StorageEstimate
    , persistStatus : UsageStats.PersistedStatus
    , replayMillis : Int
    , replayEntryCount : Int
    }


init : Model
init =
    Nothing


{-| Whether the measured stats still describe the loaded group. Stale after
a sync or local edit changes the event log (or after switching groups).
-}
isFresh : LoadedGroup -> Model -> Bool
isFresh loaded model =
    case model of
        Just stats ->
            stats.groupId == loaded.summary.id && stats.forEventCount == List.length loaded.events

        Nothing ->
            False



-- MEASUREMENT TASKS


load : LoadedGroup -> ConcurrentTask Never Stats
load loaded =
    replayTask loaded.events
        |> ConcurrentTask.andThen
            (\replay ->
                ConcurrentTask.map3 (buildStats loaded replay)
                    (compressionTask loaded.events)
                    UsageStats.estimateStorage
                    UsageStats.persistedStatus
            )


buildStats :
    LoadedGroup
    -> { millis : Int, entryCount : Int }
    -> CompressionStats
    -> UsageStats.StorageEstimate
    -> UsageStats.PersistedStatus
    -> Stats
buildStats loaded replay compression storage persistStatus =
    let
        count : Int
        count =
            List.length compression.plaintextBytes

        total : Int
        total =
            List.sum compression.plaintextBytes
    in
    { groupId = loaded.summary.id
    , forEventCount = count
    , totalPlaintextBytes = total
    , avgPlaintextBytes =
        if count == 0 then
            0

        else
            total // count
    , medianPlaintextBytes = median compression.plaintextBytes
    , gzip = compression.gzip
    , storage = storage
    , persistStatus = persistStatus
    , replayMillis = replay.millis
    , replayEntryCount = replay.entryCount
    }


type alias CompressionStats =
    { plaintextBytes : List Int
    , gzip : Maybe { wholeLogBytes : Int, perEventBytes : Int }
    }


compressionTask : List Event.Envelope -> ConcurrentTask Never CompressionStats
compressionTask envelopes =
    ConcurrentTask.define
        { function = "diagnostics:compressionStats"
        , expect = ConcurrentTask.expectJson compressionStatsDecoder
        , errors = ConcurrentTask.expectNoErrors
        , args =
            Encode.object
                [ ( "events"
                  , Encode.list (Event.encodeEnvelope >> Encode.encode 0 >> Encode.string) envelopes
                  )
                ]
        }


compressionStatsDecoder : Decode.Decoder CompressionStats
compressionStatsDecoder =
    Decode.map2 CompressionStats
        (Decode.field "plaintextBytes" (Decode.list Decode.int))
        (Decode.field "gzip"
            (Decode.nullable
                (Decode.map2 (\whole per -> { wholeLogBytes = whole, perEventBytes = per })
                    (Decode.field "wholeLogBytes" Decode.int)
                    (Decode.field "perEventBytes" Decode.int)
                )
            )
        )


{-| Time a full sort + replay of the log, as done on every group open.
The interval includes two task-port round-trips (~1 ms of noise), which only
matters below benchmark scale.
-}
replayTask : List Event.Envelope -> ConcurrentTask Never { millis : Int, entryCount : Int }
replayTask events =
    ConcurrentTask.Time.now
        |> ConcurrentTask.andThen
            (\before ->
                let
                    replayed : GroupState.GroupState
                    replayed =
                        GroupState.applyEvents events GroupState.empty
                in
                ConcurrentTask.Time.now
                    |> ConcurrentTask.map
                        (\after ->
                            { millis = Time.posixToMillis after - Time.posixToMillis before
                            , entryCount = Dict.size replayed.entries
                            }
                        )
            )



-- PURE METRICS


{-| Per-payload-type event counts, most frequent first.
-}
histogram : List Event.Envelope -> List ( String, Int )
histogram envelopes =
    List.foldl
        (\envelope counts ->
            Dict.update (payloadName envelope.payload)
                (Maybe.withDefault 0 >> (+) 1 >> Just)
                counts
        )
        Dict.empty
        envelopes
        |> Dict.toList
        |> List.sortBy (\( name, count ) -> ( -count, name ))


payloadName : Event.Payload -> String
payloadName payload =
    case payload of
        Event.Unknown ->
            "Unknown"

        Event.MemberCreated _ ->
            "MemberCreated"

        Event.MemberRenamed _ ->
            "MemberRenamed"

        Event.MemberRetired _ ->
            "MemberRetired"

        Event.MemberUnretired _ ->
            "MemberUnretired"

        Event.MemberLinked _ ->
            "MemberLinked"

        Event.MemberMetadataUpdated _ ->
            "MemberMetadataUpdated"

        Event.EntryAdded _ ->
            "EntryAdded"

        Event.EntryModified _ ->
            "EntryModified"

        Event.EntryDeleted _ ->
            "EntryDeleted"

        Event.EntryUndeleted _ ->
            "EntryUndeleted"

        Event.GroupCreated _ ->
            "GroupCreated"

        Event.GroupMetadataUpdated _ ->
            "GroupMetadataUpdated"

        Event.SettlementPreferencesUpdated _ ->
            "SettlementPreferencesUpdated"


{-| Median of a list of ints (0 for an empty list, lower middle for even
lengths — byte-size precision does not warrant averaging the two middles).
-}
median : List Int -> Int
median values =
    let
        sorted : List Int
        sorted =
            List.sort values
    in
    sorted
        |> List.drop ((List.length sorted - 1) // 2)
        |> List.head
        |> Maybe.withDefault 0


formatBytes : Int -> String
formatBytes bytes =
    let
        scaled : Float -> String
        scaled unit =
            let
                tenths : Int
                tenths =
                    round (toFloat bytes / unit * 10)
            in
            String.fromInt (tenths // 10)
                ++ (if remainderBy 10 tenths == 0 then
                        ""

                    else
                        "." ++ String.fromInt (remainderBy 10 tenths)
                   )
    in
    if bytes < 1000 then
        String.fromInt bytes ++ " B"

    else if bytes < 1000000 then
        scaled 1000 ++ " kB"

    else
        scaled 1000000 ++ " MB"



-- VIEW


view : I18n -> LoadedGroup -> Model -> Ui.Element msg
view i18n loaded model =
    Ui.column [ Ui.spacing Theme.spacing.xl, Ui.width Ui.fill, Ui.paddingXY 0 Theme.spacing.md ]
        [ eventsSection i18n loaded
        , syncSection i18n loaded
        , sizesSection i18n model
        , storageSection i18n model
        , replaySection i18n model
        ]


eventsSection : I18n -> LoadedGroup -> Ui.Element msg
eventsSection i18n loaded =
    section (T.diagEventsTitle i18n)
        (metricRow (T.diagEventCount i18n) (String.fromInt (List.length loaded.events))
            :: List.map
                (\( name, count ) -> metricRow name (String.fromInt count))
                (histogram loaded.events)
        )


syncSection : I18n -> LoadedGroup -> Ui.Element msg
syncSection i18n loaded =
    section (T.diagSyncTitle i18n)
        [ metricRow (T.diagSyncCursor i18n)
            (case loaded.syncCursor of
                Just cursor ->
                    String.fromInt cursor

                Nothing ->
                    T.diagNeverSynced i18n
            )
        , metricRow (T.diagUnpushedCount i18n) (String.fromInt (Set.size loaded.unpushedIds))
        ]


sizesSection : I18n -> Model -> Ui.Element msg
sizesSection i18n model =
    asyncSection i18n
        (T.diagSizesTitle i18n)
        model
        (\stats ->
            [ metricRow (T.diagTotalSize i18n) (formatBytes stats.totalPlaintextBytes)
            , metricRow (T.diagAvgSize i18n) (formatBytes stats.avgPlaintextBytes)
            , metricRow (T.diagMedianSize i18n) (formatBytes stats.medianPlaintextBytes)
            ]
                ++ (case stats.gzip of
                        Just gzip ->
                            [ metricRow (T.diagGzipPerEvent i18n) (formatBytes gzip.perEventBytes)
                            , metricRow (T.diagGzipWholeLog i18n) (formatBytes gzip.wholeLogBytes)
                            , metricRow (T.diagGzipSavings i18n) (formatBytes (max 0 (gzip.perEventBytes - gzip.wholeLogBytes)))
                            ]

                        Nothing ->
                            [ subtleText (T.diagGzipUnavailable i18n) ]
                   )
        )


storageSection : I18n -> Model -> Ui.Element msg
storageSection i18n model =
    asyncSection i18n
        (T.diagStorageTitle i18n)
        model
        (\stats ->
            [ metricRow (T.diagStorageUsage i18n)
                (formatBytes stats.storage.usage ++ " / " ++ formatBytes stats.storage.quota)
            , subtleText
                (case stats.persistStatus of
                    UsageStats.Persisted ->
                        T.aboutPersistGranted i18n

                    UsageStats.NotPersisted ->
                        T.aboutPersistDenied i18n

                    UsageStats.PersistUnsupported ->
                        T.aboutPersistUnsupported i18n
                )
            ]
        )


replaySection : I18n -> Model -> Ui.Element msg
replaySection i18n model =
    asyncSection i18n
        (T.diagReplayTitle i18n)
        model
        (\stats ->
            [ metricRow (T.diagReplayTime i18n) (String.fromInt stats.replayMillis ++ " ms")
            , metricRow (T.diagReplayEntries i18n) (String.fromInt stats.replayEntryCount)
            ]
        )


section : String -> List (Ui.Element msg) -> Ui.Element msg
section title rows =
    Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
        [ UI.Components.sectionLabel title
        , UI.Components.card [ Ui.padding Theme.spacing.lg ]
            [ Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ] rows ]
        ]


asyncSection : I18n -> String -> Model -> (Stats -> List (Ui.Element msg)) -> Ui.Element msg
asyncSection i18n title model rows =
    section title
        (case model of
            Just stats ->
                rows stats

            Nothing ->
                [ subtleText (T.diagMeasuring i18n) ]
        )


metricRow : String -> String -> Ui.Element msg
metricRow label value =
    Ui.row [ Ui.width Ui.fill, Ui.spacing Theme.spacing.sm ]
        [ Ui.el [ Ui.Font.size Theme.font.sm, Ui.Font.color Theme.base.text ]
            (Ui.text label)
        , Ui.el
            [ Ui.Font.size Theme.font.sm
            , Ui.Font.weight Theme.fontWeight.semibold
            , Ui.alignRight
            ]
            (Ui.text value)
        ]


subtleText : String -> Ui.Element msg
subtleText value =
    Ui.el [ Ui.Font.size Theme.font.sm, Ui.Font.color Theme.base.textSubtle ]
        (Ui.text value)
