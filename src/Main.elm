port module Main exposing (AppState, Flags, Model, Msg, main)

import AppUrl
import Browser
import ConcurrentTask
import Dict
import Domain.Currency
import Domain.Date as Date
import Domain.Entry as Entry
import Domain.Event as Event
import Domain.Group as Group
import Domain.GroupState as GroupState
import Domain.Member as Member
import Domain.Settlement as Settlement
import Form.NewGroup
import GroupExport
import Html exposing (Html)
import Identity exposing (Identity)
import IndexedDb as Idb
import Json.Decode
import Json.Encode
import Navigation
import Page.About
import Page.AddMember
import Page.EditGroupMetadata
import Page.EditMemberMetadata
import Page.EntryDetail
import Page.Group
import Page.Home
import Page.InitError
import Page.Loading
import Page.MemberDetail
import Page.NewEntry
import Page.NewGroup
import Page.NotFound
import Page.Setup
import PocketBase
import PocketBase.Realtime
import Random
import Route exposing (GroupTab(..), GroupView(..), Route(..))
import Server
import Set exposing (Set)
import Storage exposing (GroupSummary)
import Submit exposing (LoadedGroup)
import Time
import Translations as T exposing (I18n, Language(..))
import UI.Components
import UI.Shell
import UI.Theme as Theme
import UI.Toast as Toast
import UUID
import Ui
import Ui.Font
import Url
import WebCrypto
import WebCrypto.Symmetric as Symmetric


port navCmd : Navigation.CommandPort msg


port onNavEvent : Navigation.EventPort msg


port sendTask : Json.Encode.Value -> Cmd msg


port receiveTask : (Json.Decode.Value -> msg) -> Sub msg


port onClipboardCopy : (() -> msg) -> Sub msg


port onPocketbaseEvent : (Json.Decode.Value -> msg) -> Sub msg


type alias Flags =
    { initialUrl : String
    , language : String
    , randomSeed : List Int
    , currentTime : Int
    , serverUrl : String
    }


type alias Model =
    { route : Route
    , appState : AppState
    , generatingIdentity : Bool
    , i18n : I18n
    , language : Language
    , pool : ConcurrentTask.Pool Msg
    , uuidState : UUID.V7State
    , randomSeed : Random.Seed
    , currentTime : Time.Posix
    , newGroupModel : Page.NewGroup.Model
    , newEntryModel : Page.NewEntry.Model
    , memberDetailModel : Page.MemberDetail.Model
    , addMemberModel : Page.AddMember.Model
    , editMemberMetadataModel : Page.EditMemberMetadata.Model
    , entryDetailModel : Page.EntryDetail.Model
    , editGroupMetadataModel : Page.EditGroupMetadata.Model
    , loadedGroup : Maybe LoadedGroup
    , groupModel : Page.Group.Model
    , homeModel : Page.Home.Model
    , toastModel : Toast.Model
    , pendingTransfer : Maybe { toMemberId : Member.Id, amountCents : Int }
    , serverUrl : String
    , pbClient : Maybe PocketBase.Client
    , syncInProgress : Bool
    }


type AppState
    = Loading
    | Ready Storage.InitData
    | InitError String


type Msg
    = OnNavEvent Navigation.Event
    | NavigateTo Route
    | SwitchTab GroupTab
    | SwitchLanguage Language
    | GenerateIdentity
    | OnTaskProgress ( ConcurrentTask.Pool Msg, Cmd Msg )
    | OnIdentityGenerated (ConcurrentTask.Response WebCrypto.Error Identity)
    | OnInitComplete (ConcurrentTask.Response Idb.Error Storage.InitData)
    | OnIdentitySaved (ConcurrentTask.Response Idb.Error ())
      -- Page form messages
    | NewGroupMsg Page.NewGroup.Msg
    | NewEntryMsg Page.NewEntry.Msg
      -- Form submission responses
    | OnGroupCreated (ConcurrentTask.Response Idb.Error GroupSummary)
    | OnEntrySaved Group.Id (ConcurrentTask.Response Idb.Error Event.Envelope)
      -- Entry actions
    | PayMember { toMemberId : Member.Id, amountCents : Int }
    | SettleTransaction Settlement.Transaction
    | SaveSettlementPreferences { memberRootId : Member.Id, preferredRecipients : List Member.Id }
    | EntryDetailMsg Page.EntryDetail.Msg
    | OnEntryActionSaved Group.Id (ConcurrentTask.Response Idb.Error Event.Envelope)
    | GroupMsg Page.Group.Msg
      -- Member management
    | MemberDetailMsg Page.MemberDetail.Msg
    | AddMemberMsg Page.AddMember.Msg
    | EditMemberMetadataMsg Page.EditMemberMetadata.Msg
    | OnMemberActionSaved Group.Id (ConcurrentTask.Response Idb.Error Event.Envelope)
      -- Group metadata editing
    | EditGroupMetadataMsg Page.EditGroupMetadata.Msg
    | OnGroupMetadataActionSaved Group.Id (ConcurrentTask.Response Idb.Error Event.Envelope)
    | OnGroupRemoved Group.Id (ConcurrentTask.Response Idb.Error ())
    | OnGroupSummarySaved (ConcurrentTask.Response Idb.Error Idb.Key)
      -- Group loading
    | OnGroupEventsLoaded Group.Id (ConcurrentTask.Response Idb.Error { events : List Event.Envelope, groupKey : Symmetric.Key, syncCursor : Maybe String, unpushedIds : Set String })
      -- Import / Export
    | HomeMsg Page.Home.Msg
    | ExportGroup Group.Id
    | OnExportDataLoaded Group.Id (ConcurrentTask.Response Idb.Error ( List Event.Envelope, Maybe String ))
    | OnGroupImported Storage.GroupSummary (ConcurrentTask.Response Idb.Error ())
      -- Server sync
    | OnPbClientInitialized (ConcurrentTask.Response PocketBase.Error PocketBase.Client)
    | OnServerGroupCreated Group.Id (ConcurrentTask.Response Server.Error ())
    | OnGroupSynced Group.Id (Set String) (ConcurrentTask.Response Server.Error Server.SyncResult)
    | PostSyncTasksDone (ConcurrentTask.Response Idb.Error ())
    | OnPocketbaseEvent Json.Decode.Value
      -- Toast notifications
    | ClipboardCopied
    | DismissToast Toast.ToastId


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ Navigation.onEvent onNavEvent OnNavEvent
        , ConcurrentTask.onProgress
            { send = sendTask
            , receive = receiveTask
            , onProgress = OnTaskProgress
            }
            model.pool
        , onClipboardCopy (\() -> ClipboardCopied)
        , onPocketbaseEvent OnPocketbaseEvent
        ]


{-| Application entry point.
-}
main : Program Flags Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , subscriptions = subscriptions
        , view = view
        }


