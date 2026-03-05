port module Main exposing (AppState, Flags, Model, Msg, main)

import AppUrl
import Browser
import ConcurrentTask
import Dict
import Domain.Date as Date
import Domain.Event as Event
import Domain.Group as Group
import Domain.GroupState as GroupState
import Form.NewGroup
import GroupExport
import GroupOps
import Html exposing (Html)
import Identity exposing (Identity)
import IndexedDb as Idb
import Json.Decode
import Json.Encode
import Navigation
import Page.About
import Page.Group
import Page.Home
import Page.InitError
import Page.JoinGroup
import Page.Loading
import Page.NewGroup
import Page.NotFound
import Page.Setup
import PocketBase
import PushServer
import Pwa
import Random
import Route exposing (GroupTab(..), GroupView(..), Route(..))
import Server
import Set
import Storage exposing (GroupSummary)
import Time
import Translations as T exposing (I18n, Language(..))
import UI.Components
import UI.Shell
import UI.Toast as Toast
import UUID
import Ui
import Update
import Url
import WebCrypto
import WebCrypto.Symmetric as Symmetric


port navCmd : Navigation.CommandPort msg


port onNavEvent : Navigation.EventPort msg


port sendTask : Json.Encode.Value -> Cmd msg


port receiveTask : (Json.Decode.Value -> msg) -> Sub msg


port onClipboardCopy : (() -> msg) -> Sub msg


port onPocketbaseEvent : (Json.Decode.Value -> msg) -> Sub msg


port pwaIn : (Json.Decode.Value -> msg) -> Sub msg


port pwaOut : Json.Encode.Value -> Cmd msg


type alias Flags =
    { initialUrl : String
    , language : String
    , randomSeed : List Int
    , currentTime : Int
    , serverUrl : String
    , origin : String
    , isOnline : Bool
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
    , groupModel : Page.Group.Model
    , homeModel : Page.Home.Model
    , toastModel : Toast.Model
    , joinGroupModel : Page.JoinGroup.Model
    , pendingJoinAction : Maybe { groupId : Group.Id, action : Page.JoinGroup.JoinAction, newMemberName : String }
    , serverUrl : String
    , origin : String
    , pbClient : Maybe PocketBase.Client
    , isOnline : Bool
    , updateAvailable : Bool
    , installAvailable : Bool
    , notificationPermission : Maybe Pwa.NotificationPermission
    , pushSubscription : Maybe Json.Encode.Value
    , vapidKey : Maybe String
    }


type AppState
    = Loading
    | Ready Storage.InitData
    | InitError String


type Msg
    = OnNavEvent Navigation.Event
    | NavigateTo Route
    | SwitchLanguage Language
    | GenerateIdentity
    | OnTaskProgress ( ConcurrentTask.Pool Msg, Cmd Msg )
    | OnIdentityGenerated (ConcurrentTask.Response WebCrypto.Error Identity)
    | OnInitComplete (ConcurrentTask.Response Idb.Error Storage.InitData)
    | OnIdentitySaved (ConcurrentTask.Response Idb.Error ())
      -- Page form messages
    | NewGroupMsg Page.NewGroup.Msg
    | GroupMsg Page.Group.Msg
    | JoinGroupMsg Page.JoinGroup.Msg
      -- Join flow
    | OnJoinGroupFetched (ConcurrentTask.Response Server.Error Server.SyncResult)
    | OnJoinGroupSaved Group.Id (ConcurrentTask.Response Idb.Error ())
      -- Form submission responses
    | OnGroupCreated (ConcurrentTask.Response Idb.Error GroupSummary)
      -- Import / Export
    | HomeMsg Page.Home.Msg
    | ExportGroup Group.Id
    | OnExportDataLoaded Group.Id (ConcurrentTask.Response Idb.Error ( List Event.Envelope, Maybe String ))
    | OnGroupImported Storage.GroupSummary (ConcurrentTask.Response Idb.Error ())
      -- Server sync
    | OnPbClientInitialized (ConcurrentTask.Response PocketBase.Error PocketBase.Client)
    | OnServerGroupCreated Group.Id (ConcurrentTask.Response Server.Error ())
      -- Toast notifications
    | ClipboardCopied
    | DismissToast Toast.ToastId
      -- PWA
    | PwaMsg PwaMsg


