port module Main exposing (AppState, Flags, Model, Msg, main)

import AppUrl
import Browser
import Browser.Dom
import ConcurrentTask exposing (ConcurrentTask)
import ConcurrentTask.Http as Http
import Dict
import Domain.Compaction as Compaction
import Domain.Currency as Currency exposing (Currency)
import Domain.Date as Date
import Domain.Event as Event
import Domain.Group as Group
import Domain.GroupState as GroupState
import Domain.Member as Member
import Domain.TamperSignals exposing (TamperSignals)
import ErrorLog
import FeatherIcons
import Form.NewGroup
import GroupOps
import Html exposing (Html)
import Html.Attributes
import ImportExport
import IndexedDb as Idb
import Infra.ConcurrentTaskExtra as Runner exposing (TaskRunner)
import Infra.EventVerification as EventVerification
import Infra.ExchangeRate as ExchangeRate
import Infra.Identity as Identity exposing (Identity)
import Infra.PushServer as PushServer
import Infra.Server as Server
import Infra.Storage as Storage
import Infra.UsageStats as UsageStats exposing (UsageStats)
import Json.Decode
import Json.Encode
import Maybe.Extra
import Navigation
import Page.About
import Page.ErrorLog
import Page.Group
import Page.Home
import Page.ImportSplitwise
import Page.InitError
import Page.JoinGroup
import Page.Loading
import Page.NewGroup
import Page.NotFound
import Page.Welcome
import Process
import PwaState
import Random
import Route exposing (GroupTab(..), GroupView(..), Route(..))
import Set exposing (Set)
import SplitwiseImport
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
import Ui.Input
import Ui.Responsive
import Update
import Url
import WebCrypto
import WebCrypto.Symmetric as Symmetric


port navCmd : Navigation.CommandPort msg


port onNavEvent : Navigation.EventPort msg


port sendTask : Json.Encode.Value -> Cmd msg


port receiveTask : (Json.Decode.Value -> msg) -> Sub msg


port onClipboardCopy : (() -> msg) -> Sub msg


port onServerEvent : (Json.Decode.Value -> msg) -> Sub msg


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
    , installHint : String
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
    , timeZone : Time.Zone
    , newGroupModel : Page.NewGroup.Model
    , importSplitwiseModel : Maybe Page.ImportSplitwise.Model
    , groupModel : Page.Group.Model
    , homeModel : Page.Home.Model
    , aboutModel : Page.About.Model
    , toastModel : Toast.Model
    , joinGroupModel : Page.JoinGroup.Model
    , pendingJoinAction : Maybe { groupId : Group.Id, action : Page.JoinGroup.JoinAction, newMemberName : String }
    , serverUrl : String
    , origin : String
    , pendingServerCreations : Set Group.Id
    , pwaState : PwaState.Model
    , errorLog : ErrorLog.Model
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
    | GotTimeZone Time.Zone
    | OnIdentityGenerated (ConcurrentTask.Response WebCrypto.Error Identity)
    | OnInitComplete (ConcurrentTask.Response Idb.Error Storage.InitData)
    | OnIdentitySaved (ConcurrentTask.Response Idb.Error ())
      -- Page form messages
    | NewGroupMsg Page.NewGroup.Msg
    | ImportSplitwiseMsg Page.ImportSplitwise.Msg
    | OnImportSplitwiseRate Currency (ConcurrentTask.Response Http.Error Float)
    | GroupMsg Page.Group.Msg
    | JoinGroupMsg Page.JoinGroup.Msg
      -- Join flow
    | OnJoinGroupFetched (ConcurrentTask.Response Server.Error { syncResult : Server.SyncResult, manifestMismatch : Bool })
    | OnJoinLocalGroupLoaded (ConcurrentTask.Response Idb.Error { events : List Event.Envelope, groupKey : Symmetric.Key, syncCursor : Maybe Int, unpushedIds : Set.Set String, tamperSignals : TamperSignals, suspicionDismissals : Set.Set String })
    | OnJoinGroupSaved Group.Id Member.Id (ConcurrentTask.Response Idb.Error ())
      -- Form submission responses
    | OnGroupCreated (ConcurrentTask.Response Idb.Error Group.Summary)
      -- Import / Export
    | HomeMsg Page.Home.Msg
    | ImportExportMsg ImportExport.Msg
      -- Server sync
    | OnServerGroupCreated Group.Id (ConcurrentTask.Response Server.Error ())
      -- About / Usage stats
    | AboutMsg Page.About.Msg
    | OnStorageCheckComplete (ConcurrentTask.Response Never ( Maybe UsageStats, UsageStats.StorageEstimate, UsageStats.PersistedStatus ))
    | OnAboutStatsReset (ConcurrentTask.Response Idb.Error UsageStats.PersistedStatus)
    | OnSelfProfileSaved (ConcurrentTask.Response Idb.Error ())
    | ScheduleStorageCheck
    | ToggleDevMode
      -- Toast notifications
    | ClipboardCopied
    | DismissToast Toast.ToastId
      -- PWA
    | PwaStateMsg PwaState.Msg
    | OnToggleNotifResult Group.Id (ConcurrentTask.Response PushServer.Error Bool)


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ Navigation.onEvent onNavEvent OnNavEvent
        , Runner.subscription model.runner
        , Page.Group.subscription model.groupModel |> Sub.map GroupMsg
        , onClipboardCopy (\() -> ClipboardCopied)
        , onServerEvent (GroupMsg << Page.Group.serverEventMsg)
        , PwaState.subscription pwaIn PwaStateMsg
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
                |> PwaState.initTask PwaStateMsg
    in
    ( { route = route
      , appState = Loading
      , generatingIdentity = False
      , i18n = T.init language
      , runner = runner
      , uuidState = uuidState
      , randomSeed = mainSeed
      , currentTime = Time.millisToPosix flags.currentTime
      , timeZone = Time.utc
      , newGroupModel = Page.NewGroup.init
      , importSplitwiseModel = Nothing
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
      , pendingServerCreations = Set.empty
      , pwaState = PwaState.init { isOnline = flags.isOnline, installHint = flags.installHint }
      , errorLog = ErrorLog.empty
      }
    , Cmd.batch [ initCmds, Task.perform GotTimeZone Time.here ]
    )