init : Flags -> ( Model, Cmd Msg )
init flags =
    let
        route : Route
        route =
            flags.initialUrl
                |> Url.fromString
                |> Maybe.map (AppUrl.fromUrl >> Route.fromAppUrl)
                |> Maybe.withDefault NotFound

        language : Language
        language =
            flags.language
                |> T.languageFromString
                |> Maybe.withDefault En

        i18n : I18n
        i18n =
            T.init language

        initialSeed : Random.Seed
        initialSeed =
            List.foldl
                (\_ acc -> Random.step (Random.int Random.minInt Random.maxInt) acc |> Tuple.second)
                (Random.initialSeed (List.sum flags.randomSeed))
                flags.randomSeed

        ( uuidState, seedAfterV7 ) =
            Random.step UUID.initialV7State initialSeed

        currentTime : Time.Posix
        currentTime =
            Time.millisToPosix flags.currentTime

        ( pool, cmd ) =
            ConcurrentTask.attempt
                { pool = ConcurrentTask.pool
                , send = sendTask
                , onComplete = OnInitComplete
                }
                (Storage.open |> ConcurrentTask.andThen Storage.init)
    in
    ( { route = route
      , appState = Loading
      , generatingIdentity = False
      , i18n = i18n
      , language = language
      , pool = pool
      , uuidState = uuidState
      , randomSeed = seedAfterV7
      , currentTime = currentTime
      , newGroupModel = Page.NewGroup.init
      , newEntryModel = Page.NewEntry.init { currentUserRootId = "", activeMembersRootIds = [], today = Date.posixToDate currentTime, defaultCurrency = Domain.Currency.EUR }
      , memberDetailModel = Page.MemberDetail.init Member.emptyChainState
      , addMemberModel = Page.AddMember.init
      , editMemberMetadataModel = Page.EditMemberMetadata.init "" "" Member.emptyMetadata
      , entryDetailModel = Page.EntryDetail.init
      , editGroupMetadataModel = Page.EditGroupMetadata.init GroupState.empty.groupMeta
      , loadedGroup = Nothing
      , groupModel = Page.Group.init
      , homeModel = Page.Home.init
      , toastModel = Toast.init
      , pendingTransfer = Nothing
      , serverUrl = flags.serverUrl
      , pbClient = Nothing
      , syncInProgress = False
      }
    , cmd
    )


