port module Main exposing (main)

import AppUrl exposing (AppUrl)
import Browser
import ConcurrentTask
import Dict
import Domain.Date as Date
import Domain.Entry as Entry
import Domain.Event as Event
import Domain.Group as Group
import Domain.GroupState as GroupState exposing (GroupState)
import Domain.Member as Member
import Domain.Settlement as Settlement
import Form.NewGroup
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
import Random
import Route exposing (GroupTab(..), GroupView(..), Route(..))
import Storage exposing (GroupSummary)
import Submit exposing (LoadedGroup)
import Time
import Translations as T exposing (I18n, Language(..))
import UI.Components
import UI.Shell
import UI.Theme as Theme
import UUID
import Ui
import Ui.Font
import Url
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
    , memberDetailModel : Page.MemberDetail.Model
    , addMemberModel : Page.AddMember.Model
    , editMemberMetadataModel : Page.EditMemberMetadata.Model
    , editGroupMetadataModel : Page.EditGroupMetadata.Model
    , loadedGroup : Maybe LoadedGroup
    , showDeleted : Bool
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
    | SettleTransaction Settlement.Transaction
    | DeleteEntry Entry.Id
    | RestoreEntry Entry.Id
    | OnEntryActionSaved Group.Id (ConcurrentTask.Response Idb.Error Event.Envelope)
    | ToggleShowDeleted
      -- Member management
    | MemberDetailMsg Page.MemberDetail.Msg
    | AddMemberMsg Page.AddMember.Msg
    | EditMemberMetadataMsg Page.EditMemberMetadata.Msg
    | OnMemberActionSaved Group.Id (ConcurrentTask.Response Idb.Error Event.Envelope)
      -- Group metadata editing
    | EditGroupMetadataMsg Page.EditGroupMetadata.Msg
    | OnGroupMetadataActionSaved Group.Id (ConcurrentTask.Response Idb.Error Event.Envelope)
    | RemoveGroup Group.Id
    | OnGroupRemoved Group.Id (ConcurrentTask.Response Idb.Error ())
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
      , memberDetailModel = Page.MemberDetail.init dummyMemberState
      , addMemberModel = Page.AddMember.init
      , editMemberMetadataModel = Page.EditMemberMetadata.init "" Member.emptyMetadata
      , editGroupMetadataModel = Page.EditGroupMetadata.init GroupState.empty.groupMeta
      , loadedGroup = Nothing
      , showDeleted = False
      }
    , cmd
    )