addToast : Toast.ToastLevel -> String -> Model -> ( Model, Cmd Msg )
addToast level message model =
    Toast.push DismissToast level message model.toastModel
        |> Tuple.mapFirst (\toast -> { model | toastModel = toast })


logError : ErrorLog.Source -> ErrorLog.Severity -> String -> Model -> Model
logError source severity message model =
    { model | errorLog = ErrorLog.log model.currentTime source severity message model.errorLog }


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
                        , serverUrl = model.serverUrl
                        , currentTime = model.currentTime
                        , timeZone = model.timeZone
                        , route = model.route
                        , i18n = model.i18n
                        , groups = readyData.groups
                        , pendingServerCreations = model.pendingServerCreations
                        , selfProfile = readyData.selfProfile
                        , devMode = readyData.devMode
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
                            case ( m.appState, m.pwaState.pushSubscription ) of
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
                                    handleToggleGroupNotification groupId memberRootId m
                            in
                            ( toggledModel, toggleCmd :: cmds )

                        Page.Group.RequestServerGroupCreation groupId groupKey ->
                            attemptServerGroupCreation groupId (Just groupKey) m
                                |> Tuple.mapSecond (\attemptCmd -> attemptCmd :: cmds)

                        Page.Group.LogError source severity message ->
                            ( logError source severity message m, cmds )

                        Page.Group.SaveSelfProfile meta ->
                            case m.appState of
                                Ready readyData ->
                                    let
                                        ( runner, saveCmd ) =
                                            ( m.runner, Cmd.none )
                                                |> Runner.andRun OnSelfProfileSaved
                                                    (Storage.saveSelfProfile readyData.db meta)
                                    in
                                    ( { m
                                        | runner = runner
                                        , appState = Ready { readyData | selfProfile = meta }
                                      }
                                    , saveCmd :: cmds
                                    )

                                _ ->
                                    ( m, cmds )
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

        GotTimeZone zone ->
            ( { model | timeZone = zone }, Cmd.none )

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
                ( (GroupRoute groupId (Join invite)) as route, guardCmd ) ->
                    handleJoinRoute model route groupId invite.key maybeIdentity
                        |> Update.addCmd guardCmd
                        |> Update.addCmd (navScrollCmd route)

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
                                |> Update.addCmd (navScrollCmd route)

                        Nothing ->
                            ( routedModel, Cmd.batch [ guardCmd, navScrollCmd route ] )

                ( route, guardCmd ) ->
                    ( { model | route = route }, Cmd.batch [ guardCmd, navScrollCmd route ] )

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
                        GroupRoute groupId (Join invite) ->
                            handleJoinRoute modelWithIdentity model.route groupId invite.key (Just identity)
                                |> Update.addCmd (Cmd.batch [ navCmd_, taskCmd ])

                        Welcome ->
                            ( modelWithIdentity
                            , Cmd.batch [ navCmd_, taskCmd, Navigation.pushUrl navCmd (Route.toAppUrl Home) ]
                            )

                        _ ->
                            ( modelWithIdentity, Cmd.batch [ navCmd_, taskCmd ] )

                _ ->
                    ( { model | generatingIdentity = False }, Cmd.none )

        OnIdentityGenerated _ ->
            ( logError ErrorLog.IdentitySource
                ErrorLog.Err
                "Unexpected error generating identity"
                { model | generatingIdentity = False }
            , Cmd.none
            )

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
                ( modelAfterNav, navCmd_ ) =
                    case guardedRoute of
                        GroupRoute groupId (Join invite) ->
                            handleJoinRoute modelWithReadyData guardedRoute groupId invite.key readyData.identity

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
                |> Runner.andRun OnStorageCheckComplete
                    (storageCheckTask readyData.db)
                |> Tuple.mapFirst (\r -> { modelAfterNav | runner = r })

        OnInitComplete (ConcurrentTask.Error err) ->
            ( { model | appState = InitError (Storage.errorToString err) }, Cmd.none )

        OnInitComplete (ConcurrentTask.UnexpectedError _) ->
            ( logError ErrorLog.StorageSource
                ErrorLog.Err
                "Unexpected error during initialization"
                { model | appState = InitError "Unexpected error during initialization" }
            , Cmd.none
            )

        OnIdentitySaved (ConcurrentTask.Success _) ->
            ( model, Cmd.none )

        OnIdentitySaved _ ->
            ( logError ErrorLog.IdentitySource ErrorLog.Err "Unexpected error saving identity" model, Cmd.none )

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
                        |> requestPersistOnFirstGroup readyData.groups

                _ ->
                    ( model, Cmd.none )

        OnGroupCreated _ ->
            addToast Toast.Error (T.toastGroupCreateError model.i18n) model

        ImportSplitwiseMsg subMsg ->
            case ( model.importSplitwiseModel, model.appState ) of
                ( Just pageModel, Ready readyData ) ->
                    let
                        ( newPageModel, effect ) =
                            Page.ImportSplitwise.update subMsg pageModel
                    in
                    case effect of
                        Page.ImportSplitwise.NoEffect ->
                            ( { model | importSplitwiseModel = Just newPageModel }, Cmd.none )

                        Page.ImportSplitwise.RequestRate pair ->
                            ( model.runner, Cmd.none )
                                |> Runner.andRun (OnImportSplitwiseRate pair.base)
                                    (ExchangeRate.fetchRateCached readyData.db
                                        (Date.posixToDate model.timeZone model.currentTime)
                                        pair
                                    )
                                |> Tuple.mapFirst (\r -> { model | runner = r, importSplitwiseModel = Just newPageModel })

                        Page.ImportSplitwise.Done output ->
                            submitSplitwiseImport { model | importSplitwiseModel = Nothing } readyData output

                _ ->
                    ( model, Cmd.none )

        OnImportSplitwiseRate currency response ->
            case model.importSplitwiseModel of
                Just pageModel ->
                    let
                        result : Maybe Float
                        result =
                            case response of
                                ConcurrentTask.Success rate ->
                                    Just rate

                                _ ->
                                    Nothing
                    in
                    ( { model | importSplitwiseModel = Just (Page.ImportSplitwise.rateFetched currency result pageModel) }, Cmd.none )

                Nothing ->
                    ( model, Cmd.none )

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
                        ( Ready readyData, GroupRoute groupId (Join invite), Just preview ) ->
                            let
                                groupKey : Symmetric.Key
                                groupKey =
                                    Symmetric.importKey invite.key

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
                                    GroupState.summarize memberId groupId model.currentTime preview.groupState

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
                        -- User is already a member: navigate to the group and load it
                        case model.route of
                            GroupRoute groupId _ ->
                                let
                                    balanceTab : GroupView
                                    balanceTab =
                                        Tab BalanceTab

                                    balanceRoute : Route
                                    balanceRoute =
                                        GroupRoute groupId balanceTab

                                    ( toastedModel, toastCmd ) =
                                        addToast Toast.Success (T.toastAlreadyInGroup model.i18n) { model | route = balanceRoute }

                                    ( loadedModel, loadCmd ) =
                                        case buildGroupConfig toastedModel of
                                            Just config ->
                                                Page.Group.handleNavigation config groupId balanceTab toastedModel.groupModel
                                                    |> Update.wrap GroupMsg (\gm -> { toastedModel | groupModel = gm })

                                            Nothing ->
                                                ( toastedModel, Cmd.none )
                                in
                                ( loadedModel
                                , Cmd.batch
                                    [ toastCmd
                                    , loadCmd
                                    , Navigation.replaceUrl navCmd (Route.toAppUrl balanceRoute)
                                    ]
                                )

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
                                    , syncCursor = Maybe.withDefault 0 groupData.syncCursor
                                    , selectedAction = Page.JoinGroup.defaultAction groupState
                                    , newMemberName = ""
                                    , historyWarning = False
                                    }
                          }
                        , Cmd.none
                        )

                _ ->
                    ( model, Cmd.none )

        OnJoinLocalGroupLoaded _ ->
            ( model, Cmd.none )

        OnJoinGroupFetched (ConcurrentTask.Success fetched) ->
            let
                verified : List Event.Envelope
                verified =
                    fetched.syncResult.pullResult.events

                -- The invite's attestation (spec §12.1): the fetched history
                -- must reach the inviter's head. Old bare-key links (or an
                -- unknown tail format) carry none and skip the check.
                attestationOk : Bool
                attestationOk =
                    case model.route of
                        GroupRoute _ (Join invite) ->
                            case Maybe.andThen Compaction.parseAttestation invite.tail of
                                Just attestation ->
                                    Compaction.historyReaches attestation verified

                                Nothing ->
                                    True

                        _ ->
                            True
            in
            if not attestationOk then
                ( { model | joinGroupModel = Page.JoinGroup.error (T.joinGroupTruncated model.i18n) }
                , Cmd.none
                )

            else
                let
                    groupState : GroupState.GroupState
                    groupState =
                        GroupState.applyEvents verified GroupState.empty
                in
                ( { model
                    | joinGroupModel =
                        Page.JoinGroup.showPreview
                            { groupName = groupState.groupMeta.name
                            , groupState = groupState
                            , events = verified
                            , syncCursor = fetched.syncResult.pullResult.cursor
                            , selectedAction = Page.JoinGroup.defaultAction groupState
                            , newMemberName = ""
                            , historyWarning = fetched.manifestMismatch
                            }
                  }
                , Cmd.none
                )

        OnJoinGroupFetched (ConcurrentTask.Error err) ->
            ( { model | joinGroupModel = Page.JoinGroup.error (Server.errorToString err) }
            , Cmd.none
            )

        OnJoinGroupFetched (ConcurrentTask.UnexpectedError _) ->
            ( logError ErrorLog.SyncSource
                ErrorLog.Err
                "Unexpected error fetching join group"
                { model | joinGroupModel = Page.JoinGroup.error "Unexpected error" }
            , Cmd.none
            )

        OnJoinGroupSaved groupId memberId (ConcurrentTask.Success _) ->
            case ( model.appState, Page.JoinGroup.getPreview model.joinGroupModel ) of
                ( Ready readyData, Just preview ) ->
                    let
                        summary : Group.Summary
                        summary =
                            GroupState.summarize memberId groupId model.currentTime preview.groupState

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
                        |> requestPersistOnFirstGroup readyData.groups

                _ ->
                    ( model, Cmd.none )

        OnJoinGroupSaved _ _ _ ->
            addToast Toast.Error (T.toastJoinError model.i18n) model

        -- Import / Export
        ImportExportMsg ieMsg ->
            case model.appState of
                Ready readyData ->
                    let
                        config : ImportExport.Config Msg
                        config =
                            { toMsg = ImportExportMsg
                            , db = readyData.db
                            , groups = readyData.groups
                            , currentTime = model.currentTime
                            , i18n = model.i18n
                            , identityHash = Maybe.map .publicKeyHash readyData.identity |> Maybe.withDefault ""
                            }

                        ( ( runner, cmd ), maybeOutMsg ) =
                            ImportExport.update config ieMsg ( model.runner, Cmd.none )
                    in
                    processImportExportOutMsg { model | runner = runner } cmd maybeOutMsg

                _ ->
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
                                |> ImportExport.startImport ImportExportMsg base64
                                |> Tuple.mapFirst (\r -> { updatedModel | runner = r })

                        Just (Page.Home.SplitwiseFileLoaded { filename, content }) ->
                            case SplitwiseImport.parse content of
                                Ok parsed ->
                                    ( { updatedModel
                                        | importSplitwiseModel =
                                            Just
                                                (Page.ImportSplitwise.init
                                                    { groupName = dropFileExtension filename
                                                    , parsed = parsed
                                                    }
                                                )
                                      }
                                    , Cmd.batch [ cmd, Navigation.pushUrl navCmd (Route.toAppUrl Route.ImportSplitwise) ]
                                    )

                                Err _ ->
                                    ( { updatedModel | homeModel = Page.Home.setImportError (T.splitwiseImportParseError model.i18n) updatedModel.homeModel }
                                    , cmd
                                    )

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

        -- Server sync
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
            ( logError ErrorLog.ServerSource
                ErrorLog.Err
                "Unexpected error creating server group"
                { model | pendingServerCreations = Set.remove groupId model.pendingServerCreations }
            , Cmd.none
            )

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
                                |> Runner.andRun OnAboutStatsReset
                                    (Storage.resetUsageStats readyData.db
                                        |> ConcurrentTask.andThenDo (UsageStats.persistedStatus |> ConcurrentTask.mapError never)
                                    )
                                |> Tuple.mapFirst (\r -> { model | aboutModel = aboutModel, runner = r })

                        _ ->
                            ( { model | aboutModel = aboutModel }, Cmd.none )

                Nothing ->
                    ( { model | aboutModel = aboutModel }, Cmd.none )

        OnStorageCheckComplete (ConcurrentTask.Success ( maybeStats, storageEstimate, persistStatus )) ->
            case model.appState of
                Ready readyData ->
                    let
                        stats : UsageStats
                        stats =
                            maybeStats |> Maybe.withDefault (UsageStats.defaultStats model.currentTime)

                        updatedStats : UsageStats
                        updatedStats =
                            UsageStats.updateStorageCost model.timeZone model.currentTime storageEstimate.usage stats

                        breakdown : UsageStats.CostBreakdown
                        breakdown =
                            UsageStats.calculateCosts model.currentTime updatedStats

                        trackingSince : String
                        trackingSince =
                            Date.toString (Date.posixToDate model.timeZone updatedStats.trackingStartDate)

                        ( aboutModel, _ ) =
                            Page.About.update (Page.About.statsLoaded breakdown trackingSince persistStatus) model.aboutModel
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

        OnAboutStatsReset (ConcurrentTask.Success persistStatus) ->
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
                            Date.toString (Date.posixToDate model.timeZone freshStats.trackingStartDate)

                        ( aboutModel, _ ) =
                            Page.About.update (Page.About.statsLoaded breakdown trackingSince persistStatus) model.aboutModel
                    in
                    ( model.runner, Cmd.none )
                        |> Runner.andRun (\_ -> NoOp)
                            (Storage.saveUsageStats readyData.db freshStats)
                        |> Tuple.mapFirst (\r -> { model | aboutModel = aboutModel, runner = r })

                _ ->
                    ( model, Cmd.none )

        OnAboutStatsReset _ ->
            ( logError ErrorLog.StorageSource ErrorLog.Err "Unexpected error resetting usage stats" model, Cmd.none )

        OnSelfProfileSaved (ConcurrentTask.Success ()) ->
            ( model, Cmd.none )

        OnSelfProfileSaved _ ->
            ( logError ErrorLog.StorageSource ErrorLog.Err "Unexpected error saving self profile" model, Cmd.none )

        ToggleDevMode ->
            case model.appState of
                Ready readyData ->
                    let
                        updatedReadyData : Storage.InitData
                        updatedReadyData =
                            { readyData | devMode = not readyData.devMode }
                    in
                    ( model.runner, Cmd.none )
                        |> Runner.andRun (\_ -> NoOp)
                            (Storage.saveDevMode readyData.db updatedReadyData.devMode)
                        |> Tuple.mapFirst (\r -> { model | runner = r, appState = Ready updatedReadyData })

                _ ->
                    ( model, Cmd.none )

        ScheduleStorageCheck ->
            case model.appState of
                Ready readyData ->
                    ( model.runner, rescheduleStorageCheckTomorrow )
                        |> Runner.andRun OnStorageCheckComplete (storageCheckTask readyData.db)
                        |> Tuple.mapFirst (\r -> { model | runner = r })

                _ ->
                    ( model, rescheduleStorageCheckTomorrow )

        PwaStateMsg pwaMsg ->
            let
                ( pwaState, pwaCmd, outMsgs ) =
                    PwaState.update pwaOut pwaMsg model.pwaState
            in
            processPwaOutMsgs { model | pwaState = pwaState } pwaCmd outMsgs

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