addToast : Toast.ToastLevel -> String -> Model -> ( Model, Cmd Msg )
addToast level message model =
    Toast.push DismissToast level message model.toastModel
        |> Tuple.mapFirst (\toast -> { model | toastModel = toast })


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        OnNavEvent event ->
            let
                route : Route
                route =
                    Route.fromAppUrl event.appUrl

                ( guardedRoute, guardCmd ) =
                    case model.appState of
                        Ready data ->
                            applyRouteGuard data.identity route

                        _ ->
                            applyRouteGuard Nothing route

                ( modelAfterGuard, loadCmd ) =
                    ensureGroupLoaded { model | route = guardedRoute } guardedRoute

                modelWithPages : Model
                modelWithPages =
                    initPagesIfNeeded guardedRoute modelAfterGuard
            in
            ( modelWithPages, Cmd.batch [ guardCmd, loadCmd ] )

        NavigateTo route ->
            ( model, Navigation.pushUrl navCmd (Route.toAppUrl route) )

        SwitchTab tab ->
            case model.route of
                GroupRoute groupId _ ->
                    let
                        newRoute : Route
                        newRoute =
                            GroupRoute groupId (Tab tab)
                    in
                    ( { model | route = newRoute }
                    , Navigation.pushUrl navCmd (Route.toAppUrl newRoute)
                    )

                _ ->
                    ( model, Cmd.none )

        SwitchLanguage lang ->
            ( { model | language = lang, i18n = T.init lang }
            , Cmd.none
            )

        GenerateIdentity ->
            let
                ( pool, cmd ) =
                    ConcurrentTask.attempt
                        { pool = model.pool
                        , send = sendTask
                        , onComplete = OnIdentityGenerated
                        }
                        Identity.generate
            in
            ( { model | pool = pool, generatingIdentity = True }, cmd )

        OnTaskProgress ( pool, cmd ) ->
            ( { model | pool = pool }, cmd )

        OnIdentityGenerated (ConcurrentTask.Success identity) ->
            case model.appState of
                Ready readyData ->
                    let
                        updatedReadyData : Storage.InitData
                        updatedReadyData =
                            { readyData | identity = Just identity }

                        ( guardedRoute, navCmd_ ) =
                            applyRouteGuard (Just identity) model.route

                        ( pool, taskCmd ) =
                            ConcurrentTask.attempt
                                { pool = model.pool
                                , send = sendTask
                                , onComplete = OnIdentitySaved
                                }
                                (Storage.saveIdentity readyData.db identity)
                    in
                    ( { model
                        | appState = Ready updatedReadyData
                        , generatingIdentity = False
                        , route = guardedRoute
                        , pool = pool
                      }
                    , Cmd.batch [ navCmd_, taskCmd ]
                    )

                _ ->
                    ( { model | generatingIdentity = False }, Cmd.none )

        OnIdentityGenerated _ ->
            ( { model | generatingIdentity = False }, Cmd.none )

        OnInitComplete (ConcurrentTask.Success readyData) ->
            let
                ( guardedRoute, guardCmd ) =
                    applyRouteGuard readyData.identity model.route

                ( modelWithData, loadCmd ) =
                    ensureGroupLoaded
                        { model
                            | appState = Ready readyData
                            , route = guardedRoute
                        }
                        guardedRoute

                ( poolAfterPb, pbCmd ) =
                    ConcurrentTask.attempt
                        { pool = modelWithData.pool
                        , send = sendTask
                        , onComplete = OnPbClientInitialized
                        }
                        (PocketBase.init model.serverUrl)
            in
            ( { modelWithData | pool = poolAfterPb }
            , Cmd.batch [ guardCmd, loadCmd, pbCmd ]
            )

        OnInitComplete (ConcurrentTask.Error err) ->
            ( { model | appState = InitError (Storage.errorToString err) }, Cmd.none )

        OnInitComplete (ConcurrentTask.UnexpectedError _) ->
            ( { model | appState = InitError "Unexpected error during initialization" }, Cmd.none )

        OnIdentitySaved (ConcurrentTask.Success _) ->
            ( model, Cmd.none )

        OnIdentitySaved _ ->
            ( model, Cmd.none )

        -- Page form messages
        NewGroupMsg subMsg ->
            let
                ( newGroupModel, maybeOutput ) =
                    Page.NewGroup.update subMsg model.newGroupModel

                modelWithForm : Model
                modelWithForm =
                    { model | newGroupModel = newGroupModel }
            in
            case ( maybeOutput, model.appState ) of
                ( Just output, Ready readyData ) ->
                    submitNewGroup modelWithForm readyData output

                _ ->
                    ( modelWithForm, Cmd.none )

        NewEntryMsg subMsg ->
            let
                ( newEntryModel, maybeOutput ) =
                    Page.NewEntry.update subMsg model.newEntryModel

                modelWithForm : Model
                modelWithForm =
                    { model | newEntryModel = newEntryModel }
            in
            case ( maybeOutput, model.appState, model.loadedGroup ) of
                ( Just output, Ready readyData, Just loaded ) ->
                    case model.route of
                        GroupRoute _ (EditEntry entryId) ->
                            submitEditEntry modelWithForm readyData loaded entryId output

                        _ ->
                            submitNewEntry modelWithForm readyData loaded output

                _ ->
                    ( modelWithForm, Cmd.none )

        OnGroupCreated (ConcurrentTask.Success summary) ->
            case model.appState of
                Ready readyData ->
                    let
                        newRoute : Route
                        newRoute =
                            GroupRoute summary.id (Tab EntriesTab)

                        -- Trigger server group creation in background
                        ( poolAfterServer, serverCmd ) =
                            case model.pbClient of
                                Just client ->
                                    ConcurrentTask.attempt
                                        { pool = model.pool
                                        , send = sendTask
                                        , onComplete = OnServerGroupCreated summary.id
                                        }
                                        (Storage.loadGroupKeyRequired readyData.db summary.id
                                            |> ConcurrentTask.mapError (\_ -> Server.PbError (PocketBase.ServerError "Failed to load group key in IndexedDB"))
                                            |> ConcurrentTask.andThen
                                                (\key ->
                                                    Server.createGroupOnServer client
                                                        { groupId = summary.id
                                                        , groupKey = key
                                                        , createdBy = getIdentity model
                                                        }
                                                )
                                        )

                                Nothing ->
                                    ( model.pool, Cmd.none )
                    in
                    ( { model
                        | appState = Ready { readyData | groups = Dict.insert summary.id summary readyData.groups }
                        , loadedGroup = Nothing
                        , pool = poolAfterServer
                      }
                    , Cmd.batch [ Navigation.pushUrl navCmd (Route.toAppUrl newRoute), serverCmd ]
                    )

                _ ->
                    ( model, Cmd.none )

        OnGroupCreated _ ->
            addToast Toast.Error (T.toastGroupCreateError model.i18n) model

        OnEntrySaved groupId (ConcurrentTask.Success envelope) ->
            case appendEventAndRecompute model groupId envelope of
                Just updatedModel ->
                    let
                        modelWithUnpushed : Model
                        modelWithUnpushed =
                            addUnpushedIdToModel envelope.id updatedModel

                        ( syncModel, syncCmd ) =
                            triggerSync modelWithUnpushed groupId
                    in
                    case model.route of
                        GroupRoute _ (Tab BalanceTab) ->
                            addToast Toast.Success (T.toastSettlementRecorded model.i18n) syncModel
                                |> Tuple.mapSecond (\c -> Cmd.batch [ c, syncCmd ])

                        _ ->
                            ( syncModel
                            , Cmd.batch [ Navigation.pushUrl navCmd (Route.toAppUrl (GroupRoute groupId (Tab EntriesTab))), syncCmd ]
                            )

                Nothing ->
                    ( model, Cmd.none )

        OnEntrySaved _ _ ->
            addToast Toast.Error (T.toastEntrySaveError model.i18n) model

        PayMember payData ->
            case model.route of
                GroupRoute groupId _ ->
                    ( { model | pendingTransfer = Just payData }
                    , Navigation.pushUrl navCmd (Route.toAppUrl (GroupRoute groupId NewEntry))
                    )

                _ ->
                    ( model, Cmd.none )

        SettleTransaction tx ->
            case ( model.appState, model.loadedGroup ) of
                ( Ready readyData, Just loaded ) ->
                    let
                        output : Page.NewEntry.Output
                        output =
                            Page.NewEntry.TransferOutput
                                { amountCents = tx.amount
                                , currency = loaded.summary.defaultCurrency
                                , defaultCurrencyAmount = Nothing
                                , fromMemberId = tx.from
                                , toMemberId = tx.to
                                , notes = Nothing
                                , date = Date.posixToDate model.currentTime
                                }
                    in
                    submitNewEntry model readyData loaded output

                _ ->
                    ( model, Cmd.none )

        SaveSettlementPreferences prefData ->
            case ( model.appState, model.loadedGroup ) of
                ( Ready readyData, Just loaded ) ->
                    submitEvent (OnEntryActionSaved loaded.summary.id)
                        model
                        readyData
                        loaded
                        (Event.SettlementPreferencesUpdated prefData)

                _ ->
                    ( model, Cmd.none )

        EntryDetailMsg subMsg ->
            let
                ( entryDetailModel, maybeOutput ) =
                    Page.EntryDetail.update subMsg model.entryDetailModel

                modelWithPage : Model
                modelWithPage =
                    { model | entryDetailModel = entryDetailModel }
            in
            case maybeOutput of
                Just Page.EntryDetail.DeleteRequested ->
                    case model.route of
                        GroupRoute _ (EntryDetail entryId) ->
                            submitEntryAction modelWithPage (\ctx loaded -> Submit.deleteEntry ctx loaded entryId)

                        _ ->
                            ( modelWithPage, Cmd.none )

                Just Page.EntryDetail.RestoreRequested ->
                    case model.route of
                        GroupRoute _ (EntryDetail entryId) ->
                            submitEntryAction modelWithPage (\ctx loaded -> Submit.restoreEntry ctx loaded entryId)

                        _ ->
                            ( modelWithPage, Cmd.none )

                Just Page.EntryDetail.EditRequested ->
                    case model.route of
                        GroupRoute groupId (EntryDetail entryId) ->
                            ( modelWithPage, Navigation.pushUrl navCmd (Route.toAppUrl (GroupRoute groupId (EditEntry entryId))) )

                        _ ->
                            ( modelWithPage, Cmd.none )

                Just Page.EntryDetail.BackRequested ->
                    case model.route of
                        GroupRoute groupId _ ->
                            ( modelWithPage, Navigation.pushUrl navCmd (Route.toAppUrl (GroupRoute groupId (Tab EntriesTab))) )

                        _ ->
                            ( modelWithPage, Cmd.none )

                Nothing ->
                    ( modelWithPage, Cmd.none )

        OnEntryActionSaved groupId (ConcurrentTask.Success envelope) ->
            let
                baseModel : Model
                baseModel =
                    appendEventAndRecompute model groupId envelope
                        |> Maybe.withDefault model

                modelWithUnpushed : Model
                modelWithUnpushed =
                    addUnpushedIdToModel envelope.id baseModel

                ( syncModel, syncCmd ) =
                    triggerSync modelWithUnpushed groupId
            in
            case Toast.entryActionMessage model.i18n envelope.payload of
                Just message ->
                    addToast Toast.Success message syncModel
                        |> Tuple.mapSecond (\c -> Cmd.batch [ c, syncCmd ])

                Nothing ->
                    ( syncModel, syncCmd )

        OnEntryActionSaved _ _ ->
            addToast Toast.Error (T.toastEntryActionError model.i18n) model

        GroupMsg subMsg ->
            ( { model | groupModel = Page.Group.update subMsg model.groupModel }, Cmd.none )

        MemberDetailMsg subMsg ->
            let
                ( memberDetailModel, maybeOutput ) =
                    Page.MemberDetail.update subMsg model.memberDetailModel

                modelWithPage : Model
                modelWithPage =
                    { model | memberDetailModel = memberDetailModel }
            in
            case ( maybeOutput, model.appState, model.loadedGroup ) of
                ( Just output, Ready readyData, Just loaded ) ->
                    handleMemberDetailOutput modelWithPage readyData loaded output

                _ ->
                    ( modelWithPage, Cmd.none )

        AddMemberMsg subMsg ->
            let
                ( addMemberModel, maybeOutput ) =
                    Page.AddMember.update subMsg model.addMemberModel

                modelWithPage : Model
                modelWithPage =
                    { model | addMemberModel = addMemberModel }
            in
            case ( maybeOutput, model.appState, model.loadedGroup ) of
                ( Just output, Ready readyData, Just loaded ) ->
                    submitAddMember modelWithPage readyData loaded output

                _ ->
                    ( modelWithPage, Cmd.none )

        EditMemberMetadataMsg subMsg ->
            let
                ( editModel, maybeOutput ) =
                    Page.EditMemberMetadata.update subMsg model.editMemberMetadataModel

                modelWithPage : Model
                modelWithPage =
                    { model | editMemberMetadataModel = editModel }
            in
            case ( maybeOutput, model.appState, model.loadedGroup ) of
                ( Just output, Ready readyData, Just loaded ) ->
                    submitMemberMetadata modelWithPage readyData loaded output

                _ ->
                    ( modelWithPage, Cmd.none )

        OnMemberActionSaved groupId (ConcurrentTask.Success envelope) ->
            case appendEventAndRecompute model groupId envelope of
                Just updatedModel ->
                    let
                        modelWithUnpushed : Model
                        modelWithUnpushed =
                            addUnpushedIdToModel envelope.id updatedModel

                        ( syncModel, syncCmd ) =
                            triggerSync modelWithUnpushed groupId
                    in
                    case model.route of
                        GroupRoute gid AddVirtualMember ->
                            ( { syncModel | addMemberModel = Page.AddMember.init }
                            , Cmd.batch [ Navigation.pushUrl navCmd (Route.toAppUrl (GroupRoute gid (Tab MembersTab))), syncCmd ]
                            )

                        GroupRoute gid (EditMemberMetadata memberId) ->
                            ( syncModel
                            , Cmd.batch [ Navigation.pushUrl navCmd (Route.toAppUrl (GroupRoute gid (MemberDetail memberId))), syncCmd ]
                            )

                        _ ->
                            ( initPagesIfNeeded model.route syncModel
                            , syncCmd
                            )

                Nothing ->
                    ( model, Cmd.none )

        OnMemberActionSaved _ _ ->
            addToast Toast.Error (T.toastMemberActionError model.i18n) model

        -- Group metadata editing
        EditGroupMetadataMsg subMsg ->
            let
                result : Page.EditGroupMetadata.UpdateResult
                result =
                    Page.EditGroupMetadata.update subMsg model.editGroupMetadataModel

                modelWithPage : Model
                modelWithPage =
                    { model | editGroupMetadataModel = result.model }
            in
            if result.deleteRequested then
                case model.route of
                    GroupRoute groupId _ ->
                        deleteGroup modelWithPage groupId

                    _ ->
                        ( modelWithPage, Cmd.none )

            else
                case ( result.metadataOutput, model.appState, model.loadedGroup ) of
                    ( Just change, Ready readyData, Just loaded ) ->
                        submitGroupMetadata modelWithPage readyData loaded change

                    _ ->
                        ( modelWithPage, Cmd.none )

        OnGroupMetadataActionSaved groupId (ConcurrentTask.Success envelope) ->
            case appendEventAndRecompute model groupId envelope of
                Just updatedModel ->
                    let
                        modelWithUnpushed : Model
                        modelWithUnpushed =
                            addUnpushedIdToModel envelope.id updatedModel

                        ( modelAfterSummary, summaryCmd ) =
                            syncGroupSummaryName groupId modelWithUnpushed

                        ( syncModel, syncCmd ) =
                            triggerSync modelAfterSummary groupId
                    in
                    ( syncModel
                    , Cmd.batch
                        [ summaryCmd
                        , syncCmd
                        , Navigation.pushUrl navCmd (Route.toAppUrl (GroupRoute groupId (Tab MembersTab)))
                        ]
                    )

                Nothing ->
                    ( model, Cmd.none )

        OnGroupMetadataActionSaved _ _ ->
            addToast Toast.Error (T.toastGroupSettingsError model.i18n) model

        OnGroupRemoved groupId (ConcurrentTask.Success _) ->
            case model.appState of
                Ready readyData ->
                    let
                        ( modelWithToast, toastCmd ) =
                            addToast Toast.Success
                                (T.toastGroupRemoved model.i18n)
                                { model
                                    | appState = Ready { readyData | groups = Dict.remove groupId readyData.groups }
                                    , loadedGroup = Nothing
                                }
                    in
                    ( modelWithToast
                    , Cmd.batch [ Navigation.pushUrl navCmd (Route.toAppUrl Home), toastCmd ]
                    )

                _ ->
                    ( model, Cmd.none )

        OnGroupRemoved _ _ ->
            addToast Toast.Error (T.toastGroupRemoveError model.i18n) model

        OnGroupSummarySaved (ConcurrentTask.Success _) ->
            ( model, Cmd.none )

        OnGroupSummarySaved _ ->
            ( model, Cmd.none )

        -- Group loading
        OnGroupEventsLoaded groupId (ConcurrentTask.Success result) ->
            let
                modelAfterLoad : Model
                modelAfterLoad =
                    applyLoadedGroup groupId result.events result.groupKey result.syncCursor result.unpushedIds model
                        |> Maybe.map (initPagesIfNeeded model.route)
                        |> Maybe.withDefault model
            in
            -- Only sync if group has been synced before (has a cursor).
            -- Freshly created groups sync via OnServerGroupCreated instead.
            case result.syncCursor of
                Just _ ->
                    triggerSync modelAfterLoad groupId

                Nothing ->
                    ( modelAfterLoad, Cmd.none )

        OnGroupEventsLoaded _ _ ->
            ( model, Cmd.none )

        -- Import / Export
        ExportGroup groupId ->
            case model.appState of
                Ready readyData ->
                    let
                        task : ConcurrentTask.ConcurrentTask Idb.Error ( List Event.Envelope, Maybe String )
                        task =
                            ConcurrentTask.map2 Tuple.pair
                                (Storage.loadGroupEvents readyData.db groupId)
                                (Storage.loadGroupKey readyData.db groupId)

                        ( pool, cmd ) =
                            ConcurrentTask.attempt
                                { pool = model.pool
                                , send = sendTask
                                , onComplete = OnExportDataLoaded groupId
                                }
                                task
                    in
                    ( { model | pool = pool }, cmd )

                _ ->
                    ( model, Cmd.none )

        OnExportDataLoaded groupId (ConcurrentTask.Success ( events, maybeKey )) ->
            case model.appState of
                Ready readyData ->
                    case Dict.get groupId readyData.groups of
                        Just summary ->
                            ( model, GroupExport.downloadGroup model.currentTime summary events maybeKey )

                        Nothing ->
                            ( model, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        OnExportDataLoaded _ _ ->
            addToast Toast.Error (T.toastExportError model.i18n) model

        HomeMsg homeMsg ->
            case model.appState of
                Ready readyData ->
                    let
                        existingIds : Set Group.Id
                        existingIds =
                            Dict.keys readyData.groups |> Set.fromList

                        ( homeModel, homeCmd, maybeOutput ) =
                            Page.Home.update model.i18n existingIds homeMsg model.homeModel
                    in
                    case maybeOutput of
                        Just (Page.Home.ImportReady exportData) ->
                            let
                                ( pool, cmd ) =
                                    ConcurrentTask.attempt
                                        { pool = model.pool
                                        , send = sendTask
                                        , onComplete = OnGroupImported exportData.group
                                        }
                                        (Storage.importGroup readyData.db exportData.group exportData.groupKey exportData.events)
                            in
                            ( { model | homeModel = homeModel, pool = pool }
                            , Cmd.batch [ Cmd.map HomeMsg homeCmd, cmd ]
                            )

                        Nothing ->
                            ( { model | homeModel = homeModel }
                            , Cmd.map HomeMsg homeCmd
                            )

                _ ->
                    ( model, Cmd.none )

        OnGroupImported summary (ConcurrentTask.Success _) ->
            case model.appState of
                Ready readyData ->
                    let
                        newRoute : Route
                        newRoute =
                            GroupRoute summary.id (Tab BalanceTab)

                        ( modelWithToast, toastCmd ) =
                            addToast Toast.Success
                                (T.toastImportSuccess model.i18n)
                                { model
                                    | appState = Ready { readyData | groups = Dict.insert summary.id summary readyData.groups }
                                    , loadedGroup = Nothing
                                    , homeModel = Page.Home.init
                                }
                    in
                    ( modelWithToast
                    , Cmd.batch [ Navigation.pushUrl navCmd (Route.toAppUrl newRoute), toastCmd ]
                    )

                _ ->
                    ( model, Cmd.none )

        OnGroupImported _ _ ->
            addToast Toast.Error (T.toastImportError model.i18n) model

        -- Server sync
        OnPbClientInitialized (ConcurrentTask.Success client) ->
            ( { model | pbClient = Just client }, Cmd.none )

        OnPbClientInitialized (ConcurrentTask.Error err) ->
            -- Server unavailable — continue in offline mode
            addToast Toast.Error ("Server: " ++ Server.errorToString (Server.PbError err)) model

        OnPbClientInitialized (ConcurrentTask.UnexpectedError _) ->
            ( model, Cmd.none )

        OnServerGroupCreated groupId (ConcurrentTask.Success _) ->
            -- Server group created; now sync (push initial events + pull + subscribe)
            triggerSync model groupId

        OnServerGroupCreated _ (ConcurrentTask.Error err) ->
            -- Server group creation failed — local group still works
            let
                _ =
                    Debug.log "OnServerGroupCreated error" err
            in
            addToast Toast.Error ("Sync: " ++ Server.errorToString err) model

        OnServerGroupCreated _ (ConcurrentTask.UnexpectedError _) ->
            ( model, Cmd.none )

        OnGroupSynced groupId pushedIds (ConcurrentTask.Success syncResult) ->
            case ( model.appState, model.loadedGroup ) of
                ( Ready readyData, Just loaded ) ->
                    if loaded.summary.id == groupId then
                        let
                            result : Submit.SyncApplyResult
                            result =
                                Submit.applySyncResult pushedIds syncResult loaded

                            ( taskPool, taskCmds ) =
                                ConcurrentTask.attempt
                                    { pool = model.pool
                                    , send = sendTask
                                    , onComplete = PostSyncTasksDone
                                    }
                                    (Submit.postSyncTasks readyData.db groupId model.pbClient result)

                            modelAfterSync : Model
                            modelAfterSync =
                                { model
                                    | loadedGroup = Just result.updatedGroup
                                    , pool = taskPool
                                    , syncInProgress = False
                                }
                                    |> initPagesIfNeeded model.route
                        in
                        -- If new events were added during sync, trigger follow-up
                        if Set.isEmpty result.updatedGroup.unpushedIds then
                            ( modelAfterSync, taskCmds )

                        else
                            let
                                ( followUpModel, followUpCmd ) =
                                    triggerSync modelAfterSync groupId
                            in
                            ( followUpModel, Cmd.batch [ taskCmds, followUpCmd ] )

                    else
                        ( { model | syncInProgress = False }, Cmd.none )

                _ ->
                    ( { model | syncInProgress = False }, Cmd.none )

        OnGroupSynced _ _ (ConcurrentTask.Error err) ->
            -- Sync failed — unpushedIds preserved, will retry on next sync
            addToast Toast.Error ("Sync: " ++ Server.errorToString err) { model | syncInProgress = False }

        OnGroupSynced _ _ (ConcurrentTask.UnexpectedError _) ->
            ( { model | syncInProgress = False }, Cmd.none )

        PostSyncTasksDone (ConcurrentTask.Success ()) ->
            ( model, Cmd.none )

        PostSyncTasksDone _ ->
            ( model, Cmd.none )

        OnPocketbaseEvent value ->
            case model.loadedGroup of
                Just loaded ->
                    case Json.Decode.decodeValue PocketBase.Realtime.decodeEvent value of
                        Ok ( _, PocketBase.Realtime.Created record ) ->
                            handleRealtimeRecord loaded record model

                        _ ->
                            ( model, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        ClipboardCopied ->
            addToast Toast.Success (T.toastCopied model.i18n) model

        DismissToast toastId ->
            ( { model | toastModel = Toast.dismiss toastId model.toastModel }
            , Cmd.none
            )


submitContext : (ConcurrentTask.Response Idb.Error Event.Envelope -> Msg) -> Model -> Storage.InitData -> Maybe (Submit.Context Msg)
submitContext onComplete model readyData =
    readyData.identity
        |> Maybe.map
            (\identity ->
                { pool = model.pool
                , sendTask = sendTask
                , onComplete = onComplete
                , randomSeed = model.randomSeed
                , uuidState = model.uuidState
                , currentTime = model.currentTime
                , db = readyData.db
                , identity = identity
                }
            )


{-| Get the current user's identity public key hash, or empty string.
-}
getIdentity : Model -> String
getIdentity model =
    case model.appState of
        Ready readyData ->
            readyData.identity
                |> Maybe.map .publicKeyHash
                |> Maybe.withDefault ""

        _ ->
            ""


{-| Trigger a server sync (auth + push unpushed + pull) for the given group.
Skips if a sync is already in progress.
-}
triggerSync : Model -> Group.Id -> ( Model, Cmd Msg )
triggerSync model groupId =
    if model.syncInProgress then
        ( model, Cmd.none )

    else
        case ( model.pbClient, model.loadedGroup ) of
            ( Just client, Just loaded ) ->
                if loaded.summary.id == groupId then
                    let
                        ctx : Server.ServerContext
                        ctx =
                            { client = client, groupId = groupId, groupKey = loaded.groupKey }

                        -- Snapshot the IDs being pushed (to diff later in OnGroupSynced)
                        pushedIds : Set String
                        pushedIds =
                            loaded.unpushedIds

                        -- Collect unpushed events from the loaded event list
                        unpushedEvents : List Event.Envelope
                        unpushedEvents =
                            List.filter (\e -> Set.member e.id pushedIds) loaded.events
                                |> List.reverse

                        syncTask : ConcurrentTask.ConcurrentTask Server.Error Server.SyncResult
                        syncTask =
                            Server.authenticate client { groupId = groupId, groupKey = loaded.groupKey }
                                |> ConcurrentTask.andThen
                                    (\() ->
                                        Server.syncGroup ctx
                                            (getIdentity model)
                                            { unpushedEvents = unpushedEvents
                                            , pullCursor = loaded.syncCursor
                                            }
                                    )

                        ( pool, cmd ) =
                            ConcurrentTask.attempt
                                { pool = model.pool
                                , send = sendTask
                                , onComplete = OnGroupSynced groupId pushedIds
                                }
                                syncTask
                    in
                    ( { model | pool = pool, syncInProgress = True }, cmd )

                else
                    ( model, Cmd.none )

            _ ->
                ( model, Cmd.none )


{-| Handle an incoming realtime event record.
-}
handleRealtimeRecord : LoadedGroup -> Json.Decode.Value -> Model -> ( Model, Cmd Msg )
handleRealtimeRecord loaded record model =
    case Json.Decode.decodeValue Server.realtimeEventDecoder record of
        Ok serverEvt ->
            if serverEvt.groupId == loaded.summary.id then
                case Json.Decode.decodeString Symmetric.encryptedDataDecoder serverEvt.eventData of
                    Ok _ ->
                        -- We need to decrypt async, but for now just trigger a pull
                        triggerSync model loaded.summary.id

                    Err _ ->
                        ( model, Cmd.none )

            else
                ( model, Cmd.none )

        Err _ ->
            ( model, Cmd.none )


{-| Add an event ID to the in-memory unpushed set of the loaded group.
-}
addUnpushedIdToModel : String -> Model -> Model
addUnpushedIdToModel eventId model =
    case model.loadedGroup of
        Just loaded ->
            { model
                | loadedGroup =
                    Just { loaded | unpushedIds = Set.insert eventId loaded.unpushedIds }
            }

        Nothing ->
            model


applySubmitResult : Model -> ( Submit.State Msg, Cmd Msg ) -> ( Model, Cmd Msg )
applySubmitResult model ( state, cmd ) =
    ( { model
        | pool = state.pool
        , randomSeed = state.randomSeed
        , uuidState = state.uuidState
      }
    , cmd
    )


submitEntryAction : Model -> (Submit.Context Msg -> LoadedGroup -> ( Submit.State Msg, Cmd Msg )) -> ( Model, Cmd Msg )
submitEntryAction model action =
    case ( model.appState, model.loadedGroup ) of
        ( Ready readyData, Just loaded ) ->
            case submitContext (OnEntryActionSaved loaded.summary.id) model readyData of
                Just ctx ->
                    applySubmitResult model (action ctx loaded)

                Nothing ->
                    ( model, Cmd.none )

        _ ->
            ( model, Cmd.none )


submitNewGroup : Model -> Storage.InitData -> Form.NewGroup.Output -> ( Model, Cmd Msg )
submitNewGroup model readyData output =
    case submitContext (OnEntrySaved "") model readyData of
        Just ctx ->
            -- newGroup takes its own onComplete (different response type)
            applySubmitResult model (Submit.newGroup ctx OnGroupCreated output)

        Nothing ->
            ( model, Cmd.none )


submitNewEntry : Model -> Storage.InitData -> LoadedGroup -> Page.NewEntry.Output -> ( Model, Cmd Msg )
submitNewEntry model readyData loaded output =
    case submitContext (OnEntrySaved loaded.summary.id) model readyData of
        Just ctx ->
            applySubmitResult model (Submit.newEntry ctx loaded output)

        Nothing ->
            ( model, Cmd.none )


submitEditEntry : Model -> Storage.InitData -> LoadedGroup -> Entry.Id -> Page.NewEntry.Output -> ( Model, Cmd Msg )
submitEditEntry model readyData loaded originalEntryId output =
    case submitContext (OnEntrySaved loaded.summary.id) model readyData of
        Just ctx ->
            Submit.editEntry ctx loaded originalEntryId output
                |> Maybe.map (applySubmitResult model)
                |> Maybe.withDefault ( model, Cmd.none )

        Nothing ->
            ( model, Cmd.none )


initPagesIfNeeded : Route -> Model -> Model
initPagesIfNeeded route model =
    case ( route, model.appState, model.loadedGroup ) of
        ( GroupRoute _ NewEntry, Ready readyData, Just loaded ) ->
            let
                config : Page.NewEntry.Config
                config =
                    Submit.entryFormConfig readyData loaded model.currentTime
            in
            case model.pendingTransfer of
                Just payData ->
                    { model
                        | newEntryModel = Page.NewEntry.initTransfer config payData
                        , pendingTransfer = Nothing
                    }

                Nothing ->
                    { model
                        | newEntryModel = Page.NewEntry.init config
                    }

        ( GroupRoute _ (EntryDetail _), _, _ ) ->
            { model | entryDetailModel = Page.EntryDetail.init }

        ( GroupRoute _ (EditEntry entryId), Ready readyData, Just loaded ) ->
            case Dict.get entryId loaded.groupState.entries of
                Just entryState ->
                    { model
                        | newEntryModel =
                            Page.NewEntry.initFromEntry
                                (Submit.entryFormConfig readyData loaded model.currentTime)
                                entryState.currentVersion
                    }

                Nothing ->
                    model

        ( GroupRoute _ (MemberDetail memberId), _, Just loaded ) ->
            case Dict.get memberId loaded.groupState.members of
                Just memberState ->
                    { model | memberDetailModel = Page.MemberDetail.init memberState }

                Nothing ->
                    model

        ( GroupRoute _ (EditMemberMetadata memberId), _, Just loaded ) ->
            case Dict.get memberId loaded.groupState.members of
                Just memberState ->
                    { model
                        | editMemberMetadataModel =
                            Page.EditMemberMetadata.init memberState.rootId memberState.name memberState.metadata
                    }

                Nothing ->
                    model

        ( GroupRoute _ EditGroupMetadata, _, Just loaded ) ->
            { model | editGroupMetadataModel = Page.EditGroupMetadata.init loaded.groupState.groupMeta }

        _ ->
            model


ensureGroupLoaded : Model -> Route -> ( Model, Cmd Msg )
ensureGroupLoaded model route =
    case route of
        GroupRoute groupId _ ->
            case model.loadedGroup of
                Just loaded ->
                    if loaded.summary.id == groupId then
                        ( model, Cmd.none )

                    else
                        loadGroup model groupId

                Nothing ->
                    loadGroup model groupId

        _ ->
            ( model, Cmd.none )


loadGroup : Model -> Group.Id -> ( Model, Cmd Msg )
loadGroup model groupId =
    case model.appState of
        Ready readyData ->
            let
                task : ConcurrentTask.ConcurrentTask Idb.Error { events : List Event.Envelope, groupKey : Symmetric.Key, syncCursor : Maybe String, unpushedIds : Set String }
                task =
                    ConcurrentTask.map4 (\events key cursor unpushed -> { events = events, groupKey = key, syncCursor = cursor, unpushedIds = unpushed })
                        (Storage.loadGroupEvents readyData.db groupId)
                        (Storage.loadGroupKeyRequired readyData.db groupId)
                        (Storage.loadSyncCursor readyData.db groupId)
                        (Storage.loadUnpushedIds readyData.db groupId)

                ( pool, cmd ) =
                    ConcurrentTask.attempt
                        { pool = model.pool
                        , send = sendTask
                        , onComplete = OnGroupEventsLoaded groupId
                        }
                        task
            in
            ( { model | pool = pool, loadedGroup = Nothing }, cmd )

        _ ->
            ( model, Cmd.none )


handleMemberDetailOutput : Model -> Storage.InitData -> LoadedGroup -> Page.MemberDetail.Output -> ( Model, Cmd Msg )
handleMemberDetailOutput model readyData loaded output =
    let
        submit : Event.Payload -> ( Model, Cmd Msg )
        submit =
            submitEvent (OnMemberActionSaved loaded.summary.id) model readyData loaded
    in
    case output of
        Page.MemberDetail.RenameOutput data ->
            submit
                (Event.MemberRenamed
                    { rootId = data.memberId
                    , oldName = data.oldName
                    , newName = data.newName
                    }
                )

        Page.MemberDetail.RetireOutput memberId ->
            submit (Event.MemberRetired { rootId = memberId })

        Page.MemberDetail.UnretireOutput memberId ->
            submit (Event.MemberUnretired { rootId = memberId })

        Page.MemberDetail.NavigateToEditMetadata ->
            case model.route of
                GroupRoute groupId (MemberDetail memberId) ->
                    ( model
                    , Navigation.pushUrl navCmd (Route.toAppUrl (GroupRoute groupId (EditMemberMetadata memberId)))
                    )

                _ ->
                    ( model, Cmd.none )

        Page.MemberDetail.NavigateBack ->
            case model.route of
                GroupRoute groupId _ ->
                    ( model
                    , Navigation.pushUrl navCmd (Route.toAppUrl (GroupRoute groupId (Tab MembersTab)))
                    )

                _ ->
                    ( model, Cmd.none )


submitEvent : (ConcurrentTask.Response Idb.Error Event.Envelope -> Msg) -> Model -> Storage.InitData -> LoadedGroup -> Event.Payload -> ( Model, Cmd Msg )
submitEvent onComplete model readyData loaded payload =
    case submitContext onComplete model readyData of
        Just ctx ->
            applySubmitResult model (Submit.event ctx loaded payload)

        Nothing ->
            ( model, Cmd.none )


submitAddMember : Model -> Storage.InitData -> LoadedGroup -> Page.AddMember.Output -> ( Model, Cmd Msg )
submitAddMember model readyData loaded output =
    case submitContext (OnMemberActionSaved loaded.summary.id) model readyData of
        Just ctx ->
            applySubmitResult model (Submit.addMember ctx loaded output)

        Nothing ->
            ( model, Cmd.none )


submitMemberMetadata : Model -> Storage.InitData -> LoadedGroup -> Page.EditMemberMetadata.Output -> ( Model, Cmd Msg )
submitMemberMetadata model readyData loaded output =
    let
        ( modelAfterMeta, metaCmd ) =
            submitEvent (OnMemberActionSaved loaded.summary.id)
                model
                readyData
                loaded
                (Event.MemberMetadataUpdated
                    { rootId = output.memberId
                    , metadata = output.metadata
                    }
                )
    in
    if output.newName /= output.oldName then
        let
            ( modelAfterRename, renameCmd ) =
                submitEvent (OnMemberActionSaved loaded.summary.id)
                    modelAfterMeta
                    readyData
                    loaded
                    (Event.MemberRenamed
                        { rootId = output.memberId
                        , oldName = output.oldName
                        , newName = output.newName
                        }
                    )
        in
        ( modelAfterRename, Cmd.batch [ metaCmd, renameCmd ] )

    else
        ( modelAfterMeta, metaCmd )


submitGroupMetadata : Model -> Storage.InitData -> LoadedGroup -> Event.GroupMetadataChange -> ( Model, Cmd Msg )
submitGroupMetadata model readyData loaded change =
    submitEvent (OnGroupMetadataActionSaved loaded.summary.id)
        model
        readyData
        loaded
        (Event.GroupMetadataUpdated change)


{-| After a group metadata event is applied, sync the group name in the summary list and IndexedDB.
-}
syncGroupSummaryName : Group.Id -> Model -> ( Model, Cmd Msg )
syncGroupSummaryName groupId model =
    case ( model.loadedGroup, model.appState ) of
        ( Just loaded, Ready readyData ) ->
            let
                updatedSummary : GroupSummary
                updatedSummary =
                    { id = groupId
                    , name = loaded.groupState.groupMeta.name
                    , defaultCurrency = loaded.summary.defaultCurrency
                    }

                ( pool, cmd ) =
                    ConcurrentTask.attempt
                        { pool = model.pool
                        , send = sendTask
                        , onComplete = OnGroupSummarySaved
                        }
                        (Storage.saveGroupSummary readyData.db updatedSummary)
            in
            ( { model
                | appState = Ready { readyData | groups = Dict.insert groupId updatedSummary readyData.groups }
                , loadedGroup = Just { loaded | summary = updatedSummary }
                , pool = pool
              }
            , cmd
            )

        _ ->
            ( model, Cmd.none )


deleteGroup : Model -> Group.Id -> ( Model, Cmd Msg )
deleteGroup model groupId =
    case model.appState of
        Ready readyData ->
            let
                ( pool, cmd ) =
                    ConcurrentTask.attempt
                        { pool = model.pool
                        , send = sendTask
                        , onComplete = OnGroupRemoved groupId
                        }
                        (Storage.deleteGroup readyData.db groupId)
            in
            ( { model | pool = pool }, cmd )

        _ ->
            ( model, Cmd.none )


appendEventAndRecompute : Model -> Group.Id -> Event.Envelope -> Maybe Model
appendEventAndRecompute model groupId envelope =
    mapLoadedGroup
        (\loaded ->
            { loaded
                | events = envelope :: loaded.events
                , groupState = GroupState.applyEvents [ envelope ] loaded.groupState
            }
        )
        groupId
        model


applyLoadedGroup : Group.Id -> List Event.Envelope -> Symmetric.Key -> Maybe String -> Set String -> Model -> Maybe Model
applyLoadedGroup groupId events groupKey syncCursor unpushedIds model =
    case model.appState of
        Ready readyData ->
            Dict.get groupId readyData.groups
                |> Maybe.map (\summary -> Submit.initLoadedGroup events summary groupKey syncCursor unpushedIds)
                |> Maybe.map (\loaded -> { model | loadedGroup = Just loaded })

        _ ->
            Nothing


mapLoadedGroup : (LoadedGroup -> LoadedGroup) -> Group.Id -> Model -> Maybe Model
mapLoadedGroup f groupId model =
    case model.loadedGroup of
        Just loaded ->
            if loaded.summary.id == groupId then
                Just { model | loadedGroup = Just (f loaded) }

            else
                Nothing

        Nothing ->
            Nothing


applyRouteGuard : Maybe Identity -> Route -> ( Route, Cmd Msg )
applyRouteGuard identity route =
    case identity of
        Nothing ->
            case route of
                Setup ->
                    ( route, Cmd.none )

                About ->
                    ( route, Cmd.none )

                GroupRoute _ (Join _) ->
                    ( route, Cmd.none )

                _ ->
                    ( Setup, Navigation.replaceUrl navCmd (AppUrl.fromPath [ "setup" ]) )

        Just _ ->
            case route of
                Setup ->
                    ( Home, Navigation.replaceUrl navCmd (AppUrl.fromPath []) )

                _ ->
                    ( route, Cmd.none )


view : Model -> Html Msg
view model =
    Ui.layout Ui.default
        [ Ui.height Ui.fill
        , Ui.inFront (Toast.view model.toastModel)
        ]
        (viewPage model)


viewPage : Model -> Ui.Element Msg
viewPage model =
    case model.appState of
        Loading ->
            Page.Loading.view model.i18n

        InitError errorMsg ->
            UI.Shell.appShell
                { title = T.shellPartage model.i18n
                , headerExtra = Ui.none
                , content = Page.InitError.view errorMsg
                }

        Ready readyData ->
            viewReady model readyData


viewReady : Model -> Storage.InitData -> Ui.Element Msg
viewReady model readyData =
    let
        i18n : I18n
        i18n =
            model.i18n

        langSelector : Ui.Element Msg
        langSelector =
            UI.Components.languageSelector SwitchLanguage model.language

        shell : String -> Ui.Element Msg -> Ui.Element Msg
        shell title content =
            UI.Shell.appShell { title = title, headerExtra = langSelector, content = content }

        withGroup : Group.Id -> (LoadedGroup -> Ui.Element Msg) -> Ui.Element Msg
        withGroup groupId viewFn =
            viewWithLoadedGroup model groupId langSelector viewFn

        withGroupShell : Group.Id -> String -> (LoadedGroup -> Ui.Element Msg) -> Ui.Element Msg
        withGroupShell groupId title contentFn =
            withGroup groupId (\loaded -> shell title (contentFn loaded))
    in
    case model.route of
        Setup ->
            shell (T.shellPartage i18n)
                (Page.Setup.view i18n { onGenerate = GenerateIdentity, isGenerating = model.generatingIdentity })

        Home ->
            shell (T.shellPartage i18n)
                (Page.Home.view i18n
                    { onNavigate = NavigateTo
                    , onExport = ExportGroup
                    }
                    HomeMsg
                    model.homeModel
                    (Dict.values readyData.groups)
                )

        NewGroup ->
            shell (T.shellNewGroup i18n)
                (Page.NewGroup.view i18n NewGroupMsg model.newGroupModel)

        GroupRoute _ (Join _) ->
            shell (T.shellJoinGroup i18n)
                (Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ]
                    (Ui.text (T.joinGroupComingSoon i18n))
                )

        GroupRoute groupId (Tab tab) ->
            withGroup groupId (viewGroupTab model readyData langSelector groupId tab)

        GroupRoute groupId (EntryDetail entryId) ->
            withGroup groupId
                (\loaded ->
                    case Dict.get entryId loaded.groupState.entries of
                        Just entryState ->
                            shell (T.entryDetailTitle i18n)
                                (viewGroupEntryDetail model readyData loaded entryState)

                        Nothing ->
                            shell (T.shellPartage i18n) (Page.NotFound.view i18n)
                )

        GroupRoute groupId NewEntry ->
            withGroupShell groupId (T.shellNewEntry i18n) (viewGroupNewEntry model)

        GroupRoute groupId (EditEntry _) ->
            withGroupShell groupId (T.editEntryTitle i18n) (viewGroupEditEntry model)

        GroupRoute groupId (MemberDetail _) ->
            withGroupShell groupId (T.memberDetailTitle i18n) (viewGroupMemberDetail model readyData)

        GroupRoute groupId AddVirtualMember ->
            withGroupShell groupId
                (T.memberAddTitle i18n)
                (always (Page.AddMember.view i18n AddMemberMsg model.addMemberModel))

        GroupRoute groupId (EditMemberMetadata _) ->
            withGroupShell groupId
                (T.memberEditMetadataButton i18n)
                (always (Page.EditMemberMetadata.view i18n EditMemberMetadataMsg model.editMemberMetadataModel))

        GroupRoute groupId EditGroupMetadata ->
            withGroupShell groupId
                (T.groupSettingsTitle i18n)
                (always (Page.EditGroupMetadata.view i18n EditGroupMetadataMsg model.editGroupMetadataModel))

        About ->
            shell (T.shellPartage i18n) (Page.About.view i18n)

        NotFound ->
            shell (T.shellPartage i18n) (Page.NotFound.view i18n)


viewGroupTab : Model -> Storage.InitData -> Ui.Element Msg -> Group.Id -> GroupTab -> LoadedGroup -> Ui.Element Msg
viewGroupTab model readyData langSelector groupId tab loaded =
    let
        groupModel : Page.Group.Model
        groupModel =
            model.groupModel
    in
    Page.Group.view
        { i18n = model.i18n
        , onTabClick = SwitchTab
        , onNewEntry = NavigateTo (GroupRoute groupId NewEntry)
        , onEntryClick = \entryId -> NavigateTo (GroupRoute groupId (EntryDetail entryId))
        , onMemberClick = \memberId -> NavigateTo (GroupRoute groupId (MemberDetail memberId))
        , onAddMember = NavigateTo (GroupRoute groupId AddVirtualMember)
        , onEditGroupMetadata = NavigateTo (GroupRoute groupId EditGroupMetadata)
        , onSettleTransaction = SettleTransaction
        , onPayMember = PayMember
        , onSaveSettlementPreferences = SaveSettlementPreferences
        , currentUserRootId = Submit.currentUserRootId readyData loaded
        , entryDetailPath = \entryId -> Route.toPath (GroupRoute groupId (EntryDetail entryId))
        , groupDefaultCurrency = loaded.summary.defaultCurrency
        , today = Date.posixToDate model.currentTime
        , toMsg = GroupMsg
        }
        langSelector
        loaded.groupState
        { groupModel | activeTab = tab }


viewGroupNewEntry : Model -> LoadedGroup -> Ui.Element Msg
viewGroupNewEntry model loaded =
    Page.NewEntry.view model.i18n
        (GroupState.activeMembers loaded.groupState)
        NewEntryMsg
        model.newEntryModel


viewGroupEntryDetail : Model -> Storage.InitData -> LoadedGroup -> GroupState.EntryState -> Ui.Element Msg
viewGroupEntryDetail model readyData loaded entryState =
    Page.EntryDetail.view model.i18n
        { currentUserRootId = Submit.currentUserRootId readyData loaded
        , resolveName = GroupState.resolveMemberName loaded.groupState
        }
        EntryDetailMsg
        model.entryDetailModel
        entryState


viewGroupEditEntry : Model -> LoadedGroup -> Ui.Element Msg
viewGroupEditEntry model loaded =
    Page.NewEntry.view model.i18n
        (GroupState.activeMembers loaded.groupState)
        NewEntryMsg
        model.newEntryModel


viewGroupMemberDetail : Model -> Storage.InitData -> LoadedGroup -> Ui.Element Msg
viewGroupMemberDetail model readyData loaded =
    Page.MemberDetail.view model.i18n
        (Submit.currentUserRootId readyData loaded)
        MemberDetailMsg
        model.memberDetailModel


viewWithLoadedGroup : Model -> Group.Id -> Ui.Element Msg -> (LoadedGroup -> Ui.Element Msg) -> Ui.Element Msg
viewWithLoadedGroup model groupId langSelector viewFn =
    let
        loadingShell : Ui.Element Msg
        loadingShell =
            UI.Shell.appShell
                { title = T.shellPartage model.i18n
                , headerExtra = langSelector
                , content =
                    Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ]
                        (Ui.text (T.loadingGroup model.i18n))
                }
    in
    case model.loadedGroup of
        Just loaded ->
            if loaded.summary.id == groupId then
                viewFn loaded

            else
                loadingShell

        Nothing ->
            loadingShell