type PwaMsg
    = GotPwaEvent (Result Json.Decode.Error Pwa.Event)
    | AcceptUpdate
    | RequestInstall
    | DismissInstallBanner
    | EnableNotifications
    | OnVapidKeyFetched (ConcurrentTask.Response PushServer.Error String)
    | ToggleGroupNotification Group.Id String
    | OnToggleResult Group.Id (ConcurrentTask.Response PushServer.Error Bool)


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
        , Page.Group.onTaskProgress
            { send = sendTask
            , receive = receiveTask
            }
            model.groupModel
            |> Sub.map GroupMsg
        , onClipboardCopy (\() -> ClipboardCopied)
        , onPocketbaseEvent (GroupMsg << Page.Group.pocketbaseEventMsg)
        , pwaIn (PwaMsg << GotPwaEvent << Pwa.decodeEvent)
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

        -- Split seeds: Main keeps uuidState + mainSeed, Page.Group gets groupUuidState + groupSeedAfterV7
        ( uuidState, seedAfterV7 ) =
            Random.step UUID.initialV7State initialSeed

        ( groupSeed, mainSeed ) =
            Random.step Random.independentSeed seedAfterV7

        ( groupUuidState, groupSeedAfterV7 ) =
            Random.step UUID.initialV7State groupSeed

        currentTime : Time.Posix
        currentTime =
            Time.millisToPosix flags.currentTime

        groupPool : ConcurrentTask.Pool Page.Group.Msg
        groupPool =
            ConcurrentTask.pool |> ConcurrentTask.withPoolId 1

        ( pool0, initCmd ) =
            ConcurrentTask.attempt
                { pool = ConcurrentTask.pool
                , send = sendTask
                , onComplete = OnInitComplete
                }
                (Storage.open |> ConcurrentTask.andThen Storage.init)

        ( pool, vapidCmd ) =
            ConcurrentTask.attempt
                { pool = pool0
                , send = sendTask
                , onComplete = PwaMsg << OnVapidKeyFetched
                }
                PushServer.fetchVapidKey
    in
    ( { route = route
      , appState = Loading
      , generatingIdentity = False
      , i18n = i18n
      , language = language
      , pool = pool
      , uuidState = uuidState
      , randomSeed = mainSeed
      , currentTime = currentTime
      , newGroupModel = Page.NewGroup.init
      , groupModel =
            Page.Group.init
                { pool = groupPool
                , randomSeed = groupSeedAfterV7
                , uuidState = groupUuidState
                }
      , homeModel = Page.Home.init
      , joinGroupModel = Page.JoinGroup.init
      , pendingJoinAction = Nothing
      , toastModel = Toast.init
      , serverUrl = flags.serverUrl
      , origin = flags.origin
      , pbClient = Nothing
      , isOnline = flags.isOnline
      , updateAvailable = False
      , installAvailable = False
      , notificationPermission = Nothing
      , pushSubscription = Nothing
      , vapidKey = Nothing
      }
    , Cmd.batch [ initCmd, vapidCmd ]
    )


addToast : Toast.ToastLevel -> String -> Model -> ( Model, Cmd Msg )
addToast level message model =
    Toast.push DismissToast level message model.toastModel
        |> Tuple.mapFirst (\toast -> { model | toastModel = toast })


{-| Build a Page.Group.UpdateConfig from current model state.
Returns Nothing if app is not Ready or identity is not set.
-}
buildGroupConfig : Model -> Maybe Page.Group.UpdateConfig
buildGroupConfig model =
    case model.appState of
        Ready readyData ->
            readyData.identity
                |> Maybe.map
                    (\identity ->
                        { sendTask = sendTask
                        , db = readyData.db
                        , identity = identity
                        , pbClient = model.pbClient
                        , currentTime = model.currentTime
                        , route = model.route
                        , i18n = model.i18n
                        , groups = readyData.groups
                        }
                    )

        _ ->
            Nothing