{-| On the first group (create, import, or join), ask the browser to protect
the origin's storage from eviction. Later groups skip the request: once
granted it stays granted, and re-asking after a denial would only re-prompt.
-}
requestPersistOnFirstGroup : Dict.Dict Group.Id Group.Summary -> ( Model, Cmd Msg ) -> ( Model, Cmd Msg )
requestPersistOnFirstGroup groupsBefore ( model, cmd ) =
    if Dict.isEmpty groupsBefore then
        ( model.runner, cmd )
            |> Runner.andRun (\_ -> NoOp) UsageStats.requestPersistentStorage
            |> Tuple.mapFirst (\runner -> { model | runner = runner })

    else
        ( model, cmd )


storageCheckTask : Idb.Db -> ConcurrentTask Never ( Maybe UsageStats, UsageStats.StorageEstimate, UsageStats.PersistedStatus )
storageCheckTask db =
    ConcurrentTask.map3 (\stats estimate persisted -> ( stats, estimate, persisted ))
        (Storage.loadUsageStats db
            |> ConcurrentTask.onError (\_ -> ConcurrentTask.succeed Nothing)
        )
        UsageStats.estimateStorage
        UsageStats.persistedStatus


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


submitSplitwiseImport : Model -> Storage.InitData -> Page.ImportSplitwise.Output -> ( Model, Cmd Msg )
submitSplitwiseImport model readyData output =
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
                    GroupOps.importSplitwiseGroup ctx
                        OnGroupCreated
                        { groupName = output.groupName
                        , creatorName = output.creatorName
                        , claimedMemberIndex = output.claimedMemberIndex
                        , defaultCurrency = output.defaultCurrency
                        , rate = \c -> Dict.get (Currency.currencyCode c) output.rates |> Maybe.withDefault 1
                        , parsed = output.parsed
                        }
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


