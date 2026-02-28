port module Main exposing (main)

import AppUrl exposing (AppUrl)
import Browser
import ConcurrentTask
import Dict
import Domain.Date as Date
import Domain.Event as Event
import Domain.Group as Group
import Domain.GroupState as GroupState exposing (GroupState)
import Form.NewGroup
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
import Page.Loading
import Page.NewEntry
import Page.NewGroup
import Page.NotFound
import Page.Setup
import Random
import Route exposing (GroupTab(..), GroupView(..), Route(..))
import Storage exposing (GroupSummary)
import Time
import Translations as T exposing (I18n, Language(..))
import UI.Components
import UI.Shell
import UI.Theme as Theme
import UUID
import Ui
import Ui.Font
import Url
import UuidGen
import WebCrypto


port navCmd : Navigation.CommandPort msg


port onNavEvent : Navigation.EventPort msg


port sendTask : Json.Encode.Value -> Cmd msg


port receiveTask : (Json.Decode.Value -> msg) -> Sub msg


type alias Flags =
    { initialUrl : String
    , language : String
    , randomSeed : List Int
    , currentTime : Int
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
    , loadedGroup : Maybe LoadedGroup
    }


type alias LoadedGroup =
    { groupId : Group.Id
    , events : List Event.Envelope
    , groupState : GroupState
    , summary : GroupSummary
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
      -- Group loading
    | OnGroupEventsLoaded Group.Id (ConcurrentTask.Response Idb.Error (List Event.Envelope))


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
        ]


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
        route =
            flags.initialUrl
                |> Url.fromString
                |> Maybe.map (AppUrl.fromUrl >> Route.fromAppUrl)
                |> Maybe.withDefault NotFound

        language =
            flags.language
                |> T.languageFromString
                |> Maybe.withDefault En

        i18n =
            T.init language

        initialSeed =
            List.foldl
                (\n acc -> Random.step (Random.int Random.minInt Random.maxInt) acc |> Tuple.second)
                (Random.initialSeed (List.sum flags.randomSeed))
                flags.randomSeed

        ( uuidState, seedAfterV7 ) =
            Random.step UUID.initialV7State initialSeed

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
      , newEntryModel = Page.NewEntry.init { currentUserRootId = "", activeMembers = [], today = Date.posixToDate currentTime }
      , loadedGroup = Nothing
      }
    , cmd
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        OnNavEvent event ->
            let
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

                modelWithEntry =
                    initNewEntryIfNeeded modelAfterGuard guardedRoute
            in
            ( modelWithEntry, Cmd.batch [ guardCmd, loadCmd ] )

        NavigateTo route ->
            ( model, Navigation.pushUrl navCmd (Route.toAppUrl route) )

        SwitchTab tab ->
            case model.route of
                GroupRoute groupId _ ->
                    let
                        newRoute =
                            GroupRoute groupId (Tab tab)
                    in
                    ( { model | route = newRoute }
                    , Navigation.replaceUrl navCmd (Route.toAppUrl newRoute)
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
            in
            ( modelWithData
            , Cmd.batch [ guardCmd, loadCmd ]
            )

        OnInitComplete (ConcurrentTask.Error err) ->
            ( { model | appState = InitError (Storage.errorToString err) }, Cmd.none )

        OnInitComplete (ConcurrentTask.UnexpectedError _) ->
            ( { model | appState = InitError "Unexpected error during initialization" }, Cmd.none )

        OnIdentitySaved _ ->
            ( model, Cmd.none )

        -- Page form messages
        NewGroupMsg subMsg ->
            let
                ( newGroupModel, maybeOutput ) =
                    Page.NewGroup.update subMsg model.newGroupModel

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

                modelWithForm =
                    { model | newEntryModel = newEntryModel }
            in
            case ( maybeOutput, model.appState, model.loadedGroup ) of
                ( Just output, Ready readyData, Just loaded ) ->
                    submitNewEntry modelWithForm readyData loaded output

                _ ->
                    ( modelWithForm, Cmd.none )

        OnGroupCreated (ConcurrentTask.Success summary) ->
            case model.appState of
                Ready readyData ->
                    let
                        newRoute =
                            GroupRoute summary.id (Tab BalanceTab)
                    in
                    ( { model
                        | appState = Ready { readyData | groups = readyData.groups ++ [ summary ] }
                        , loadedGroup = Nothing
                      }
                    , Navigation.pushUrl navCmd (Route.toAppUrl newRoute)
                    )

                _ ->
                    ( model, Cmd.none )

        OnGroupCreated _ ->
            ( model, Cmd.none )

        OnEntrySaved groupId (ConcurrentTask.Success envelope) ->
            case model.loadedGroup of
                Just loaded ->
                    if loaded.groupId == groupId then
                        let
                            -- TODO later: reverse events order to ease aggregation
                            newEvents =
                                loaded.events ++ [ envelope ]

                            -- TODO later: do not re-build group state from scratch if possible,
                            -- change applyEvents to: List Envelope -> GroupState -> GroupState
                            newGroupState =
                                GroupState.applyEvents newEvents

                            newRoute =
                                GroupRoute groupId (Tab EntriesTab)
                        in
                        ( { model
                            | loadedGroup =
                                Just
                                    { loaded
                                        | events = newEvents
                                        , groupState = newGroupState
                                    }
                          }
                        , Navigation.pushUrl navCmd (Route.toAppUrl newRoute)
                        )

                    else
                        ( model, Cmd.none )

                Nothing ->
                    ( model, Cmd.none )

        OnEntrySaved _ _ ->
            ( model, Cmd.none )

        -- Group loading
        OnGroupEventsLoaded groupId (ConcurrentTask.Success events) ->
            case model.appState of
                Ready readyData ->
                    case findGroupSummary groupId readyData.groups of
                        Just summary ->
                            let
                                modelWithGroup =
                                    { model
                                        | loadedGroup =
                                            Just
                                                { groupId = groupId
                                                , events = events
                                                , groupState = GroupState.applyEvents events
                                                , summary = summary
                                                }
                                    }
                            in
                            ( initNewEntryIfNeeded modelWithGroup model.route
                            , Cmd.none
                            )

                        Nothing ->
                            ( model, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        OnGroupEventsLoaded _ _ ->
            ( model, Cmd.none )


submitNewGroup : Model -> Storage.InitData -> Form.NewGroup.Output -> ( Model, Cmd Msg )
submitNewGroup model readyData output =
    case readyData.identity of
        Nothing ->
            ( model, Cmd.none )

        Just identity ->
            let
                -- Generate group ID (v4)
                ( groupId, seed1 ) =
                    UuidGen.v4 model.randomSeed

                -- Generate virtual member IDs (v4)
                ( virtualMemberIds, seedAfter ) =
                    UuidGen.v4batch (List.length output.virtualMembers) seed1

                -- Generate event IDs (v7): 1 metadata + 1 creator + N virtual members
                ( eventIds, uuidStateAfter ) =
                    UuidGen.v7batch (2 + List.length output.virtualMembers) model.currentTime model.uuidState

                allEvents =
                    Event.buildGroupCreationEvents
                        { creatorId = identity.publicKeyHash
                        , groupName = output.name
                        , creatorName = output.creatorName
                        , virtualMembers = List.map2 Tuple.pair virtualMemberIds output.virtualMembers
                        , eventIds = eventIds
                        , currentTime = model.currentTime
                        }

                summary =
                    { id = groupId
                    , name = output.name
                    , defaultCurrency = output.currency
                    }

                task =
                    Storage.saveGroupSummary readyData.db summary
                        |> ConcurrentTask.andThen (\_ -> Storage.saveEvents readyData.db groupId allEvents)
                        |> ConcurrentTask.map (\_ -> summary)

                ( pool, cmd ) =
                    ConcurrentTask.attempt
                        { pool = model.pool
                        , send = sendTask
                        , onComplete = OnGroupCreated
                        }
                        task
            in
            ( { model
                | pool = pool
                , randomSeed = seedAfter
                , uuidState = uuidStateAfter
              }
            , cmd
            )


submitNewEntry : Model -> Storage.InitData -> LoadedGroup -> Page.NewEntry.Output -> ( Model, Cmd Msg )
submitNewEntry model readyData loaded output =
    case readyData.identity |> Maybe.andThen (\id -> Dict.get id.publicKeyHash loaded.groupState.members) |> Maybe.map .rootId of
        Nothing ->
            ( model, Cmd.none )

        Just currentUserRootId ->
            let
                ( entryId, seedAfter ) =
                    UuidGen.v4 model.randomSeed

                ( eventId, uuidStateAfter ) =
                    UuidGen.v7 model.currentTime model.uuidState

                envelope =
                    case output of
                        Page.NewEntry.ExpenseOutput data ->
                            Event.buildExpenseEvent
                                { entryId = entryId
                                , eventId = eventId
                                , currentUserRootId = currentUserRootId
                                , currentTime = model.currentTime
                                , currency = loaded.summary.defaultCurrency
                                , payerId = data.payerId
                                , beneficiaryIds = data.beneficiaryIds
                                , description = data.description
                                , amountCents = data.amountCents
                                , category = data.category
                                , notes = data.notes
                                , date = data.date
                                }

                        Page.NewEntry.TransferOutput data ->
                            Event.buildTransferEvent
                                { entryId = entryId
                                , eventId = eventId
                                , currentUserRootId = currentUserRootId
                                , currentTime = model.currentTime
                                , currency = loaded.summary.defaultCurrency
                                , fromMemberId = data.fromMemberId
                                , toMemberId = data.toMemberId
                                , amountCents = data.amountCents
                                , notes = data.notes
                                , date = data.date
                                }

                task =
                    Storage.saveEvents readyData.db loaded.groupId [ envelope ]
                        |> ConcurrentTask.map (\_ -> envelope)

                ( pool, cmd ) =
                    ConcurrentTask.attempt
                        { pool = model.pool
                        , send = sendTask
                        , onComplete = OnEntrySaved loaded.groupId
                        }
                        task
            in
            ( { model
                | pool = pool
                , randomSeed = seedAfter
                , uuidState = uuidStateAfter
              }
            , cmd
            )


initNewEntryIfNeeded : Model -> Route -> Model
initNewEntryIfNeeded model route =
    case ( route, model.appState, model.loadedGroup ) of
        ( GroupRoute _ NewEntry, Ready readyData, Just loaded ) ->
            let
                currentUserRootId =
                    readyData.identity
                        |> Maybe.andThen (\id -> Dict.get id.publicKeyHash loaded.groupState.members)
                        |> Maybe.map .rootId
                        |> Maybe.withDefault ""

                activeMembers =
                    GroupState.activeMembers loaded.groupState
            in
            { model
                | newEntryModel =
                    Page.NewEntry.init
                        { currentUserRootId = currentUserRootId
                        , activeMembers = List.map (\m -> { id = m.id, rootId = m.rootId }) activeMembers
                        , today = Date.posixToDate model.currentTime
                        }
            }

        _ ->
            model


ensureGroupLoaded : Model -> Route -> ( Model, Cmd Msg )
ensureGroupLoaded model route =
    case route of
        GroupRoute groupId _ ->
            case model.loadedGroup of
                Just loaded ->
                    if loaded.groupId == groupId then
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
                ( pool, cmd ) =
                    ConcurrentTask.attempt
                        { pool = model.pool
                        , send = sendTask
                        , onComplete = OnGroupEventsLoaded groupId
                        }
                        (Storage.loadGroupEvents readyData.db groupId)
            in
            ( { model | pool = pool, loadedGroup = Nothing }, cmd )

        _ ->
            ( model, Cmd.none )


findGroupSummary : Group.Id -> List GroupSummary -> Maybe GroupSummary
findGroupSummary groupId groups =
    List.filter (\g -> g.id == groupId) groups
        |> List.head


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
    Ui.layout Ui.default [ Ui.height Ui.fill ] (viewPage model)


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
        i18n =
            model.i18n

        langSelector =
            UI.Components.languageSelector SwitchLanguage model.language
    in
    case model.route of
        Setup ->
            UI.Shell.appShell
                { title = T.shellPartage i18n
                , headerExtra = langSelector
                , content = Page.Setup.view i18n { onGenerate = GenerateIdentity, isGenerating = model.generatingIdentity }
                }

        Home ->
            UI.Shell.appShell
                { title = T.shellPartage i18n
                , headerExtra = langSelector
                , content = Page.Home.view i18n NavigateTo readyData.groups
                }

        NewGroup ->
            UI.Shell.appShell
                { title = T.shellNewGroup i18n
                , headerExtra = langSelector
                , content = Page.NewGroup.view i18n NewGroupMsg model.newGroupModel
                }

        GroupRoute groupId (Tab tab) ->
            case model.loadedGroup of
                Just loaded ->
                    if loaded.groupId == groupId then
                        let
                            currentUserRootId =
                                readyData.identity
                                    |> Maybe.andThen (\id -> Dict.get id.publicKeyHash loaded.groupState.members)
                                    |> Maybe.map .rootId
                                    |> Maybe.withDefault ""
                        in
                        Page.Group.view
                            { i18n = i18n
                            , onTabClick = SwitchTab
                            , onNewEntry = NavigateTo (GroupRoute groupId NewEntry)
                            , currentUserRootId = currentUserRootId
                            }
                            langSelector
                            loaded.groupState
                            tab

                    else
                        viewLoadingGroup i18n langSelector

                Nothing ->
                    viewLoadingGroup i18n langSelector

        GroupRoute groupId (Join _) ->
            UI.Shell.appShell
                { title = T.shellJoinGroup i18n
                , headerExtra = langSelector
                , content =
                    Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ]
                        (Ui.text (T.joinGroupComingSoon i18n))
                }

        GroupRoute groupId NewEntry ->
            case model.loadedGroup of
                Just loaded ->
                    if loaded.groupId == groupId then
                        UI.Shell.appShell
                            { title = T.shellNewEntry i18n
                            , headerExtra = langSelector
                            , content =
                                Page.NewEntry.view i18n
                                    (GroupState.activeMembers loaded.groupState)
                                    NewEntryMsg
                                    model.newEntryModel
                            }

                    else
                        viewLoadingGroup i18n langSelector

                Nothing ->
                    viewLoadingGroup i18n langSelector

        About ->
            UI.Shell.appShell { title = T.shellPartage i18n, headerExtra = langSelector, content = Page.About.view i18n }

        NotFound ->
            UI.Shell.appShell { title = T.shellPartage i18n, headerExtra = langSelector, content = Page.NotFound.view i18n }


viewLoadingGroup : I18n -> Ui.Element Msg -> Ui.Element Msg
viewLoadingGroup i18n langSelector =
    UI.Shell.appShell
        { title = T.shellPartage i18n
        , headerExtra = langSelector
        , content =
            Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ]
                (Ui.text (T.loadingGroup i18n))
        }