{-| Process outputs from Page.Group.update by folding over the output list.
-}
processGroupOutputs : Model -> Cmd Page.Group.Msg -> List Page.Group.Output -> ( Model, Cmd Msg )
processGroupOutputs model groupCmd outputs =
    let
        ( finalModel, extraCmds ) =
            List.foldl
                (\output ( m, cmds ) ->
                    case output of
                        Page.Group.NavigateTo route ->
                            ( m, Navigation.pushUrl navCmd (Route.toAppUrl route) :: cmds )

                        Page.Group.ShowToast level message ->
                            let
                                ( modelWithToast, toastCmd ) =
                                    addToast level message m
                            in
                            ( modelWithToast, toastCmd :: cmds )

                        Page.Group.UpdateGroupSummary summary ->
                            case m.appState of
                                Ready readyData ->
                                    ( { m | appState = Ready { readyData | groups = Dict.insert summary.id summary readyData.groups } }
                                    , cmds
                                    )

                                _ ->
                                    ( m, cmds )

                        Page.Group.RemoveGroup groupId ->
                            case m.appState of
                                Ready readyData ->
                                    ( { m | appState = Ready { readyData | groups = Dict.remove groupId readyData.groups } }
                                    , cmds
                                    )

                                _ ->
                                    ( m, cmds )

                        Page.Group.UpdateCurrentTime time ->
                            ( { m | currentTime = time }, cmds )

                        Page.Group.ToggleGroupNotification groupId memberRootId ->
                            let
                                ( toggledModel, toggleCmd ) =
                                    updatePwa (ToggleGroupNotification groupId memberRootId) m
                            in
                            ( toggledModel, toggleCmd :: cmds )
                )
                ( model, [] )
                outputs
    in
    ( finalModel
    , Cmd.batch (Cmd.map GroupMsg groupCmd :: extraCmds)
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        OnNavEvent event ->
            let
                maybeIdentity : Maybe Identity
                maybeIdentity =
                    case model.appState of
                        Ready data ->
                            data.identity

                        _ ->
                            Nothing
            in
            case applyRouteGuard maybeIdentity (Route.fromAppUrl event.appUrl) of
                ( (GroupRoute groupId (Join key)) as route, guardCmd ) ->
                    handleJoinRoute model route groupId key maybeIdentity
                        |> Update.addCmd guardCmd

                ( (GroupRoute groupId groupView) as route, guardCmd ) ->
                    let
                        routedModel : Model
                        routedModel =
                            { model | route = route }
                    in
                    case buildGroupConfig routedModel of
                        Just config ->
                            Page.Group.handleNavigation config groupId groupView model.groupModel
                                |> Update.wrap GroupMsg (\gm -> { routedModel | groupModel = gm })
                                |> Update.addCmd guardCmd

                        Nothing ->
                            ( routedModel, guardCmd )

                ( route, guardCmd ) ->
                    ( { model | route = route }, guardCmd )

        NavigateTo route ->
            ( model, Navigation.pushUrl navCmd (Route.toAppUrl route) )

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

                        modelWithIdentity : Model
                        modelWithIdentity =
                            { model
                                | appState = Ready updatedReadyData
                                , generatingIdentity = False
                                , route = guardedRoute
                                , pool = pool
                                , groupModel = Page.Group.setIdentityHash identity.publicKeyHash model.groupModel
                            }
                    in
                    -- If on a Join route, re-trigger the join fetch now that we have identity
                    case model.route of
                        GroupRoute groupId (Join key) ->
                            handleJoinRoute modelWithIdentity model.route groupId key (Just identity)
                                |> Update.addCmd (Cmd.batch [ navCmd_, taskCmd ])

                        _ ->
                            ( modelWithIdentity, Cmd.batch [ navCmd_, taskCmd ] )

                _ ->
                    ( { model | generatingIdentity = False }, Cmd.none )

        OnIdentityGenerated _ ->
            ( { model | generatingIdentity = False }, Cmd.none )

        OnInitComplete (ConcurrentTask.Success readyData) ->
            let
                ( guardedRoute, guardCmd ) =
                    applyRouteGuard readyData.identity model.route

                modelWithData : Model
                modelWithData =
                    { model
                        | appState = Ready readyData
                        , route = guardedRoute
                        , groupModel =
                            case readyData.identity of
                                Just identity ->
                                    Page.Group.setIdentityHash identity.publicKeyHash model.groupModel

                                Nothing ->
                                    model.groupModel
                    }

                -- Handle group navigation if the initial route is a group route
                -- (Join routes are deferred until PB client is ready)
                ( modelAfterNav, navCmd_ ) =
                    case guardedRoute of
                        GroupRoute _ (Join _) ->
                            -- Join needs PB client, which isn't ready yet.
                            -- Will be handled in OnPbClientInitialized.
                            ( modelWithData, Cmd.none )

                        GroupRoute groupId groupView ->
                            case buildGroupConfig modelWithData of
                                Just config ->
                                    Page.Group.handleNavigation config groupId groupView modelWithData.groupModel
                                        |> Update.wrap GroupMsg (\gm -> { modelWithData | groupModel = gm })

                                Nothing ->
                                    ( modelWithData, Cmd.none )

                        _ ->
                            ( modelWithData, Cmd.none )

                ( poolAfterPb, pbCmd ) =
                    ConcurrentTask.attempt
                        { pool = modelAfterNav.pool
                        , send = sendTask
                        , onComplete = OnPbClientInitialized
                        }
                        (PocketBase.init model.serverUrl)
            in
            ( { modelAfterNav | pool = poolAfterPb }
            , Cmd.batch [ guardCmd, navCmd_, pbCmd ]
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
                                    let
                                        identityHash : String
                                        identityHash =
                                            readyData.identity
                                                |> Maybe.map .publicKeyHash
                                                |> Maybe.withDefault ""
                                    in
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
                                                        , createdBy = identityHash
                                                        }
                                                )
                                        )

                                Nothing ->
                                    ( model.pool, Cmd.none )
                    in
                    ( { model
                        | appState = Ready { readyData | groups = Dict.insert summary.id summary readyData.groups }
                        , groupModel = Page.Group.resetLoadedGroup model.groupModel
                        , pool = poolAfterServer
                      }
                    , Cmd.batch [ Navigation.pushUrl navCmd (Route.toAppUrl newRoute), serverCmd ]
                    )

                _ ->
                    ( model, Cmd.none )

        OnGroupCreated _ ->
            addToast Toast.Error (T.toastGroupCreateError model.i18n) model

        GroupMsg subMsg ->
            case buildGroupConfig model of
                Just config ->
                    let
                        ( groupModel, groupCmd, outputs ) =
                            Page.Group.update config subMsg model.groupModel

                        ( modelAfterOutputs, outputCmd ) =
                            processGroupOutputs { model | groupModel = groupModel } groupCmd outputs
                    in
                    -- Check for pending join action after group loads
                    case ( modelAfterOutputs.pendingJoinAction, modelAfterOutputs.groupModel.loadedGroup ) of
                        ( Just joinAction, Just _ ) ->
                            case buildGroupConfig modelAfterOutputs of
                                Just configAfter ->
                                    let
                                        ( joinGroupModel, joinCmd ) =
                                            Page.Group.submitJoinEvent configAfter
                                                { action = joinAction.action, newMemberName = joinAction.newMemberName }
                                                modelAfterOutputs.groupModel
                                    in
                                    ( { modelAfterOutputs | groupModel = joinGroupModel, pendingJoinAction = Nothing }
                                    , Cmd.batch [ outputCmd, Cmd.map GroupMsg joinCmd ]
                                    )

                                Nothing ->
                                    ( modelAfterOutputs, outputCmd )

                        _ ->
                            ( modelAfterOutputs, outputCmd )

                Nothing ->
                    ( model, Cmd.none )

        -- Join flow
        JoinGroupMsg subMsg ->
            let
                ( joinModel, maybeOutput ) =
                    Page.JoinGroup.update subMsg model.joinGroupModel
            in
            case maybeOutput of
                Just (Page.JoinGroup.JoinConfirmed joinData) ->
                    case ( model.appState, model.route, Page.JoinGroup.getPreview joinModel ) of
                        ( Ready readyData, GroupRoute groupId (Join key), Just preview ) ->
                            let
                                groupKey : Symmetric.Key
                                groupKey =
                                    Symmetric.importKey key

                                summary : GroupSummary
                                summary =
                                    { id = groupId
                                    , name = preview.groupName
                                    , defaultCurrency = preview.groupState.groupMeta.defaultCurrency
                                    , isSubscribed = False
                                    }

                                ( pool, cmd ) =
                                    ConcurrentTask.attempt
                                        { pool = model.pool
                                        , send = sendTask
                                        , onComplete = OnJoinGroupSaved groupId
                                        }
                                        (Storage.importGroup readyData.db summary (Just (Symmetric.exportKey groupKey)) preview.events (Just preview.syncCursor))
                            in
                            ( { model
                                | joinGroupModel = joinModel
                                , pool = pool
                                , pendingJoinAction =
                                    Just
                                        { groupId = groupId
                                        , action = joinData.selectedAction
                                        , newMemberName = joinData.newMemberName
                                        }
                              }
                            , cmd
                            )

                        _ ->
                            ( { model | joinGroupModel = joinModel }, Cmd.none )

                Nothing ->
                    ( { model | joinGroupModel = joinModel }, Cmd.none )

        OnJoinGroupFetched (ConcurrentTask.Success syncResult) ->
            let
                groupState : GroupState.GroupState
                groupState =
                    GroupState.applyEvents syncResult.pullResult.events GroupState.empty

                groupName : String
                groupName =
                    groupState.groupMeta.name
            in
            ( { model
                | joinGroupModel =
                    Page.JoinGroup.showPreview
                        { groupName = groupName
                        , groupState = groupState
                        , events = syncResult.pullResult.events
                        , syncCursor = syncResult.pullResult.cursor
                        , selectedAction = Page.JoinGroup.JoinAsNewMember
                        , newMemberName = ""
                        }
              }
            , Cmd.none
            )

        OnJoinGroupFetched (ConcurrentTask.Error err) ->
            ( { model | joinGroupModel = Page.JoinGroup.error (Server.errorToString err) }
            , Cmd.none
            )

        OnJoinGroupFetched (ConcurrentTask.UnexpectedError _) ->
            ( { model | joinGroupModel = Page.JoinGroup.error "Unexpected error" }
            , Cmd.none
            )

        OnJoinGroupSaved groupId (ConcurrentTask.Success _) ->
            case ( model.appState, Page.JoinGroup.getPreview model.joinGroupModel ) of
                ( Ready readyData, Just preview ) ->
                    let
                        summary : GroupSummary
                        summary =
                            { id = groupId
                            , name = preview.groupName
                            , defaultCurrency = preview.groupState.groupMeta.defaultCurrency
                            , isSubscribed = False
                            }

                        newRoute : Route
                        newRoute =
                            GroupRoute groupId (Tab BalanceTab)
                    in
                    addToast Toast.Success
                        (T.toastJoinedGroup model.i18n)
                        { model
                            | appState = Ready { readyData | groups = Dict.insert groupId summary readyData.groups }
                            , groupModel = Page.Group.resetLoadedGroup model.groupModel
                        }
                        |> Update.addCmd (Navigation.pushUrl navCmd (Route.toAppUrl newRoute))

                _ ->
                    ( model, Cmd.none )

        OnJoinGroupSaved _ _ ->
            addToast Toast.Error (T.toastJoinError model.i18n) model

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
                        existingIds : Set.Set Group.Id
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
                                        (Storage.importGroup readyData.db exportData.group exportData.groupKey exportData.events Nothing)
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
                    addToast Toast.Success
                        (T.toastImportSuccess model.i18n)
                        { model
                            | appState = Ready { readyData | groups = Dict.insert summary.id summary readyData.groups }
                            , groupModel = Page.Group.resetLoadedGroup model.groupModel
                            , homeModel = Page.Home.init
                        }
                        |> Update.addCmd (Navigation.pushUrl navCmd (Route.toAppUrl (GroupRoute summary.id (Tab BalanceTab))))

                _ ->
                    ( model, Cmd.none )

        OnGroupImported _ _ ->
            addToast Toast.Error (T.toastImportError model.i18n) model

        -- Server sync
        OnPbClientInitialized (ConcurrentTask.Success client) ->
            let
                modelWithClient : Model
                modelWithClient =
                    { model | pbClient = Just client }
            in
            -- If the initial route is a Join route, now that PB client is ready, trigger the join flow
            case model.route of
                GroupRoute groupId (Join key) ->
                    let
                        maybeIdentity : Maybe Identity
                        maybeIdentity =
                            case modelWithClient.appState of
                                Ready data ->
                                    data.identity

                                _ ->
                                    Nothing
                    in
                    handleJoinRoute modelWithClient model.route groupId key maybeIdentity

                _ ->
                    ( modelWithClient, Cmd.none )

        OnPbClientInitialized (ConcurrentTask.Error err) ->
            -- Server unavailable — continue in offline mode
            addToast Toast.Error ("Server: " ++ Server.errorToString (Server.PbError err)) model

        OnPbClientInitialized (ConcurrentTask.UnexpectedError _) ->
            ( model, Cmd.none )

        OnServerGroupCreated groupId (ConcurrentTask.Success _) ->
            -- Server group created; now sync (push initial events + pull + subscribe)
            case buildGroupConfig model of
                Just config ->
                    Page.Group.triggerSync config groupId model.groupModel
                        |> Update.wrap GroupMsg (\gm -> { model | groupModel = gm })

                Nothing ->
                    ( model, Cmd.none )

        OnServerGroupCreated _ (ConcurrentTask.Error err) ->
            -- Server group creation failed — local group still works
            let
                _ =
                    Debug.log "OnServerGroupCreated error" err
            in
            addToast Toast.Error ("Sync: " ++ Server.errorToString err) model

        OnServerGroupCreated _ (ConcurrentTask.UnexpectedError _) ->
            ( model, Cmd.none )

        ClipboardCopied ->
            addToast Toast.Success (T.toastCopied model.i18n) model

        DismissToast toastId ->
            ( { model | toastModel = Toast.dismiss toastId model.toastModel }
            , Cmd.none
            )

        PwaMsg pwaMsg ->
            updatePwa pwaMsg model