dummyMemberState : GroupState.MemberState
dummyMemberState =
    { id = ""
    , rootId = ""
    , previousId = Nothing
    , name = ""
    , memberType = Member.Virtual
    , isRetired = False
    , isReplaced = False
    , isActive = False
    , metadata = Member.emptyMetadata
    }


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

                modelWithPages =
                    initPagesIfNeeded modelAfterGuard guardedRoute
            in
            ( modelWithPages, Cmd.batch [ guardCmd, loadCmd ] )

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
                        newRoute =
                            GroupRoute summary.id (Tab EntriesTab)
                    in
                    ( { model
                        | appState = Ready { readyData | groups = Dict.insert summary.id summary readyData.groups }
                        , loadedGroup = Nothing
                      }
                    , Navigation.pushUrl navCmd (Route.toAppUrl newRoute)
                    )

                _ ->
                    ( model, Cmd.none )

        OnGroupCreated _ ->
            ( model, Cmd.none )

        OnEntrySaved groupId (ConcurrentTask.Success envelope) ->
            case appendEventAndRecompute model groupId envelope of
                Just updatedModel ->
                    let
                        targetRoute =
                            case model.route of
                                GroupRoute _ (Tab BalanceTab) ->
                                    GroupRoute groupId (Tab BalanceTab)

                                _ ->
                                    GroupRoute groupId (Tab EntriesTab)
                    in
                    ( updatedModel
                    , Navigation.pushUrl navCmd (Route.toAppUrl targetRoute)
                    )

                Nothing ->
                    ( model, Cmd.none )

        OnEntrySaved _ _ ->
            ( model, Cmd.none )

        SettleTransaction tx ->
            case ( model.appState, model.loadedGroup ) of
                ( Ready readyData, Just loaded ) ->
                    let
                        output =
                            Page.NewEntry.TransferOutput
                                { amountCents = tx.amount
                                , fromMemberId = tx.from
                                , toMemberId = tx.to
                                , notes = Nothing
                                , date = Date.posixToDate model.currentTime
                                }
                    in
                    submitNewEntry model readyData loaded output

                _ ->
                    ( model, Cmd.none )

        DeleteEntry rootId ->
            submitEntryAction model (\ctx loaded -> Submit.deleteEntry ctx loaded rootId)

        RestoreEntry rootId ->
            submitEntryAction model (\ctx loaded -> Submit.restoreEntry ctx loaded rootId)

        OnEntryActionSaved groupId (ConcurrentTask.Success envelope) ->
            ( appendEventAndRecompute model groupId envelope
                |> Maybe.withDefault model
            , Cmd.none
            )

        OnEntryActionSaved _ _ ->
            ( model, Cmd.none )

        ToggleShowDeleted ->
            ( { model | showDeleted = not model.showDeleted }, Cmd.none )

        MemberDetailMsg subMsg ->
            let
                ( memberDetailModel, maybeOutput ) =
                    Page.MemberDetail.update subMsg model.memberDetailModel

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
                    case model.route of
                        GroupRoute gid AddVirtualMember ->
                            ( { updatedModel | addMemberModel = Page.AddMember.init }
                            , Navigation.pushUrl navCmd (Route.toAppUrl (GroupRoute gid (Tab MembersTab)))
                            )

                        GroupRoute gid (EditMemberMetadata memberId) ->
                            ( updatedModel
                            , Navigation.pushUrl navCmd (Route.toAppUrl (GroupRoute gid (MemberDetail memberId)))
                            )

                        _ ->
                            ( initPagesIfNeeded updatedModel model.route
                            , Cmd.none
                            )

                Nothing ->
                    ( model, Cmd.none )

        OnMemberActionSaved _ _ ->
            ( model, Cmd.none )

        -- Group metadata editing
        EditGroupMetadataMsg subMsg ->
            let
                result =
                    Page.EditGroupMetadata.update subMsg model.editGroupMetadataModel

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
                        ( finalModel, syncCmd ) =
                            syncGroupSummaryName groupId updatedModel
                    in
                    ( finalModel
                    , Cmd.batch
                        [ syncCmd
                        , Navigation.pushUrl navCmd (Route.toAppUrl (GroupRoute groupId (Tab MembersTab)))
                        ]
                    )

                Nothing ->
                    ( model, Cmd.none )

        OnGroupMetadataActionSaved _ _ ->
            ( model, Cmd.none )

        RemoveGroup groupId ->
            deleteGroup model groupId

        OnGroupRemoved groupId (ConcurrentTask.Success _) ->
            case model.appState of
                Ready readyData ->
                    ( { model
                        | appState = Ready { readyData | groups = Dict.remove groupId readyData.groups }
                        , loadedGroup = Nothing
                      }
                    , Navigation.pushUrl navCmd (Route.toAppUrl Home)
                    )

                _ ->
                    ( model, Cmd.none )

        OnGroupRemoved _ _ ->
            ( model, Cmd.none )

        -- Group loading
        OnGroupEventsLoaded groupId (ConcurrentTask.Success events) ->
            case model.appState of
                Ready readyData ->
                    case Dict.get groupId readyData.groups of
                        Just summary ->
                            let
                                modelWithGroup =
                                    { model
                                        | loadedGroup =
                                            Just
                                                { groupId = groupId
                                                , events = List.reverse events
                                                , groupState = GroupState.applyEvents events GroupState.empty
                                                , summary = summary
                                                }
                                    }
                            in
                            ( initPagesIfNeeded modelWithGroup model.route
                            , Cmd.none
                            )

                        Nothing ->
                            ( model, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        OnGroupEventsLoaded _ _ ->
            ( model, Cmd.none )


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
            case submitContext (OnEntryActionSaved loaded.groupId) model readyData of
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
    case submitContext (OnEntrySaved loaded.groupId) model readyData of
        Just ctx ->
            applySubmitResult model (Submit.newEntry ctx loaded output)

        Nothing ->
            ( model, Cmd.none )


submitEditEntry : Model -> Storage.InitData -> LoadedGroup -> Entry.Id -> Page.NewEntry.Output -> ( Model, Cmd Msg )
submitEditEntry model readyData loaded originalEntryId output =
    case submitContext (OnEntrySaved loaded.groupId) model readyData of
        Just ctx ->
            Submit.editEntry ctx loaded originalEntryId output
                |> Maybe.map (applySubmitResult model)
                |> Maybe.withDefault ( model, Cmd.none )

        Nothing ->
            ( model, Cmd.none )


initPagesIfNeeded : Model -> Route -> Model
initPagesIfNeeded model route =
    case ( route, model.appState, model.loadedGroup ) of
        ( GroupRoute _ NewEntry, Ready readyData, Just loaded ) ->
            { model
                | newEntryModel =
                    Page.NewEntry.init (entryFormConfig readyData loaded model.currentTime)
            }

        ( GroupRoute _ (EditEntry entryId), Ready readyData, Just loaded ) ->
            case Dict.get entryId loaded.groupState.entries of
                Just entryState ->
                    { model
                        | newEntryModel =
                            Page.NewEntry.initFromEntry
                                (entryFormConfig readyData loaded model.currentTime)
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
                            Page.EditMemberMetadata.init memberState.rootId memberState.metadata
                    }

                Nothing ->
                    model

        ( GroupRoute _ EditGroupMetadata, _, Just loaded ) ->
            { model | editGroupMetadataModel = Page.EditGroupMetadata.init loaded.groupState.groupMeta }

        _ ->
            model


entryFormConfig : Storage.InitData -> LoadedGroup -> Time.Posix -> Page.NewEntry.Config
entryFormConfig readyData loaded currentTime =
    let
        activeMembers =
            GroupState.activeMembers loaded.groupState
    in
    { currentUserRootId = GroupState.resolveMemberRootId loaded.groupState (readyData.identity |> Maybe.map .publicKeyHash |> Maybe.withDefault "")
    , activeMembers = List.map (\m -> { id = m.id, rootId = m.rootId }) activeMembers
    , today = Date.posixToDate currentTime
    }


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


handleMemberDetailOutput : Model -> Storage.InitData -> LoadedGroup -> Page.MemberDetail.Output -> ( Model, Cmd Msg )
handleMemberDetailOutput model readyData loaded output =
    let
        submit =
            submitEvent (OnMemberActionSaved loaded.groupId) model readyData loaded
    in
    case output of
        Page.MemberDetail.RenameOutput data ->
            submit
                (Event.MemberRenamed
                    { memberId = data.memberId
                    , oldName = data.oldName
                    , newName = data.newName
                    }
                )

        Page.MemberDetail.RetireOutput memberId ->
            submit (Event.MemberRetired { memberId = memberId })

        Page.MemberDetail.UnretireOutput memberId ->
            submit (Event.MemberUnretired { memberId = memberId })

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
    case submitContext (OnMemberActionSaved loaded.groupId) model readyData of
        Just ctx ->
            applySubmitResult model (Submit.addMember ctx loaded output)

        Nothing ->
            ( model, Cmd.none )


submitMemberMetadata : Model -> Storage.InitData -> LoadedGroup -> Page.EditMemberMetadata.Output -> ( Model, Cmd Msg )
submitMemberMetadata model readyData loaded output =
    submitEvent (OnMemberActionSaved loaded.groupId)
        model
        readyData
        loaded
        (Event.MemberMetadataUpdated
            { memberId = output.memberId
            , metadata = output.metadata
            }
        )


submitGroupMetadata : Model -> Storage.InitData -> LoadedGroup -> Event.GroupMetadataChange -> ( Model, Cmd Msg )
submitGroupMetadata model readyData loaded change =
    submitEvent (OnGroupMetadataActionSaved loaded.groupId)
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
                updatedSummary =
                    { id = groupId
                    , name = loaded.groupState.groupMeta.name
                    , defaultCurrency = loaded.summary.defaultCurrency
                    }

                ( pool, cmd ) =
                    ConcurrentTask.attempt
                        { pool = model.pool
                        , send = sendTask
                        , onComplete = \_ -> OnIdentitySaved (ConcurrentTask.Success ())
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


mapLoadedGroup : (LoadedGroup -> LoadedGroup) -> Group.Id -> Model -> Maybe Model
mapLoadedGroup f groupId model =
    case model.loadedGroup of
        Just loaded ->
            if loaded.groupId == groupId then
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
                , content = Page.Home.view i18n NavigateTo (Dict.values readyData.groups)
                }

        NewGroup ->
            UI.Shell.appShell
                { title = T.shellNewGroup i18n
                , headerExtra = langSelector
                , content = Page.NewGroup.view i18n NewGroupMsg model.newGroupModel
                }

        GroupRoute groupId (Tab tab) ->
            viewWithLoadedGroup model
                groupId
                langSelector
                (\loaded ->
                    Page.Group.view
                        { i18n = i18n
                        , onTabClick = SwitchTab
                        , onNewEntry = NavigateTo (GroupRoute groupId NewEntry)
                        , onEntryClick = \entryId -> NavigateTo (GroupRoute groupId (EntryDetail entryId))
                        , onToggleDeleted = ToggleShowDeleted
                        , onMemberClick = \memberId -> NavigateTo (GroupRoute groupId (MemberDetail memberId))
                        , onAddMember = NavigateTo (GroupRoute groupId AddVirtualMember)
                        , onEditGroupMetadata = NavigateTo (GroupRoute groupId EditGroupMetadata)
                        , onSettleTransaction = SettleTransaction
                        , currentUserRootId = GroupState.resolveMemberRootId loaded.groupState (readyData.identity |> Maybe.map .publicKeyHash |> Maybe.withDefault "")
                        }
                        { showDeleted = model.showDeleted }
                        langSelector
                        loaded.groupState
                        tab
                )

        GroupRoute groupId (Join _) ->
            UI.Shell.appShell
                { title = T.shellJoinGroup i18n
                , headerExtra = langSelector
                , content =
                    Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ]
                        (Ui.text (T.joinGroupComingSoon i18n))
                }

        GroupRoute groupId NewEntry ->
            viewWithLoadedGroup model
                groupId
                langSelector
                (\loaded ->
                    UI.Shell.appShell
                        { title = T.shellNewEntry i18n
                        , headerExtra = langSelector
                        , content =
                            Page.NewEntry.view i18n
                                (GroupState.activeMembers loaded.groupState)
                                NewEntryMsg
                                model.newEntryModel
                        }
                )

        GroupRoute groupId (EntryDetail entryId) ->
            viewWithLoadedGroup model
                groupId
                langSelector
                (\loaded ->
                    case Dict.get entryId loaded.groupState.entries of
                        Just entryState ->
                            UI.Shell.appShell
                                { title = T.entryDetailTitle i18n
                                , headerExtra = langSelector
                                , content =
                                    Page.EntryDetail.view i18n
                                        { onEdit = NavigateTo (GroupRoute groupId (EditEntry entryId))
                                        , onDelete = DeleteEntry entryId
                                        , onRestore = RestoreEntry entryId
                                        , onBack = NavigateTo (GroupRoute groupId (Tab EntriesTab))
                                        , currentUserRootId = GroupState.resolveMemberRootId loaded.groupState (readyData.identity |> Maybe.map .publicKeyHash |> Maybe.withDefault "")
                                        , resolveName = GroupState.resolveMemberName loaded.groupState
                                        }
                                        entryState
                                }

                        Nothing ->
                            UI.Shell.appShell
                                { title = T.shellPartage i18n
                                , headerExtra = langSelector
                                , content = Page.NotFound.view i18n
                                }
                )

        GroupRoute groupId (EditEntry _) ->
            viewWithLoadedGroup model
                groupId
                langSelector
                (\loaded ->
                    UI.Shell.appShell
                        { title = T.editEntryTitle i18n
                        , headerExtra = langSelector
                        , content =
                            Page.NewEntry.view i18n
                                (GroupState.activeMembers loaded.groupState)
                                NewEntryMsg
                                model.newEntryModel
                        }
                )

        GroupRoute groupId (MemberDetail _) ->
            viewWithLoadedGroup model
                groupId
                langSelector
                (\loaded ->
                    UI.Shell.appShell
                        { title = T.memberDetailTitle i18n
                        , headerExtra = langSelector
                        , content =
                            Page.MemberDetail.view i18n
                                (GroupState.resolveMemberRootId loaded.groupState (readyData.identity |> Maybe.map .publicKeyHash |> Maybe.withDefault ""))
                                MemberDetailMsg
                                model.memberDetailModel
                        }
                )

        GroupRoute groupId AddVirtualMember ->
            viewWithLoadedGroup model
                groupId
                langSelector
                (\_ ->
                    UI.Shell.appShell
                        { title = T.memberAddTitle i18n
                        , headerExtra = langSelector
                        , content =
                            Page.AddMember.view i18n
                                AddMemberMsg
                                model.addMemberModel
                        }
                )

        GroupRoute groupId (EditMemberMetadata _) ->
            viewWithLoadedGroup model
                groupId
                langSelector
                (\_ ->
                    UI.Shell.appShell
                        { title = T.memberEditMetadataButton i18n
                        , headerExtra = langSelector
                        , content =
                            Page.EditMemberMetadata.view i18n
                                EditMemberMetadataMsg
                                model.editMemberMetadataModel
                        }
                )

        GroupRoute groupId EditGroupMetadata ->
            viewWithLoadedGroup model
                groupId
                langSelector
                (\_ ->
                    UI.Shell.appShell
                        { title = T.groupSettingsTitle i18n
                        , headerExtra = langSelector
                        , content =
                            Page.EditGroupMetadata.view i18n
                                EditGroupMetadataMsg
                                model.editGroupMetadataModel
                        }
                )

        About ->
            UI.Shell.appShell { title = T.shellPartage i18n, headerExtra = langSelector, content = Page.About.view i18n }

        NotFound ->
            UI.Shell.appShell { title = T.shellPartage i18n, headerExtra = langSelector, content = Page.NotFound.view i18n }


viewWithLoadedGroup : Model -> Group.Id -> Ui.Element Msg -> (LoadedGroup -> Ui.Element Msg) -> Ui.Element Msg
viewWithLoadedGroup model groupId langSelector content =
    case model.loadedGroup of
        Just loaded ->
            if loaded.groupId == groupId then
                content loaded

            else
                viewLoadingGroup model.i18n langSelector

        Nothing ->
            viewLoadingGroup model.i18n langSelector


viewLoadingGroup : I18n -> Ui.Element Msg -> Ui.Element Msg
viewLoadingGroup i18n langSelector =
    UI.Shell.appShell
        { title = T.shellPartage i18n
        , headerExtra = langSelector
        , content =
            Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ]
                (Ui.text (T.loadingGroup i18n))
        }
