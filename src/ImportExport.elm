module ImportExport exposing (Config, Msg, OutMsg(..), exportMsg, startImport, update)

{-| Import/export orchestration, extracted from Main.elm.

Handles the async task chains for exporting (load → encode → compress → download)
and importing (decompress → validate → save) groups.

`Msg` is opaque — Main only wraps it via `ImportExportMsg`. The only exposed
entry point is `exportMsg` (for Page.Home config) and `startImport` (called
when Page.Home outputs ImportFileLoaded).

-}

import ConcurrentTask
import Dict exposing (Dict)
import Domain.Event as Event
import Domain.Group as Group
import GroupExport
import IndexedDb as Idb
import Infra.Compression as Compression
import Infra.ConcurrentTaskExtra as Runner exposing (TaskRunner)
import Infra.Storage as Storage
import Set
import Time
import Translations as T exposing (I18n)
import UI.Toast as Toast


type Msg
    = ExportGroup Group.Id
    | OnExportDataLoaded Group.Id (ConcurrentTask.Response Idb.Error ( List Event.Envelope, Maybe String ))
    | OnExportCompressed (ConcurrentTask.Response String ())
    | OnImportDecompressed (ConcurrentTask.Response String String)
    | OnGroupImported Group.Summary (ConcurrentTask.Response Idb.Error ())


type OutMsg
    = ShowToast Toast.ToastLevel String
    | SetImportError String
    | GroupImported Group.Summary


{-| Opaque message to start a group export. Use in Page.Home config:

    { onExport = ImportExportMsg << ImportExport.exportMsg }

-}
exportMsg : Group.Id -> Msg
exportMsg =
    ExportGroup


{-| Start importing from a base64-encoded compressed file.
Called when Page.Home outputs ImportFileLoaded.

    |> ImportExport.startImport ImportExportMsg base64

-}
startImport : (Msg -> msg) -> String -> ( TaskRunner msg, Cmd msg ) -> ( TaskRunner msg, Cmd msg )
startImport toMsg base64 =
    Runner.andRun (toMsg << OnImportDecompressed) (Compression.decompress base64)


type alias Config msg =
    { toMsg : Msg -> msg
    , db : Idb.Db
    , groups : Dict Group.Id Group.Summary
    , currentTime : Time.Posix
    , i18n : I18n
    }


update : Config msg -> Msg -> ( TaskRunner msg, Cmd msg ) -> ( ( TaskRunner msg, Cmd msg ), Maybe OutMsg )
update config msg runnerCmd =
    case msg of
        ExportGroup groupId ->
            ( runnerCmd
                |> Runner.andRun (config.toMsg << OnExportDataLoaded groupId)
                    (ConcurrentTask.map2 Tuple.pair
                        (Storage.loadGroupEvents config.db groupId)
                        (Storage.loadGroupKey config.db groupId)
                    )
            , Nothing
            )

        OnExportDataLoaded groupId (ConcurrentTask.Success ( events, maybeKey )) ->
            case Dict.get groupId config.groups of
                Just summary ->
                    let
                        json : String
                        json =
                            GroupExport.encodeExport config.currentTime summary events maybeKey

                        filename : String
                        filename =
                            GroupExport.exportFilename summary
                    in
                    ( runnerCmd
                        |> Runner.andRun (config.toMsg << OnExportCompressed)
                            (Compression.compressAndDownload json filename)
                    , Nothing
                    )

                Nothing ->
                    ( runnerCmd, Nothing )

        OnExportDataLoaded _ _ ->
            ( runnerCmd, Just (ShowToast Toast.Error (T.toastExportError config.i18n)) )

        OnExportCompressed (ConcurrentTask.Error _) ->
            ( runnerCmd, Just (ShowToast Toast.Error (T.toastExportError config.i18n)) )

        OnExportCompressed _ ->
            ( runnerCmd, Nothing )

        OnImportDecompressed (ConcurrentTask.Success jsonString) ->
            let
                existingIds : Set.Set Group.Id
                existingIds =
                    Dict.keys config.groups |> Set.fromList
            in
            case GroupExport.validateImport existingIds jsonString of
                Err GroupExport.InvalidFile ->
                    ( runnerCmd, Just (SetImportError (T.importErrorInvalidFile config.i18n)) )

                Err GroupExport.AlreadyExists ->
                    ( runnerCmd, Just (SetImportError (T.importErrorAlreadyExists config.i18n)) )

                Ok exportData ->
                    ( runnerCmd
                        |> Runner.andRun (config.toMsg << OnGroupImported exportData.group)
                            (Storage.saveGroup config.db exportData.group exportData.groupKey exportData.events Nothing)
                    , Nothing
                    )

        OnImportDecompressed _ ->
            ( runnerCmd, Just (SetImportError (T.importErrorInvalidFile config.i18n)) )

        OnGroupImported summary (ConcurrentTask.Success _) ->
            ( runnerCmd, Just (GroupImported summary) )

        OnGroupImported _ _ ->
            ( runnerCmd, Just (ShowToast Toast.Error (T.toastImportError config.i18n)) )