{-| Submit a new group using Main's own pool/seed/uuid.
-}
submitNewGroup : Model -> Storage.InitData -> Form.NewGroup.Output -> ( Model, Cmd Msg )
submitNewGroup model readyData output =
    case readyData.identity of
        Just identity ->
            let
                ctx : GroupOps.Context Msg
                ctx =
                    { pool = model.pool
                    , sendTask = sendTask
                    , onComplete = \_ -> OnGroupCreated (ConcurrentTask.UnexpectedError (ConcurrentTask.InternalError "unused"))
                    , randomSeed = model.randomSeed
                    , uuidState = model.uuidState
                    , currentTime = model.currentTime
                    , db = readyData.db
                    , identity = identity
                    }

                ( state, cmd ) =
                    GroupOps.newGroup ctx OnGroupCreated output
            in
            ( { model
                | pool = state.pool
                , randomSeed = state.randomSeed
                , uuidState = state.uuidState
              }
            , cmd
            )

        Nothing ->
            ( model, Cmd.none )


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


{-| Handle navigation to a Join route.
-}
handleJoinRoute : Model -> Route -> Group.Id -> String -> Maybe Identity -> ( Model, Cmd Msg )
handleJoinRoute model route groupId key maybeIdentity =
    case model.appState of
        Ready readyData ->
            if Dict.member groupId readyData.groups then
                -- Group already exists locally: navigate to it and trigger sync
                let
                    balanceRoute : Route
                    balanceRoute =
                        GroupRoute groupId (Tab BalanceTab)
                in
                addToast Toast.Success (T.toastAlreadyInGroup model.i18n) { model | route = balanceRoute }
                    |> Update.addCmd (Navigation.replaceUrl navCmd (Route.toAppUrl balanceRoute))

            else
                case maybeIdentity of
                    Just _ ->
                        case model.pbClient of
                            Just client ->
                                -- Has identity + server: fetch group data
                                let
                                    groupKey : Symmetric.Key
                                    groupKey =
                                        Symmetric.importKey key

                                    serverCtx : Server.ServerContext
                                    serverCtx =
                                        { client = client
                                        , groupId = groupId
                                        , groupKey = groupKey
                                        }

                                    ( pool, cmd ) =
                                        ConcurrentTask.attempt
                                            { pool = model.pool
                                            , send = sendTask
                                            , onComplete = OnJoinGroupFetched
                                            }
                                            (Server.authenticateAndSync serverCtx
                                                ""
                                                { unpushedEvents = [], pullCursor = Nothing, notifyContext = Nothing }
                                            )
                                in
                                ( { model
                                    | route = route
                                    , pool = pool
                                    , joinGroupModel = Page.JoinGroup.init
                                  }
                                , cmd
                                )

                            Nothing ->
                                -- Server not ready yet
                                ( { model
                                    | route = route
                                    , joinGroupModel = Page.JoinGroup.error "Server not available"
                                  }
                                , Cmd.none
                                )

                    Nothing ->
                        -- No identity: auto-generate one, then re-trigger join
                        let
                            ( pool, cmd ) =
                                ConcurrentTask.attempt
                                    { pool = model.pool
                                    , send = sendTask
                                    , onComplete = OnIdentityGenerated
                                    }
                                    Identity.generate
                        in
                        ( { model | route = route, joinGroupModel = Page.JoinGroup.init, pool = pool, generatingIdentity = True }
                        , cmd
                        )

        _ ->
            ( { model | route = route }, Cmd.none )