{-| Strip the extension from a filename, e.g. "Trip.csv" -> "Trip".
-}
dropFileExtension : String -> String
dropFileExtension name =
    case List.reverse (String.split "." name) of
        _ :: rest ->
            if List.isEmpty rest then
                name

            else
                String.join "." (List.reverse rest)

        [] ->
            name


{-| Reset scroll to the top when navigating to a new page. Routes that scroll
to a specific element handle their own viewport instead.
-}
navScrollCmd : Route -> Cmd Msg
navScrollCmd route =
    case route of
        GroupRoute _ (HighlightEntry _) ->
            Cmd.none

        _ ->
            Task.perform (\_ -> NoOp) (Browser.Dom.setViewport 0 0)


applyRouteGuard : Maybe Identity -> Route -> ( Route, Cmd Msg )
applyRouteGuard identity route =
    case identity of
        Nothing ->
            case route of
                Welcome ->
                    ( route, Cmd.none )

                About ->
                    ( route, Cmd.none )

                GroupRoute _ (Join _) ->
                    ( route, Cmd.none )

                _ ->
                    ( Welcome, Navigation.replaceUrl navCmd (AppUrl.fromPath []) )

        Just _ ->
            ( route, Cmd.none )


{-| Joiner-side compaction verification (spec §14.9): when the fetched
history carries a quorumed compaction proposal, the received pre-boundary
envelopes must count and hash exactly as the quorum signed. True means
mismatch — the history is surfaced as not fully verifiable.
-}
verifyCompactedHistory : List Event.Envelope -> ConcurrentTask Server.Error Bool
verifyCompactedHistory verified =
    let
        state : GroupState.GroupState
        state =
            GroupState.applyEvents verified GroupState.empty

        resolvers : { resolveRoot : Member.Id -> Maybe Member.Id, isRetired : Member.Id -> Bool }
        resolvers =
            { resolveRoot = GroupState.resolveMemberRootId state
            , isRetired =
                \root ->
                    Dict.get root state.members
                        |> Maybe.map .isRetired
                        |> Maybe.withDefault False
            }
    in
    case Compaction.quorumedProposal resolvers verified of
        Nothing ->
            ConcurrentTask.succeed False

        Just quorumed ->
            if quorumed.claimedCount /= quorumed.prefixCount then
                ConcurrentTask.succeed True

            else
                WebCrypto.sha256 quorumed.manifestInput
                    |> ConcurrentTask.mapError Server.CryptoError
                    |> ConcurrentTask.map (\hash -> hash /= quorumed.claimedHash)


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
                        -- Has identity: fetch group data from the server
                        let
                            serverCtx : Server.ServerContext
                            serverCtx =
                                { serverUrl = model.serverUrl
                                , groupId = groupId
                                , groupKey = Symmetric.importKey key
                                }

                            ( runner, cmd ) =
                                ( model.runner, Cmd.none )
                                    |> Runner.andRun OnJoinGroupFetched
                                        (Server.sync serverCtx
                                            ""
                                            { unpushedEvents = [], pullCursor = Nothing, notifyContext = Nothing }
                                            |> ConcurrentTask.andThen
                                                (\syncResult ->
                                                    EventVerification.filterVerifiedEvents GroupState.empty syncResult.pullResult.events
                                                        |> ConcurrentTask.andThen
                                                            (\verified ->
                                                                let
                                                                    pull : Server.PullResult
                                                                    pull =
                                                                        syncResult.pullResult
                                                                in
                                                                verifyCompactedHistory verified
                                                                    |> ConcurrentTask.map
                                                                        (\manifestMismatch ->
                                                                            { syncResult = { syncResult | pullResult = { pull | events = verified } }
                                                                            , manifestMismatch = manifestMismatch
                                                                            }
                                                                        )
                                                            )
                                                )
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
                        -- No identity: auto-generate one, then re-trigger join
                        ( model.runner, Cmd.none )
                            |> Runner.andRun OnIdentityGenerated Identity.generate
                            |> Tuple.mapFirst (\r -> { model | route = route, joinGroupModel = Page.JoinGroup.init, runner = r, generatingIdentity = True })

        _ ->
            ( { model | route = route }, Cmd.none )



-- PWA


processPwaOutMsgs : Model -> Cmd Msg -> List PwaState.OutMsg -> ( Model, Cmd Msg )
processPwaOutMsgs model pwaCmd outMsgs =
    let
        ( finalModel, extraCmds ) =
            List.foldl
                (\outMsg ( m, cmds ) ->
                    case outMsg of
                        PwaState.ShowToastError ->
                            let
                                ( modelWithToast, toastCmd ) =
                                    addToast Toast.Error (T.toastPushError m.i18n) m
                            in
                            ( logError ErrorLog.PushSource ErrorLog.Err "Push subscription error" modelWithToast, toastCmd :: cmds )

                        PwaState.NavigateToUrl url ->
                            case Url.fromString (m.origin ++ url) of
                                Just parsedUrl ->
                                    let
                                        route : Route
                                        route =
                                            Route.fromAppUrl (AppUrl.fromUrl parsedUrl)
                                    in
                                    ( m, Navigation.pushUrl navCmd (Route.toAppUrl route) :: cmds )

                                Nothing ->
                                    ( m, cmds )

                        PwaState.LogError source severity message ->
                            ( logError source severity message m, cmds )

                        PwaState.CameOnline ->
                            case m.groupModel.loadedGroup of
                                Just loaded ->
                                    if loaded.syncCursor == Nothing then
                                        attemptServerGroupCreation loaded.summary.id (Just loaded.groupKey) m
                                            |> Tuple.mapSecond (\cmd -> cmd :: cmds)

                                    else
                                        case buildGroupConfig m of
                                            Just config ->
                                                Page.Group.triggerSync config loaded.summary.id m.groupModel
                                                    |> Update.wrap GroupMsg (\gm -> { m | groupModel = gm })
                                                    |> Tuple.mapSecond (\cmd -> cmd :: cmds)

                                            Nothing ->
                                                ( m, cmds )

                                Nothing ->
                                    ( m, cmds )
                )
                ( model, [] )
                outMsgs
    in
    ( finalModel, Cmd.batch (pwaCmd :: extraCmds) )


processImportExportOutMsg : Model -> Cmd Msg -> Maybe ImportExport.OutMsg -> ( Model, Cmd Msg )
processImportExportOutMsg model ieCmd maybeOutMsg =
    case maybeOutMsg of
        Nothing ->
            ( model, ieCmd )

        Just (ImportExport.ShowToast level message) ->
            addToast level
                message
                (case level of
                    Toast.Error ->
                        logError ErrorLog.ImportExportSource ErrorLog.Err message model

                    _ ->
                        model
                )
                |> Update.addCmd ieCmd

        Just (ImportExport.SetImportError errorMsg) ->
            ( { model | homeModel = Page.Home.setImportError errorMsg model.homeModel }, ieCmd )

        Just (ImportExport.GroupImported summary droppedCount) ->
            case model.appState of
                Ready readyData ->
                    let
                        importedModel : Model
                        importedModel =
                            { model
                                | appState = Ready { readyData | groups = Dict.insert summary.id summary readyData.groups }
                                , groupModel = Page.Group.resetLoadedGroup model.groupModel
                                , homeModel = Page.Home.init
                            }
                    in
                    (if droppedCount > 0 then
                        let
                            warning : String
                            warning =
                                T.toastImportTampered (String.fromInt droppedCount) model.i18n
                        in
                        addToast Toast.Error warning (logError ErrorLog.ImportExportSource ErrorLog.Err warning importedModel)

                     else
                        addToast Toast.Success (T.toastImportSuccess model.i18n) importedModel
                    )
                        |> Update.addCmd ieCmd
                        |> Update.addCmd (Navigation.pushUrl navCmd (Route.toAppUrl (GroupRoute summary.id (Tab BalanceTab))))

                _ ->
                    ( model, ieCmd )


handleToggleGroupNotification : Group.Id -> String -> Model -> ( Model, Cmd Msg )
handleToggleGroupNotification groupId memberRootId model =
    case model.appState of
        Ready readyData ->
            case ( Dict.get groupId readyData.groups, model.pwaState.pushSubscription ) of
                ( Just summary, Just subscription ) ->
                    ( model.runner, Cmd.none )
                        |> Runner.andRun (OnToggleNotifResult groupId)
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
            , Ui.Responsive.paddingXY Theme.breakpoints
                (\bp ->
                    case bp of
                        Theme.Compact ->
                            { x = Ui.Responsive.value Theme.spacing.md, y = Ui.Responsive.value 0 }

                        Theme.Wide ->
                            { x = Ui.Responsive.value Theme.spacing.xl, y = Ui.Responsive.value 0 }
                )
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

        errorLogButton : Ui.Attribute Msg
        errorLogButton =
            if model.errorLog.size > 0 && model.route /= Route.ErrorLog then
                Ui.inFront <|
                    Ui.el
                        [ Ui.alignRight
                        , Ui.centerY
                        ]
                        (Ui.el
                            [ Ui.Input.button (NavigateTo Route.ErrorLog)
                            , Ui.pointer
                            , Ui.background Theme.danger.solid
                            , Ui.rounded 8
                            , Ui.padding Theme.spacing.sm
                            , Ui.htmlAttribute (Html.Attributes.style "border-top-right-radius" "0")
                            , Ui.htmlAttribute (Html.Attributes.style "border-bottom-right-radius" "0")
                            ]
                            (UI.Components.featherIconColored "white" 20 FeatherIcons.alertTriangle)
                        )

            else
                Ui.noAttr
    in
    Ui.layout (Ui.default |> Ui.withBreakpoints Theme.breakpoints)
        [ Ui.background Theme.base.bg
        , Theme.fontFamily
        , Ui.Font.color Theme.base.text
        , Ui.Font.size Theme.font.md
        , overlayAttr
        , toasts
        , errorLogButton
        ]
        (Ui.el [ Ui.background Theme.base.bg ]
            (Ui.column
                [ Ui.widthMax Theme.contentMaxWidth
                , Ui.centerX
                , Ui.htmlAttribute (Html.Attributes.style "min-height" "100dvh")
                , Ui.Responsive.paddingEach Theme.breakpoints
                    (\bp ->
                        case bp of
                            Theme.Compact ->
                                { top = Ui.Responsive.value Theme.spacing.md
                                , bottom = Ui.Responsive.value 0
                                , left = Ui.Responsive.value Theme.spacing.md
                                , right = Ui.Responsive.value Theme.spacing.md
                                }

                            Theme.Wide ->
                                { top = Ui.Responsive.value Theme.spacing.md
                                , bottom = Ui.Responsive.value 0
                                , left = Ui.Responsive.value Theme.spacing.xl
                                , right = Ui.Responsive.value Theme.spacing.xl
                                }
                    )
                ]
                [ Ui.map PwaStateMsg (PwaState.viewBanners model.i18n model.pwaState), pageResult.content ]
            )
        )


viewPage : Model -> Page.Group.ViewResult Msg
viewPage model =
    let
        noOverlay : Ui.Element Msg -> Page.Group.ViewResult Msg
        noOverlay content =
            { content = content, overlay = Nothing }
    in
    case model.route of
        Route.ErrorLog ->
            noOverlay <|
                UI.Shell.pageShell { title = T.errorLogTitle model.i18n, onBack = GoBack }
                    (Page.ErrorLog.view
                        { i18n = model.i18n
                        , errorLog = model.errorLog
                        , groups =
                            case model.appState of
                                Ready readyData ->
                                    Dict.values readyData.groups

                                _ ->
                                    []
                        , currentTime = model.currentTime
                        , timeZone = model.timeZone
                        , appState =
                            case model.appState of
                                Loading ->
                                    "Loading"

                                InitError _ ->
                                    "InitError"

                                Ready _ ->
                                    "Ready"
                        }
                    )

        _ ->
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
        Welcome ->
            noOverlay <|
                Page.Welcome.view i18n
                    { onGenerate = GenerateIdentity
                    , onSwitchLanguage = SwitchLanguage
                    , onNavigate = NavigateTo
                    , isGenerating = model.generatingIdentity
                    , hasIdentity = readyData.identity /= Nothing
                    }

        Home ->
            noOverlay <|
                Page.Home.view i18n
                    { onNavigate = NavigateTo
                    , onExport = ImportExportMsg << ImportExport.exportMsg
                    , onExportCsv = ImportExportMsg << ImportExport.exportCsvMsg
                    , notificationPermission = model.pwaState.notificationPermission
                    , pushActive = PwaState.pushIsActive model.pwaState
                    , onEnableNotifications = PwaStateMsg PwaState.enableNotificationsMsg
                    , currentTime = model.currentTime
                    }
                    HomeMsg
                    model.homeModel
                    (Dict.values readyData.groups)

        NewGroup ->
            noOverlay <|
                UI.Shell.pageShell { title = T.shellNewGroup i18n, onBack = GoBack }
                    (Page.NewGroup.view i18n NewGroupMsg model.newGroupModel)

        ImportSplitwise ->
            noOverlay <|
                UI.Shell.pageShell { title = T.splitwiseImportTitle i18n, onBack = NavigateTo Home }
                    (case model.importSplitwiseModel of
                        Just pageModel ->
                            Page.ImportSplitwise.view i18n ImportSplitwiseMsg pageModel

                        Nothing ->
                            Ui.none
                    )

        GroupRoute _ (Join _) ->
            noOverlay <|
                UI.Shell.pageShell { title = T.shellJoinGroup i18n, onBack = GoBack }
                    (Page.JoinGroup.view i18n { toMsg = JoinGroupMsg, onSwitchLanguage = SwitchLanguage } model.joinGroupModel)

        GroupRoute groupId groupView ->
            Page.Group.view
                { i18n = i18n
                , toMsg = GroupMsg
                , onNavigateHome = NavigateTo Home
                , onGoBack = GoBack
                , onSwitchLanguage = SwitchLanguage
                , today = Date.posixToDate model.timeZone model.currentTime
                , timeZone = model.timeZone
                , groupId = groupId
                , isKnownGroup = Dict.member groupId readyData.groups
                , origin = model.origin
                , pushActive = PwaState.pushIsActive model.pwaState
                , selfProfile = readyData.selfProfile
                , devMode = readyData.devMode
                }
                groupView
                model.groupModel

        About ->
            noOverlay <|
                UI.Shell.pageShell { title = T.aboutTitle i18n, onBack = NavigateTo Home }
                    (Page.About.view i18n
                        { onSwitchLanguage = SwitchLanguage
                        , toMsg = AboutMsg
                        , devMode = readyData.devMode
                        , onToggleDevMode = ToggleDevMode
                        }
                        model.aboutModel
                    )

        Route.ErrorLog ->
            -- Handled in viewPage before reaching viewReady
            noOverlay Ui.none

        NotFound ->
            noOverlay <|
                UI.Shell.pageShell { title = T.shellPartage i18n, onBack = NavigateTo Home }
                    (Page.NotFound.view i18n)


{-| Create a group on the server. Called after sync has already failed,
indicating the group doesn't exist on the server yet.
No-op if creation is already in progress.
-}
attemptServerGroupCreation : Group.Id -> Maybe Symmetric.Key -> Model -> ( Model, Cmd Msg )
attemptServerGroupCreation groupId maybeGroupKey model =
    case model.appState of
        Ready readyData ->
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
                                    |> ConcurrentTask.mapError (\_ -> Server.InternalError "Failed to load group key in IndexedDB")

                    createGroup : Symmetric.Key -> ConcurrentTask Server.Error ()
                    createGroup key =
                        Server.createGroupOnServer
                            { serverUrl = model.serverUrl
                            , groupId = groupId
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
