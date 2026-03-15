port module Main exposing (AppState, Flags, Model, Msg, main)

import AppUrl
import Browser
import Compression
import ConcurrentTask exposing (ConcurrentTask)
import ConcurrentTaskExtra as Runner exposing (TaskRunner)
import Dict
import Domain.Date as Date
import Domain.Event as Event
import Domain.Group as Group
import Domain.GroupState as GroupState
import Domain.Member as Member
import Form.NewGroup
import GroupExport
import GroupOps
import Html exposing (Html)
import Html.Attributes
import Identity exposing (Identity)
import IndexedDb as Idb
import Json.Decode
import Json.Encode
import Maybe.Extra
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
import Process
import PushServer
import Pwa
import Random
import Route exposing (GroupTab(..), GroupView(..), Route(..))
import Server
import Set exposing (Set)
import Storage
import Task
import Time
import Translations as T exposing (I18n, Language(..))
import UI.Components
import UI.Shell
import UI.Theme as Theme
import UI.Toast as Toast
import UUID
import Ui
import Ui.Font
import Update
import Url
import UsageStats exposing (UsageStats)
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
    , runner : TaskRunner Msg
    , uuidState : UUID.V7State
    , randomSeed : Random.Seed
    , currentTime : Time.Posix
    , newGroupModel : Page.NewGroup.Model
    , groupModel : Page.Group.Model
    , homeModel : Page.Home.Model
    , aboutModel : Page.About.Model
    , toastModel : Toast.Model
    , joinGroupModel : Page.JoinGroup.Model
    , pendingJoinAction : Maybe { groupId : Group.Id, action : Page.JoinGroup.JoinAction, newMemberName : String }
    , serverUrl : String
    , origin : String
    , pbClient : Maybe PocketBase.Client
    , pendingServerCreations : Set Group.Id
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
    = NoOp
    | OnNavEvent Navigation.Event
    | NavigateTo Route
    | GoBack
    | SwitchLanguage Language
    | GenerateIdentity
    | OnTaskProgress ( TaskRunner Msg, Cmd Msg )
    | OnIdentityGenerated (ConcurrentTask.Response WebCrypto.Error Identity)
    | OnInitComplete (ConcurrentTask.Response Idb.Error Storage.InitData)
    | OnIdentitySaved (ConcurrentTask.Response Idb.Error ())
      -- Page form messages
    | NewGroupMsg Page.NewGroup.Msg
    | GroupMsg Page.Group.Msg
    | JoinGroupMsg Page.JoinGroup.Msg
      -- Join flow
    | OnJoinGroupFetched (ConcurrentTask.Response Server.Error Server.SyncResult)
    | OnJoinLocalGroupLoaded (ConcurrentTask.Response Idb.Error { events : List Event.Envelope, groupKey : Symmetric.Key, syncCursor : Maybe String, unpushedIds : Set.Set String })
    | OnJoinGroupSaved Group.Id Member.Id (ConcurrentTask.Response Idb.Error ())
      -- Form submission responses
    | OnGroupCreated (ConcurrentTask.Response Idb.Error Group.Summary)
      -- Import / Export
    | HomeMsg Page.Home.Msg
    | ExportGroup Group.Id
    | OnExportDataLoaded Group.Id (ConcurrentTask.Response Idb.Error ( List Event.Envelope, Maybe String ))
    | OnExportCompressed (ConcurrentTask.Response String ())
    | OnImportDecompressed (ConcurrentTask.Response String String)
    | OnGroupImported Group.Summary (ConcurrentTask.Response Idb.Error ())
      -- Server sync
    | OnPbClientInitialized (ConcurrentTask.Response PocketBase.Error PocketBase.Client)
    | OnServerGroupCreated Group.Id (ConcurrentTask.Response Server.Error ())
      -- About / Usage stats
    | AboutMsg Page.About.Msg
    | OnStorageCheckComplete (ConcurrentTask.Response Never ( Maybe UsageStats, UsageStats.StorageEstimate ))
    | OnAboutStatsReset (ConcurrentTask.Response Idb.Error ())
    | ScheduleStorageCheck
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
    | OnToggleNotifResult Group.Id (ConcurrentTask.Response PushServer.Error Bool)


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ Navigation.onEvent onNavEvent OnNavEvent
        , Runner.subscription model.runner
        , Page.Group.subscription model.groupModel |> Sub.map GroupMsg
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

        initStorage : ConcurrentTask Idb.Error Storage.InitData
        initStorage =
            Storage.open |> ConcurrentTask.andThen Storage.init

        storeNotificationTranslations : Storage.InitData -> ConcurrentTask Idb.Error Storage.InitData
        storeNotificationTranslations initData =
            Storage.saveNotificationTranslations initData.db
                (PushServer.notificationTranslations language)
                |> ConcurrentTask.map (\_ -> initData)

        ( runner, initCmds ) =
            ( Runner.initTaskRunner
                { pool = ConcurrentTask.pool
                , send = sendTask
                , receive = receiveTask
                , onProgress = OnTaskProgress
                }
            , Cmd.none
            )
                |> Runner.andRun OnInitComplete
                    (initStorage |> ConcurrentTask.andThen storeNotificationTranslations)
                |> Runner.andRun (PwaMsg << OnVapidKeyFetched)
                    PushServer.fetchVapidKey
    in
    ( { route = route
      , appState = Loading
      , generatingIdentity = False
      , i18n = T.init language
      , runner = runner
      , uuidState = uuidState
      , randomSeed = mainSeed
      , currentTime = Time.millisToPosix flags.currentTime
      , newGroupModel = Page.NewGroup.init
      , groupModel =
            Page.Group.init
                { pool = ConcurrentTask.withPoolId 1 ConcurrentTask.pool
                , send = sendTask
                , receive = receiveTask
                , randomSeed = groupSeedAfterV7
                , uuidState = groupUuidState
                }
      , homeModel = Page.Home.init
      , aboutModel = Page.About.init
      , joinGroupModel = Page.JoinGroup.init
      , pendingJoinAction = Nothing
      , toastModel = Toast.init
      , serverUrl = flags.serverUrl
      , origin = flags.origin
      , pbClient = Nothing
      , pendingServerCreations = Set.empty
      , isOnline = flags.isOnline
      , updateAvailable = False
      , installAvailable = False
      , notificationPermission = Nothing
      , pushSubscription = Nothing
      , vapidKey = Nothing
      }
    , initCmds
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
                        { db = readyData.db
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

                        Page.Group.RemoveGroup groupId memberRootId ->
                            case ( m.appState, m.pushSubscription ) of
                                ( Ready readyData, Just subscription ) ->
                                    let
                                        ( runner, unsubCmd ) =
                                            ( m.runner, Cmd.none )
                                                |> Runner.andRun (always NoOp)
                                                    (PushServer.unsubscribeFromGroup
                                                        { subscription = subscription
                                                        , groupId = groupId
                                                        , memberRootId = memberRootId
                                                        }
                                                    )
                                    in
                                    ( { m | runner = runner, appState = Ready { readyData | groups = Dict.remove groupId readyData.groups } }
                                    , unsubCmd :: cmds
                                    )

                                ( Ready readyData, Nothing ) ->
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

                        Page.Group.RequestServerGroupCreation groupId groupKey ->
                            attemptServerGroupCreation groupId (Just groupKey) m
                                |> Tuple.mapSecond (\attemptCmd -> attemptCmd :: cmds)
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
        NoOp ->
            ( model, Cmd.none )

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

        GoBack ->
            ( model, Navigation.back navCmd 1 )

        SwitchLanguage lang ->
            let
                updatedModel : Model
                updatedModel =
                    { model | i18n = T.load lang model.i18n }
            in
            case model.appState of
                -- Save the current language notifications translations to IndexedDB
                Ready readyData ->
                    ( model.runner, Cmd.none )
                        |> Runner.andRun (\_ -> NoOp)
                            (ConcurrentTask.map2 (\_ _ -> ())
                                (Storage.saveLanguage readyData.db (T.languageToString lang))
                                (Storage.saveNotificationTranslations readyData.db
                                    (PushServer.notificationTranslations lang)
                                )
                            )
                        |> Tuple.mapFirst (\r -> { updatedModel | runner = r })

                _ ->
                    ( updatedModel, Cmd.none )

        GenerateIdentity ->
            ( model.runner, Cmd.none )
                |> Runner.andRun OnIdentityGenerated Identity.generate
                |> Tuple.mapFirst (\r -> { model | runner = r, generatingIdentity = True })

        OnTaskProgress ( runner, cmd ) ->
            ( { model | runner = runner }, cmd )

        OnIdentityGenerated (ConcurrentTask.Success identity) ->
            case model.appState of
                Ready readyData ->
                    let
                        updatedReadyData : Storage.InitData
                        updatedReadyData =
                            { readyData | identity = Just identity }

                        ( guardedRoute, navCmd_ ) =
                            applyRouteGuard (Just identity) model.route

                        ( runner, taskCmd ) =
                            ( model.runner, Cmd.none )
                                |> Runner.andRun OnIdentitySaved
                                    (Storage.saveIdentity readyData.db identity)

                        modelWithIdentity : Model
                        modelWithIdentity =
                            { model
                                | appState = Ready updatedReadyData
                                , generatingIdentity = False
                                , route = guardedRoute
                                , runner = runner
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
                -- Override language if a saved preference exists
                modelWithLanguage : Model
                modelWithLanguage =
                    case readyData.savedLanguage |> Maybe.andThen T.languageFromString of
                        Just savedLang ->
                            { model | i18n = T.load savedLang model.i18n }

                        Nothing ->
                            model

                ( guardedRoute, guardCmd ) =
                    applyRouteGuard readyData.identity modelWithLanguage.route

                modelWithReadyData : Model
                modelWithReadyData =
                    { modelWithLanguage
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
                            ( modelWithReadyData, Cmd.none )

                        GroupRoute groupId groupView ->
                            case buildGroupConfig modelWithReadyData of
                                Just config ->
                                    Page.Group.handleNavigation config groupId groupView modelWithReadyData.groupModel
                                        |> Update.wrap GroupMsg (\gm -> { modelWithReadyData | groupModel = gm })

                                Nothing ->
                                    ( modelWithReadyData, Cmd.none )

                        _ ->
                            ( modelWithReadyData, Cmd.none )
            in
            ( modelAfterNav.runner, Cmd.batch [ guardCmd, navCmd_, rescheduleStorageCheckTomorrow ] )
                |> Runner.andRun OnPbClientInitialized
                    (PocketBase.init model.serverUrl)
                |> Runner.andRun OnStorageCheckComplete
                    (storageCheckTask readyData.db)
                |> Tuple.mapFirst (\r -> { modelAfterNav | runner = r })

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
                ( newGroupModel, pageCmd, maybeOutput ) =
                    Page.NewGroup.update subMsg model.newGroupModel

                modelWithForm : Model
                modelWithForm =
                    { model | newGroupModel = newGroupModel }
            in
            case ( maybeOutput, model.appState ) of
                ( Just output, Ready readyData ) ->
                    submitNewGroup modelWithForm readyData output

                _ ->
                    ( modelWithForm, Cmd.map NewGroupMsg pageCmd )

        OnGroupCreated (ConcurrentTask.Success summary) ->
            case model.appState of
                Ready readyData ->
                    let
                        modelWithGroup : Model
                        modelWithGroup =
                            { model
                                | appState = Ready { readyData | groups = Dict.insert summary.id summary readyData.groups }
                                , groupModel = Page.Group.resetLoadedGroup model.groupModel
                            }

                        ( modelAfterAttempt, serverCmd ) =
                            attemptServerGroupCreation summary.id Nothing modelWithGroup

                        newRoute : Route
                        newRoute =
                            GroupRoute summary.id (Tab EntriesTab)
                    in
                    ( modelAfterAttempt
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

                                memberId : Member.Id
                                memberId =
                                    case joinData.selectedAction of
                                        Page.JoinGroup.ClaimMember mId ->
                                            mId

                                        Page.JoinGroup.JoinAsNewMember ->
                                            Maybe.map .publicKeyHash readyData.identity
                                                |> Maybe.withDefault ""

                                summary : Group.Summary
                                summary =
                                    GroupState.summarize memberId groupId preview.groupState

                                updatedModel : Model
                                updatedModel =
                                    { model
                                        | joinGroupModel = joinModel
                                        , pendingJoinAction =
                                            Just
                                                { groupId = groupId
                                                , action = joinData.selectedAction
                                                , newMemberName = joinData.newMemberName
                                                }
                                    }
                            in
                            ( model.runner, Cmd.none )
                                |> Runner.andRun (OnJoinGroupSaved groupId memberId)
                                    (Storage.saveGroup readyData.db summary (Just (Symmetric.exportKey groupKey)) preview.events (Just preview.syncCursor))
                                |> Tuple.mapFirst (\r -> { updatedModel | runner = r })

                        _ ->
                            ( { model | joinGroupModel = joinModel }, Cmd.none )

                Nothing ->
                    ( { model | joinGroupModel = joinModel }, Cmd.none )

        OnJoinLocalGroupLoaded (ConcurrentTask.Success groupData) ->
            case model.appState of
                Ready readyData ->
                    let
                        groupState : GroupState.GroupState
                        groupState =
                            GroupState.applyEvents groupData.events GroupState.empty

                        identityHash : String
                        identityHash =
                            Maybe.map .publicKeyHash readyData.identity
                                |> Maybe.withDefault ""

                        isMember : Bool
                        isMember =
                            GroupState.resolveMemberRootId groupState identityHash /= Nothing
                    in
                    if isMember then
                        -- User is already a member: navigate to the group
                        case model.route of
                            GroupRoute groupId _ ->
                                let
                                    balanceRoute : Route
                                    balanceRoute =
                                        GroupRoute groupId (Tab BalanceTab)
                                in
                                addToast Toast.Success (T.toastAlreadyInGroup model.i18n) { model | route = balanceRoute }
                                    |> Update.addCmd (Navigation.replaceUrl navCmd (Route.toAppUrl balanceRoute))

                            _ ->
                                ( model, Cmd.none )

                    else
                        -- User is not a member: show join preview from local data
                        ( { model
                            | joinGroupModel =
                                Page.JoinGroup.showPreview
                                    { groupName = groupState.groupMeta.name
                                    , groupState = groupState
                                    , events = groupData.events
                                    , syncCursor = Maybe.withDefault "" groupData.syncCursor
                                    , selectedAction = Page.JoinGroup.defaultAction groupState
                                    , newMemberName = ""
                                    }
                          }
                        , Cmd.none
                        )

                _ ->
                    ( model, Cmd.none )

        OnJoinLocalGroupLoaded _ ->
            ( model, Cmd.none )

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
                        , selectedAction = Page.JoinGroup.defaultAction groupState
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

        OnJoinGroupSaved groupId memberId (ConcurrentTask.Success _) ->
            case ( model.appState, Page.JoinGroup.getPreview model.joinGroupModel ) of
                ( Ready readyData, Just preview ) ->
                    let
                        summary : Group.Summary
                        summary =
                            GroupState.summarize memberId groupId preview.groupState

                        balanceTabRoute : Route
                        balanceTabRoute =
                            GroupRoute groupId (Tab BalanceTab)
                    in
                    addToast Toast.Success
                        (T.toastJoinedGroup model.i18n)
                        { model
                            | appState = Ready { readyData | groups = Dict.insert groupId summary readyData.groups }
                            , groupModel = Page.Group.resetLoadedGroup model.groupModel
                        }
                        |> Update.addCmd (Navigation.pushUrl navCmd (Route.toAppUrl balanceTabRoute))

                _ ->
                    ( model, Cmd.none )

        OnJoinGroupSaved _ _ _ ->
            addToast Toast.Error (T.toastJoinError model.i18n) model

        -- Import / Export
        ExportGroup groupId ->
            case model.appState of
                Ready readyData ->
                    ( model.runner, Cmd.none )
                        |> Runner.andRun (OnExportDataLoaded groupId)
                            (ConcurrentTask.map2 Tuple.pair
                                (Storage.loadGroupEvents readyData.db groupId)
                                (Storage.loadGroupKey readyData.db groupId)
                            )
                        |> Tuple.mapFirst (\r -> { model | runner = r })

                _ ->
                    ( model, Cmd.none )

        OnExportDataLoaded groupId (ConcurrentTask.Success ( events, maybeKey )) ->
            case model.appState of
                Ready readyData ->
                    case Dict.get groupId readyData.groups of
                        Just summary ->
                            let
                                json : String
                                json =
                                    GroupExport.encodeExport model.currentTime summary events maybeKey

                                filename : String
                                filename =
                                    GroupExport.exportFilename summary
                            in
                            ( model.runner, Cmd.none )
                                |> Runner.andRun OnExportCompressed
                                    (Compression.compressAndDownload json filename)
                                |> Tuple.mapFirst (\r -> { model | runner = r })

                        Nothing ->
                            ( model, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        OnExportDataLoaded _ _ ->
            addToast Toast.Error (T.toastExportError model.i18n) model

        OnExportCompressed (ConcurrentTask.Error _) ->
            addToast Toast.Error (T.toastExportError model.i18n) model

        OnExportCompressed _ ->
            ( model, Cmd.none )

        HomeMsg homeMsg ->
            case model.appState of
                Ready _ ->
                    let
                        ( homeModel, homeCmd, maybeOutput ) =
                            Page.Home.update homeMsg model.homeModel

                        ( updatedModel, cmd ) =
                            ( { model | homeModel = homeModel }, Cmd.map HomeMsg homeCmd )
                    in
                    case maybeOutput of
                        Just (Page.Home.ImportFileLoaded base64) ->
                            ( updatedModel.runner, cmd )
                                |> Runner.andRun OnImportDecompressed
                                    (Compression.decompress base64)
                                |> Tuple.mapFirst (\r -> { updatedModel | runner = r })

                        Just (Page.Home.JoinLink url) ->
                            let
                                parsedUrl : Maybe Url.Url
                                parsedUrl =
                                    Url.fromString url
                                        |> Maybe.Extra.orElse (Url.fromString <| model.origin ++ url)
                            in
                            case Maybe.map (AppUrl.fromUrl >> Route.fromAppUrl) parsedUrl of
                                Just ((GroupRoute _ (Join _)) as route) ->
                                    ( updatedModel, Cmd.batch [ cmd, Navigation.pushUrl navCmd (Route.toAppUrl route) ] )

                                _ ->
                                    ( updatedModel, cmd )

                        Nothing ->
                            ( updatedModel, cmd )

                _ ->
                    ( model, Cmd.none )

        OnImportDecompressed (ConcurrentTask.Success jsonString) ->
            case model.appState of
                Ready readyData ->
                    let
                        existingIds : Set.Set Group.Id
                        existingIds =
                            Dict.keys readyData.groups |> Set.fromList
                    in
                    case GroupExport.validateImport existingIds jsonString of
                        Err GroupExport.InvalidFile ->
                            ( { model | homeModel = Page.Home.setImportError (T.importErrorInvalidFile model.i18n) model.homeModel }
                            , Cmd.none
                            )

                        Err GroupExport.AlreadyExists ->
                            ( { model | homeModel = Page.Home.setImportError (T.importErrorAlreadyExists model.i18n) model.homeModel }
                            , Cmd.none
                            )

                        Ok exportData ->
                            ( model.runner, Cmd.none )
                                |> Runner.andRun (OnGroupImported exportData.group)
                                    (Storage.saveGroup readyData.db exportData.group exportData.groupKey exportData.events Nothing)
                                |> Tuple.mapFirst (\r -> { model | runner = r })

                _ ->
                    ( model, Cmd.none )

        OnImportDecompressed _ ->
            ( { model | homeModel = Page.Home.setImportError (T.importErrorInvalidFile model.i18n) model.homeModel }
            , Cmd.none
            )

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
                    -- Check if the currently loaded group needs server creation
                    case modelWithClient.groupModel.loadedGroup of
                        Just loaded ->
                            if loaded.syncCursor == Nothing then
                                attemptServerGroupCreation loaded.summary.id (Just loaded.groupKey) modelWithClient

                            else
                                ( modelWithClient, Cmd.none )

                        Nothing ->
                            ( modelWithClient, Cmd.none )

        OnPbClientInitialized (ConcurrentTask.Error err) ->
            -- Server unavailable — continue in offline mode
            addToast Toast.Error ("Server: " ++ Server.errorToString (Server.PbError err)) model

        OnPbClientInitialized (ConcurrentTask.UnexpectedError _) ->
            ( model, Cmd.none )

        OnServerGroupCreated groupId (ConcurrentTask.Success _) ->
            -- Server group created; now sync (push initial events + pull + subscribe)
            let
                cleanModel : Model
                cleanModel =
                    { model | pendingServerCreations = Set.remove groupId model.pendingServerCreations }
            in
            case buildGroupConfig cleanModel of
                Just config ->
                    Page.Group.triggerSync config groupId cleanModel.groupModel
                        |> Update.wrap GroupMsg (\gm -> { cleanModel | groupModel = gm })

                Nothing ->
                    ( cleanModel, Cmd.none )

        OnServerGroupCreated groupId (ConcurrentTask.Error err) ->
            -- Server group creation failed — local group still works
            let
                cleanModel : Model
                cleanModel =
                    { model | pendingServerCreations = Set.remove groupId model.pendingServerCreations }
            in
            addToast Toast.Error ("Sync: " ++ Server.errorToString err) cleanModel

        OnServerGroupCreated groupId (ConcurrentTask.UnexpectedError _) ->
            ( { model | pendingServerCreations = Set.remove groupId model.pendingServerCreations }, Cmd.none )

        ClipboardCopied ->
            addToast Toast.Success (T.toastCopied model.i18n) model

        DismissToast toastId ->
            ( { model | toastModel = Toast.dismiss toastId model.toastModel }
            , Cmd.none
            )

        -- About / Usage stats
        AboutMsg aboutMsg ->
            let
                ( aboutModel, maybeOutput ) =
                    Page.About.update aboutMsg model.aboutModel
            in
            case maybeOutput of
                Just Page.About.RequestResetStats ->
                    case model.appState of
                        Ready readyData ->
                            ( model.runner, Cmd.none )
                                |> Runner.andRun OnAboutStatsReset (Storage.resetUsageStats readyData.db)
                                |> Tuple.mapFirst (\r -> { model | aboutModel = aboutModel, runner = r })

                        _ ->
                            ( { model | aboutModel = aboutModel }, Cmd.none )

                Nothing ->
                    ( { model | aboutModel = aboutModel }, Cmd.none )

        OnStorageCheckComplete (ConcurrentTask.Success ( maybeStats, storageEstimate )) ->
            case model.appState of
                Ready readyData ->
                    let
                        stats : UsageStats
                        stats =
                            maybeStats |> Maybe.withDefault (UsageStats.defaultStats model.currentTime)

                        updatedStats : UsageStats
                        updatedStats =
                            UsageStats.updateStorageCost model.currentTime storageEstimate.usage stats

                        breakdown : UsageStats.CostBreakdown
                        breakdown =
                            UsageStats.calculateCosts model.currentTime updatedStats

                        trackingSince : String
                        trackingSince =
                            Date.toString (Date.posixToDate updatedStats.trackingStartDate)

                        ( aboutModel, _ ) =
                            Page.About.update (Page.About.statsLoaded breakdown trackingSince) model.aboutModel
                    in
                    -- If needs save, save usage stats to IndexedDB
                    if updatedStats /= stats || maybeStats == Nothing then
                        ( model.runner, Cmd.none )
                            |> Runner.andRun (\_ -> NoOp)
                                (Storage.saveUsageStats readyData.db updatedStats)
                            |> Tuple.mapFirst (\r -> { model | aboutModel = aboutModel, runner = r })

                    else
                        ( { model | aboutModel = aboutModel }, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        OnStorageCheckComplete _ ->
            ( model, Cmd.none )

        OnAboutStatsReset (ConcurrentTask.Success ()) ->
            case model.appState of
                Ready readyData ->
                    let
                        freshStats : UsageStats
                        freshStats =
                            UsageStats.defaultStats model.currentTime

                        breakdown : UsageStats.CostBreakdown
                        breakdown =
                            UsageStats.calculateCosts model.currentTime freshStats

                        trackingSince : String
                        trackingSince =
                            Date.toString (Date.posixToDate freshStats.trackingStartDate)

                        ( aboutModel, _ ) =
                            Page.About.update (Page.About.statsLoaded breakdown trackingSince) model.aboutModel
                    in
                    ( model.runner, Cmd.none )
                        |> Runner.andRun (\_ -> NoOp)
                            (Storage.saveUsageStats readyData.db freshStats)
                        |> Tuple.mapFirst (\r -> { model | aboutModel = aboutModel, runner = r })

                _ ->
                    ( model, Cmd.none )

        OnAboutStatsReset _ ->
            ( model, Cmd.none )

        ScheduleStorageCheck ->
            case model.appState of
                Ready readyData ->
                    ( model.runner, rescheduleStorageCheckTomorrow )
                        |> Runner.andRun OnStorageCheckComplete (storageCheckTask readyData.db)
                        |> Tuple.mapFirst (\r -> { model | runner = r })

                _ ->
                    ( model, rescheduleStorageCheckTomorrow )

        PwaMsg pwaMsg ->
            updatePwa pwaMsg model


storageCheckTask : Idb.Db -> ConcurrentTask Never ( Maybe UsageStats, UsageStats.StorageEstimate )
storageCheckTask db =
    ConcurrentTask.map2 Tuple.pair
        (Storage.loadUsageStats db
            |> ConcurrentTask.onError (\_ -> ConcurrentTask.succeed Nothing)
        )
        UsageStats.estimateStorage


rescheduleStorageCheckTomorrow : Cmd Msg
rescheduleStorageCheckTomorrow =
    Process.sleep (24 * 60 * 60 * 1000)
        |> Task.perform (\_ -> ScheduleStorageCheck)


{-| Submit a new group using Main's own pool/seed/uuid.
-}
submitNewGroup : Model -> Storage.InitData -> Form.NewGroup.Output -> ( Model, Cmd Msg )
submitNewGroup model readyData output =
    case readyData.identity of
        Just identity ->
            let
                ctx : GroupOps.Context Msg
                ctx =
                    { runner = model.runner
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
                | runner = state.runner
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
                -- Group exists locally: load it to check membership
                ( model.runner, Cmd.none )
                    |> Runner.andRun OnJoinLocalGroupLoaded (Storage.loadGroup readyData.db groupId)
                    |> Tuple.mapFirst (\r -> { model | route = route, runner = r, joinGroupModel = Page.JoinGroup.init })

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

                                    ( runner, cmd ) =
                                        ( model.runner, Cmd.none )
                                            |> Runner.andRun OnJoinGroupFetched
                                                (Server.authenticateAndSync serverCtx
                                                    ""
                                                    { unpushedEvents = [], pullCursor = Nothing, notifyContext = Nothing }
                                                )
                                in
                                ( { model
                                    | route = route
                                    , runner = runner
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
                        ( model.runner, Cmd.none )
                            |> Runner.andRun OnIdentityGenerated Identity.generate
                            |> Tuple.mapFirst (\r -> { model | route = route, joinGroupModel = Page.JoinGroup.init, runner = r, generatingIdentity = True })

        _ ->
            ( { model | route = route }, Cmd.none )



-- PWA


updatePwa : PwaMsg -> Model -> ( Model, Cmd Msg )
updatePwa pwaMsg model =
    case pwaMsg of
        GotPwaEvent (Ok event) ->
            case event of
                Pwa.ConnectionChanged online ->
                    let
                        modelWithOnline : Model
                        modelWithOnline =
                            { model | isOnline = online }
                    in
                    if online then
                        case model.groupModel.loadedGroup of
                            Just loaded ->
                                if loaded.syncCursor == Nothing then
                                    attemptServerGroupCreation loaded.summary.id (Just loaded.groupKey) modelWithOnline

                                else
                                    ( modelWithOnline, Cmd.none )

                            Nothing ->
                                ( modelWithOnline, Cmd.none )

                    else
                        ( modelWithOnline, Cmd.none )

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

                Pwa.NotificationClicked data ->
                    case Json.Decode.decodeValue (Json.Decode.field "url" Json.Decode.string) data of
                        Ok url ->
                            case Url.fromString (model.origin ++ url) of
                                Just parsedUrl ->
                                    let
                                        route : Route
                                        route =
                                            Route.fromAppUrl (AppUrl.fromUrl parsedUrl)
                                    in
                                    ( model, Navigation.pushUrl navCmd (Route.toAppUrl route) )

                                Nothing ->
                                    ( model, Cmd.none )

                        Err _ ->
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
                            ( model.runner, Cmd.none )
                                |> Runner.andRun (PwaMsg << OnToggleNotifResult groupId)
                                    (PushServer.toggleGroupNotification
                                        { db = readyData.db
                                        , summary = summary
                                        , subscription = subscription
                                        , memberRootId = memberRootId
                                        }
                                    )
                                |> Tuple.mapFirst (\r -> { model | runner = r })

                        _ ->
                            ( model, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        OnToggleNotifResult groupId (ConcurrentTask.Success isSubscribed) ->
            case model.appState of
                Ready readyData ->
                    case Dict.get groupId readyData.groups of
                        Just summary ->
                            let
                                updatedSummary : Group.Summary
                                updatedSummary =
                                    { summary | isSubscribed = isSubscribed }
                            in
                            ( { model
                                | appState = Ready { readyData | groups = Dict.insert groupId updatedSummary readyData.groups }
                                , groupModel = Page.Group.updateLoadedSummary updatedSummary model.groupModel
                              }
                            , Cmd.none
                            )

                        Nothing ->
                            ( model, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        OnToggleNotifResult _ _ ->
            addToast Toast.Error (T.toastPushError model.i18n) model



-- VIEW


view : Model -> Html Msg
view model =
    let
        pageResult : Page.Group.ViewResult Msg
        pageResult =
            viewPage model

        innerAppArea : List (Ui.Attribute Msg)
        innerAppArea =
            [ Ui.centerX
            , Ui.widthMax Theme.contentMaxWidth
            , Ui.width Ui.fill
            , Ui.paddingWith
                { top = 0
                , bottom = 0
                , left = Theme.spacing.xl
                , right = Theme.spacing.xl
                }
            ]

        overlayAttr : Ui.Attribute Msg
        overlayAttr =
            case pageResult.overlay of
                Just overlay ->
                    Ui.inFront <|
                        Ui.el (Ui.alignBottom :: innerAppArea) overlay

                Nothing ->
                    Ui.noAttr

        toasts : Ui.Attribute Msg
        toasts =
            Ui.inFront <|
                Ui.el (Ui.alignBottom :: innerAppArea)
                    (Toast.view model.toastModel)
    in
    Ui.layout Ui.default
        [ Ui.background Theme.base.bg
        , Theme.fontFamily
        , Ui.Font.color Theme.base.text
        , Ui.Font.size Theme.font.md
        , overlayAttr
        , toasts
        ]
        (Ui.el [ Ui.background Theme.base.bg ]
            (Ui.column
                [ Ui.widthMax Theme.contentMaxWidth
                , Ui.centerX
                , Ui.htmlAttribute (Html.Attributes.style "min-height" "100vh")
                , Ui.paddingWith
                    { top = Theme.spacing.md
                    , bottom = 0
                    , left = Theme.spacing.xl
                    , right = Theme.spacing.xl
                    }
                ]
                [ viewPwaBanners model, pageResult.content ]
            )
        )


viewPwaBanners : Model -> Ui.Element Msg
viewPwaBanners model =
    UI.Components.pwaBanners model.i18n
        { isOnline = model.isOnline
        , updateAvailable = model.updateAvailable
        , installAvailable = model.installAvailable
        , onUpdate = PwaMsg AcceptUpdate
        , onInstall = PwaMsg RequestInstall
        , onDismissInstall = PwaMsg DismissInstallBanner
        }


viewPage : Model -> Page.Group.ViewResult Msg
viewPage model =
    let
        noOverlay : Ui.Element Msg -> Page.Group.ViewResult Msg
        noOverlay content =
            { content = content, overlay = Nothing }
    in
    case model.appState of
        Loading ->
            noOverlay (Page.Loading.view model.i18n)

        InitError errorMsg ->
            noOverlay <|
                UI.Shell.pageShell { title = T.shellPartage model.i18n, onBack = NavigateTo Home }
                    (Page.InitError.view model.i18n errorMsg)

        Ready readyData ->
            viewReady model readyData


viewReady : Model -> Storage.InitData -> Page.Group.ViewResult Msg
viewReady model readyData =
    let
        i18n : I18n
        i18n =
            model.i18n

        noOverlay : Ui.Element Msg -> Page.Group.ViewResult Msg
        noOverlay content =
            { content = content, overlay = Nothing }
    in
    case model.route of
        Setup ->
            noOverlay <|
                UI.Shell.pageShell { title = T.shellPartage i18n, onBack = NavigateTo Home }
                    (Page.Setup.view i18n { onGenerate = GenerateIdentity, isGenerating = model.generatingIdentity })

        Home ->
            noOverlay <|
                Page.Home.view i18n
                    { onNavigate = NavigateTo
                    , onExport = ExportGroup
                    , notificationPermission = model.notificationPermission
                    , pushActive = pushIsActive model
                    , onEnableNotifications = PwaMsg EnableNotifications
                    }
                    HomeMsg
                    model.homeModel
                    (Dict.values readyData.groups)

        NewGroup ->
            noOverlay <|
                UI.Shell.pageShell { title = T.shellNewGroup i18n, onBack = GoBack }
                    (Page.NewGroup.view i18n NewGroupMsg model.newGroupModel)

        GroupRoute _ (Join _) ->
            noOverlay <|
                UI.Shell.pageShell { title = T.shellJoinGroup i18n, onBack = GoBack }
                    (Ui.map JoinGroupMsg (Page.JoinGroup.view i18n model.joinGroupModel))

        GroupRoute groupId groupView ->
            Page.Group.view
                { i18n = i18n
                , toMsg = GroupMsg
                , onNavigateHome = NavigateTo Home
                , onGoBack = GoBack
                , today = Date.posixToDate model.currentTime
                , groupId = groupId
                , origin = model.origin
                , pushActive = pushIsActive model
                }
                groupView
                model.groupModel

        About ->
            noOverlay <|
                UI.Shell.pageShell { title = T.shellPartage i18n, onBack = NavigateTo Home }
                    (Page.About.view i18n
                        { onSwitchLanguage = SwitchLanguage
                        , toMsg = AboutMsg
                        }
                        model.aboutModel
                    )

        NotFound ->
            noOverlay <|
                UI.Shell.pageShell { title = T.shellPartage i18n, onBack = NavigateTo Home }
                    (Page.NotFound.view i18n)


pushIsActive : Model -> Bool
pushIsActive model =
    model.notificationPermission == Just Pwa.Granted && model.pushSubscription /= Nothing


{-| Create a group on the server. Called after sync has already failed,
indicating the group doesn't exist on the server yet.
No-op if pbClient is missing or creation already in progress.
-}
attemptServerGroupCreation : Group.Id -> Maybe Symmetric.Key -> Model -> ( Model, Cmd Msg )
attemptServerGroupCreation groupId maybeGroupKey model =
    case ( model.pbClient, model.appState ) of
        ( Just client, Ready readyData ) ->
            if Set.member groupId model.pendingServerCreations then
                ( model, Cmd.none )

            else
                let
                    loadKey : ConcurrentTask Server.Error Symmetric.Key
                    loadKey =
                        case maybeGroupKey of
                            Just key ->
                                ConcurrentTask.succeed key

                            Nothing ->
                                Storage.loadGroupKeyRequired readyData.db groupId
                                    |> ConcurrentTask.mapError (\_ -> Server.PbError (PocketBase.ServerError "Failed to load group key in IndexedDB"))

                    createGroup : Symmetric.Key -> ConcurrentTask Server.Error ()
                    createGroup key =
                        Server.createGroupOnServer client
                            { groupId = groupId
                            , groupKey = key
                            , createdBy = actorId
                            }

                    actorId : String
                    actorId =
                        readyData.identity
                            |> Maybe.map .publicKeyHash
                            |> Maybe.withDefault ""
                in
                ( model.runner, Cmd.none )
                    |> Runner.andRun (OnServerGroupCreated groupId)
                        (loadKey |> ConcurrentTask.andThen createGroup)
                    |> Tuple.mapFirst (\r -> { model | runner = r, pendingServerCreations = Set.insert groupId model.pendingServerCreations })

        _ ->
            ( model, Cmd.none )