-- PWA


updatePwa : PwaMsg -> Model -> ( Model, Cmd Msg )
updatePwa pwaMsg model =
    case pwaMsg of
        GotPwaEvent (Ok event) ->
            case event of
                Pwa.ConnectionChanged online ->
                    ( { model | isOnline = online }, Cmd.none )

                Pwa.UpdateAvailable ->
                    ( { model | updateAvailable = True }, Cmd.none )

                Pwa.InstallAvailable ->
                    ( { model | installAvailable = True }, Cmd.none )

                Pwa.Installed ->
                    ( { model | installAvailable = False }, Cmd.none )

                Pwa.NotificationPermissionChanged permission ->
                    let
                        newModel : Model
                        newModel =
                            { model | notificationPermission = Just permission }
                    in
                    case ( permission, model.vapidKey ) of
                        ( Pwa.Granted, Just key ) ->
                            ( newModel, Pwa.subscribePush pwaOut key )

                        _ ->
                            ( newModel, Cmd.none )

                Pwa.PushSubscription subscription ->
                    ( { model | pushSubscription = Just subscription }, Cmd.none )

                Pwa.PushSubscriptionError _ ->
                    addToast Toast.Error (T.toastPushError model.i18n) model

                Pwa.PushUnsubscribed ->
                    ( { model | pushSubscription = Nothing }, Cmd.none )

                Pwa.NotificationClicked _ ->
                    ( model, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        GotPwaEvent (Err _) ->
            ( model, Cmd.none )

        AcceptUpdate ->
            ( model, Pwa.acceptUpdate pwaOut )

        RequestInstall ->
            ( { model | installAvailable = False }, Pwa.requestInstall pwaOut )

        DismissInstallBanner ->
            ( { model | installAvailable = False }, Cmd.none )

        EnableNotifications ->
            case model.notificationPermission of
                Just Pwa.Granted ->
                    -- Already granted, subscribe to push
                    case model.vapidKey of
                        Just key ->
                            ( model, Pwa.subscribePush pwaOut key )

                        Nothing ->
                            ( model, Cmd.none )

                _ ->
                    ( model, Pwa.requestNotificationPermission pwaOut )

        OnVapidKeyFetched (ConcurrentTask.Success key) ->
            let
                newModel : Model
                newModel =
                    { model | vapidKey = Just key }
            in
            case model.notificationPermission of
                Just Pwa.Granted ->
                    ( newModel, Pwa.subscribePush pwaOut key )

                _ ->
                    ( newModel, Cmd.none )

        OnVapidKeyFetched _ ->
            ( model, Cmd.none )

        ToggleGroupNotification groupId memberRootId ->
            case model.appState of
                Ready readyData ->
                    case ( Dict.get groupId readyData.groups, model.pushSubscription ) of
                        ( Just summary, Just subscription ) ->
                            let
                                ( pool, cmd ) =
                                    ConcurrentTask.attempt
                                        { pool = model.pool
                                        , send = sendTask
                                        , onComplete = PwaMsg << OnToggleResult groupId
                                        }
                                        (PushServer.toggleGroupNotification
                                            { db = readyData.db
                                            , summary = summary
                                            , subscription = subscription
                                            , memberRootId = memberRootId
                                            }
                                        )
                            in
                            ( { model | pool = pool }, cmd )

                        _ ->
                            ( model, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        OnToggleResult groupId (ConcurrentTask.Success isSubscribed) ->
            case model.appState of
                Ready readyData ->
                    case Dict.get groupId readyData.groups of
                        Just summary ->
                            let
                                updatedGroups : Dict.Dict Group.Id GroupSummary
                                updatedGroups =
                                    Dict.insert groupId { summary | isSubscribed = isSubscribed } readyData.groups
                            in
                            ( { model | appState = Ready { readyData | groups = updatedGroups } }, Cmd.none )

                        Nothing ->
                            ( model, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        OnToggleResult _ _ ->
            addToast Toast.Error (T.toastPushError model.i18n) model


viewPwaBanners : Model -> List (Ui.Element Msg)
viewPwaBanners model =
    UI.Components.pwaBanners model.i18n
        { isOnline = model.isOnline
        , updateAvailable = model.updateAvailable
        , installAvailable = model.installAvailable
        , onUpdate = PwaMsg AcceptUpdate
        , onInstall = PwaMsg RequestInstall
        , onDismissInstall = PwaMsg DismissInstallBanner
        }



-- VIEW


view : Model -> Html Msg
view model =
    Ui.layout Ui.default
        [ Ui.height Ui.fill
        , Ui.inFront (Toast.view model.toastModel)
        ]
        (Ui.column [ Ui.width Ui.fill, Ui.height Ui.fill ]
            (viewPwaBanners model ++ [ viewPage model ])
        )


viewPage : Model -> Ui.Element Msg
viewPage model =
    case model.appState of
        Loading ->
            Page.Loading.view model.i18n

        InitError errorMsg ->
            UI.Shell.appShell
                { title = T.shellPartage model.i18n
                , onTitleClick = NavigateTo Home
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
            UI.Shell.appShell { title = title, onTitleClick = NavigateTo Home, headerExtra = langSelector, content = content }
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
                    , notificationPermission = model.notificationPermission
                    , pushActive = pushIsActive model
                    , onEnableNotifications = PwaMsg EnableNotifications
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
                (Ui.map JoinGroupMsg (Page.JoinGroup.view i18n model.joinGroupModel))

        GroupRoute groupId groupView ->
            Page.Group.view
                { i18n = i18n
                , toMsg = GroupMsg
                , onNavigateHome = NavigateTo Home
                , today = Date.posixToDate model.currentTime
                , groupId = groupId
                , origin = model.origin
                , pushActive = pushIsActive model
                }
                langSelector
                groupView
                model.groupModel

        About ->
            shell (T.shellPartage i18n) (Page.About.view i18n)

        NotFound ->
            shell (T.shellPartage i18n) (Page.NotFound.view i18n)


pushIsActive : Model -> Bool
pushIsActive model =
    model.notificationPermission == Just Pwa.Granted && model.pushSubscription /= Nothing
