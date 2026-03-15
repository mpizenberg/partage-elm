module Page.Group exposing
    ( InitConfig
    , Model
    , Msg
    , Output(..)
    , PendingEntry
    , UpdateConfig
    , ViewConfig
    , ViewResult
    , handleNavigation
    , init
    , pocketbaseEventMsg
    , resetLoadedGroup
    , setIdentityHash
    , submitJoinEvent
    , subscription
    , triggerSync
    , update
    , updateLoadedSummary
    , view
    )

{-| Group page shell with tab routing, using real group data.

Owns its own ConcurrentTask.Pool and handles all group business logic
(event submission, sync, loading, output handling) internally.

-}

import Browser.Dom
import ConcurrentTask exposing (ConcurrentTask)
import Dict exposing (Dict)
import Domain.Currency exposing (Currency(..))
import Domain.Date as Date exposing (Date)
import Domain.Entry as Entry
import Domain.Event as Event
import Domain.Group as Group
import Domain.GroupState as GroupState
import Domain.Member as Member
import Domain.Settlement as Settlement
import GroupOps exposing (LoadedGroup)
import IndexedDb as Idb
import Infra.ConcurrentTaskExtra as Runner exposing (TaskRunner)
import Infra.EventVerification as EventVerification
import Infra.Identity exposing (Identity)
import Infra.PushServer as PushServer
import Infra.Server as Server
import Infra.Storage as Storage
import Json.Decode
import Json.Encode
import Page.Group.ActivityTab
import Page.Group.AddMember
import Page.Group.BalanceTab
import Page.Group.EditGroupMetadata
import Page.Group.EditMemberMetadata
import Page.Group.EntriesTab
import Page.Group.MembersTab
import Page.Group.NewEntry
import Page.Group.NewEntry.Shared as NewEntryShared
import Page.JoinGroup
import PocketBase
import PocketBase.Realtime
import Process
import Random
import Route exposing (GroupTab(..), GroupView(..), Route(..))
import Set exposing (Set)
import Task
import Time
import Translations as T exposing (I18n)
import UI.Components
import UI.Shell
import UI.Theme as Theme
import UI.Toast as Toast
import UUID
import Ui
import Ui.Font
import WebCrypto.Symmetric as Symmetric



-- CONFIG TYPES


{-| Configuration for initializing Page.Group. Provided once at startup.
-}
type alias InitConfig =
    { pool : ConcurrentTask.Pool Msg
    , send : Json.Encode.Value -> Cmd Msg
    , receive : (Json.Decode.Value -> Msg) -> Sub Msg
    , randomSeed : Random.Seed
    , uuidState : UUID.V7State
    }


{-| Runtime dependencies provided by Main on each update call.
-}
type alias UpdateConfig =
    { db : Idb.Db
    , identity : Identity
    , pbClient : Maybe PocketBase.Client
    , currentTime : Time.Posix
    , route : Route
    , i18n : I18n
    , groups : Dict Group.Id Group.Summary
    }


{-| View configuration, much simpler than the old Context.
-}
type alias ViewConfig msg =
    { i18n : I18n
    , toMsg : Msg -> msg
    , onNavigateHome : msg
    , onGoBack : msg
    , today : Date
    , groupId : Group.Id
    , origin : String
    , pushActive : Bool
    }



-- MODEL


type alias Model =
    -- ConcurrentTask runner and RNG state
    { runner : TaskRunner Msg
    , randomSeed : Random.Seed
    , uuidState : UUID.V7State
    , identityHash : String
    , loadedGroup : Maybe LoadedGroup
    , syncInProgress : Bool

    -- Tabs
    , activeTab : GroupTab
    , entriesTabModel : Page.Group.EntriesTab.Model
    , balanceTabModel : Page.Group.BalanceTab.Model
    , activityTabModel : Page.Group.ActivityTab.Model
    , membersTabModel : Page.Group.MembersTab.Model

    -- Member pages
    , addMemberModel : Page.Group.AddMember.Model
    , editMemberMetadataModel : Page.Group.EditMemberMetadata.Model

    -- Entry pages
    , newEntryModel : Page.Group.NewEntry.Model
    , pendingEntry : Maybe PendingEntry

    -- Group pages
    , editGroupMetadataModel : Page.Group.EditGroupMetadata.Model
    }


type PendingEntry
    = PendingTransfer Entry.TransferData
    | PendingExpense Entry.ExpenseData



-- MSG


subscription : Model -> Sub Msg
subscription model =
    Runner.subscription model.runner


pocketbaseEventMsg : Json.Decode.Value -> Msg
pocketbaseEventMsg =
    OnPocketbaseEvent


type
    Msg
    -- Pool progress
    = OnTaskProgress ( TaskRunner Msg, Cmd Msg )
      -- Navigation
    | RequestNavigation GroupView
    | RequestTransfer { toMemberId : Member.Id, amountCents : Int }
      -- Tabs
    | EntriesTabMsg Page.Group.EntriesTab.Msg
    | BalanceTabMsg Page.Group.BalanceTab.Msg
    | ActivityTabMsg Page.Group.ActivityTab.Msg
    | MembersTabMsg Page.Group.MembersTab.Msg
      -- Member pages
    | AddMemberMsg Page.Group.AddMember.Msg
    | EditMemberMetadataMsg Page.Group.EditMemberMetadata.Msg
      -- Entry pages
    | NewEntryMsg NewEntryShared.Msg
      -- Group pages
    | EditGroupMetadataMsg Page.Group.EditGroupMetadata.Msg
    | SettleTransaction Settlement.Transaction
    | SaveSettlementPreferences { memberRootId : Member.Id, preferredRecipients : List Member.Id }
    | ToggleNotification
      -- Async response handlers
    | OnEntrySaved Group.Id (ConcurrentTask.Response Idb.Error Event.Envelope)
    | OnEntryActionSaved Group.Id (ConcurrentTask.Response Idb.Error Event.Envelope)
    | OnMemberActionSaved Group.Id (ConcurrentTask.Response Idb.Error Event.Envelope)
    | OnGroupMetadataActionSaved Group.Id (ConcurrentTask.Response Idb.Error Event.Envelope)
    | OnGroupRemoved Group.Id (ConcurrentTask.Response Idb.Error ())
    | OnGroupSummarySaved (ConcurrentTask.Response Idb.Error Idb.Key)
    | OnGroupEventsLoaded Group.Id (ConcurrentTask.Response Idb.Error { events : List Event.Envelope, groupKey : Symmetric.Key, syncCursor : Maybe String, unpushedIds : Set String })
    | OnGroupSynced Group.Id (Set String) (ConcurrentTask.Response Server.Error Server.SyncResult)
    | PostSyncTasksDone (ConcurrentTask.Response Idb.Error ())
    | OnPocketbaseEvent Json.Decode.Value
    | ScrollToEntryResult (Result Browser.Dom.Error ())



-- OUTPUT


{-| Outputs produced by Page.Group that Main needs to handle.
-}
type Output
    = NavigateTo Route
    | ShowToast Toast.ToastLevel String
    | UpdateGroupSummary Group.Summary
    | RemoveGroup Group.Id Member.Id
    | UpdateCurrentTime Time.Posix
    | ToggleGroupNotification Group.Id Member.Id
    | RequestServerGroupCreation Group.Id Symmetric.Key



-- INIT


init : InitConfig -> Model
init config =
    { runner =
        Runner.initTaskRunner
            { pool = config.pool
            , send = config.send
            , receive = config.receive
            , onProgress = OnTaskProgress
            }
    , randomSeed = config.randomSeed
    , uuidState = config.uuidState
    , identityHash = ""
    , loadedGroup = Nothing
    , syncInProgress = False
    , activeTab = BalanceTab
    , entriesTabModel = Page.Group.EntriesTab.init
    , balanceTabModel = Page.Group.BalanceTab.init
    , activityTabModel = Page.Group.ActivityTab.init
    , membersTabModel = Page.Group.MembersTab.init
    , addMemberModel = Page.Group.AddMember.init
    , editMemberMetadataModel = Page.Group.EditMemberMetadata.init "" "" Member.emptyMetadata
    , newEntryModel = Page.Group.NewEntry.init { currentUserRootId = "", activeMembersRootIds = [], today = { year = 2000, month = 1, day = 1 }, defaultCurrency = EUR }
    , pendingEntry = Nothing
    , editGroupMetadataModel = Page.Group.EditGroupMetadata.init GroupState.empty.groupMeta
    }



-- EXPOSED FUNCTIONS


{-| Handle navigation to a group view. Combines ensureGroupLoaded + initPagesIfNeeded.
-}
handleNavigation : UpdateConfig -> Group.Id -> GroupView -> Model -> ( Model, Cmd Msg )
handleNavigation config groupId groupView model =
    let
        ( loadedModel, loadCmd ) =
            ensureGroupLoaded config groupId model

        ( initModel, initCmd ) =
            initPagesIfNeeded config groupView loadedModel
    in
    ( initModel, Cmd.batch [ loadCmd, initCmd ] )


ensureGroupLoaded : UpdateConfig -> Group.Id -> Model -> ( Model, Cmd Msg )
ensureGroupLoaded config groupId model =
    case model.loadedGroup of
        Just loaded ->
            if loaded.summary.id == groupId then
                ( model, Cmd.none )

            else
                loadGroup config groupId model

        Nothing ->
            loadGroup config groupId model


loadGroup : UpdateConfig -> Group.Id -> Model -> ( Model, Cmd Msg )
loadGroup config groupId model =
    ( model.runner, Cmd.none )
        |> Runner.andRun (OnGroupEventsLoaded groupId) (Storage.loadGroup config.db groupId)
        |> Tuple.mapFirst (\r -> { model | runner = r, loadedGroup = Nothing })


{-| Trigger a server sync for the given group. Called by Main on OnServerGroupCreated.
-}
triggerSync : UpdateConfig -> Group.Id -> Model -> ( Model, Cmd Msg )
triggerSync config groupId model =
    triggerSyncInternal config groupId model


{-| Reset the loaded group. Called by Main on OnGroupCreated / OnGroupImported.
-}
resetLoadedGroup : Model -> Model
resetLoadedGroup model =
    { model | loadedGroup = Nothing }


{-| Update the loaded group's summary if it matches the given group ID.
-}
updateLoadedSummary : Group.Summary -> Model -> Model
updateLoadedSummary summary model =
    case model.loadedGroup of
        Just loaded ->
            if loaded.summary.id == summary.id then
                { model | loadedGroup = Just { loaded | summary = summary } }

            else
                model

        Nothing ->
            model


{-| Set the identity hash. Called by Main on OnInitComplete / OnIdentityGenerated.
-}
setIdentityHash : String -> Model -> Model
setIdentityHash hash model =
    { model | identityHash = hash }


{-| Submit a member event for joining a group (claim member or join as new).
Called by Main after the group has been loaded following a join.
-}
submitJoinEvent : UpdateConfig -> { action : Page.JoinGroup.JoinAction, newMemberName : String } -> Model -> ( Model, Cmd Msg )
submitJoinEvent config joinData model =
    case model.loadedGroup of
        Just loaded ->
            case joinPayload config.identity.publicKeyHash config.identity.signingKeyPair.publicKey joinData loaded of
                Just payload ->
                    let
                        ( newModel, cmd, _ ) =
                            runSubmit (OnMemberActionSaved loaded.summary.id) config model (\ctx -> GroupOps.event ctx loaded payload)
                    in
                    ( newModel, cmd )

                Nothing ->
                    ( model, Cmd.none )

        Nothing ->
            ( model, Cmd.none )


joinPayload : Member.Id -> String -> { action : Page.JoinGroup.JoinAction, newMemberName : String } -> LoadedGroup -> Maybe Event.Payload
joinPayload selfId publicKey joinData loaded =
    case joinData.action of
        Page.JoinGroup.ClaimMember rootId ->
            Dict.get rootId loaded.groupState.members
                |> Maybe.map
                    (\chain ->
                        Event.MemberReplaced
                            { rootId = rootId
                            , previousId = chain.currentMember.id
                            , newId = selfId
                            , publicKey = publicKey
                            }
                    )

        Page.JoinGroup.JoinAsNewMember ->
            Just
                (Event.MemberCreated
                    { memberId = selfId
                    , name = joinData.newMemberName
                    , memberType = Member.Real
                    , addedBy = selfId
                    , publicKey = publicKey
                    }
                )



-- UPDATE


update : UpdateConfig -> Msg -> Model -> ( Model, Cmd Msg, List Output )
update config msg model =
    case msg of
        OnTaskProgress ( runner, cmd ) ->
            ( { model | runner = runner }, cmd, [] )

        RequestNavigation groupView ->
            case config.route of
                GroupRoute groupId _ ->
                    ( model, Cmd.none, [ NavigateTo (GroupRoute groupId groupView) ] )

                _ ->
                    ( model, Cmd.none, [] )

        RequestTransfer payData ->
            case ( config.route, model.loadedGroup ) of
                ( GroupRoute groupId _, Just loaded ) ->
                    let
                        transferData : Entry.TransferData
                        transferData =
                            { amount = payData.amountCents
                            , currency = loaded.summary.defaultCurrency
                            , defaultCurrencyAmount = Nothing
                            , date = Date.posixToDate config.currentTime
                            , from = currentUserRootId model loaded |> Maybe.withDefault ""
                            , to = payData.toMemberId
                            , notes = Nothing
                            }
                    in
                    ( { model | pendingEntry = Just (PendingTransfer transferData) }, Cmd.none, [ NavigateTo (GroupRoute groupId NewEntry) ] )

                _ ->
                    ( model, Cmd.none, [] )

        -- Tab sub-page messages
        EntriesTabMsg subMsg ->
            let
                ( newEntriesTabModel, maybeOutput ) =
                    Page.Group.EntriesTab.update subMsg model.entriesTabModel

                modelWithTab : Model
                modelWithTab =
                    { model | entriesTabModel = newEntriesTabModel }
            in
            case maybeOutput of
                Just output ->
                    handleEntriesTabOutput config modelWithTab output

                Nothing ->
                    ( modelWithTab, Cmd.none, [] )

        BalanceTabMsg subMsg ->
            ( { model | balanceTabModel = Page.Group.BalanceTab.update subMsg model.balanceTabModel }, Cmd.none, [] )

        ActivityTabMsg subMsg ->
            ( { model | activityTabModel = Page.Group.ActivityTab.update subMsg model.activityTabModel }, Cmd.none, [] )

        MembersTabMsg subMsg ->
            let
                ( newMembersTabModel, maybeOutput ) =
                    Page.Group.MembersTab.update subMsg model.membersTabModel

                modelWithTab : Model
                modelWithTab =
                    { model | membersTabModel = newMembersTabModel }
            in
            case maybeOutput of
                Just output ->
                    handleMembersTabOutput config modelWithTab output

                Nothing ->
                    ( modelWithTab, Cmd.none, [] )

        -- Add member
        AddMemberMsg subMsg ->
            let
                ( modelWithPage, maybeOutput ) =
                    Page.Group.AddMember.update subMsg model.addMemberModel
                        |> Tuple.mapFirst (\subModel -> { model | addMemberModel = subModel })
            in
            case ( maybeOutput, model.loadedGroup ) of
                ( Just addOutput, Just loaded ) ->
                    runSubmit (OnMemberActionSaved loaded.summary.id) config modelWithPage (\ctx -> GroupOps.addMember ctx loaded addOutput)

                _ ->
                    ( modelWithPage, Cmd.none, [] )

        -- Edit member metadata
        EditMemberMetadataMsg subMsg ->
            let
                ( modelWithPage, maybeOutput ) =
                    Page.Group.EditMemberMetadata.update subMsg model.editMemberMetadataModel
                        |> Tuple.mapFirst (\subModel -> { model | editMemberMetadataModel = subModel })
            in
            case ( maybeOutput, model.loadedGroup ) of
                ( Just metaOutput, Just loaded ) ->
                    submitMemberMetadata config modelWithPage loaded metaOutput

                _ ->
                    ( modelWithPage, Cmd.none, [] )

        -- New entry / edit entry
        NewEntryMsg subMsg ->
            let
                ( modelWithPage, maybeOutput ) =
                    Page.Group.NewEntry.update subMsg model.newEntryModel
                        |> Tuple.mapFirst (\subModel -> { model | newEntryModel = subModel })
            in
            case ( maybeOutput, model.loadedGroup ) of
                ( Just entryOutput, Just loaded ) ->
                    case config.route of
                        GroupRoute _ (EditEntry entryId) ->
                            case GroupOps.editEntry (submitContext (OnEntrySaved loaded.summary.id) config modelWithPage) loaded entryId entryOutput of
                                Just ( state, cmd ) ->
                                    ( { modelWithPage | runner = state.runner, randomSeed = state.randomSeed, uuidState = state.uuidState }, cmd, [] )

                                Nothing ->
                                    ( modelWithPage, Cmd.none, [] )

                        _ ->
                            runSubmit (OnEntrySaved loaded.summary.id) config modelWithPage (\ctx -> GroupOps.newEntry ctx loaded entryOutput)

                _ ->
                    ( modelWithPage, Cmd.none, [] )

        -- Edit group metadata
        EditGroupMetadataMsg subMsg ->
            let
                result : Page.Group.EditGroupMetadata.UpdateResult
                result =
                    Page.Group.EditGroupMetadata.update subMsg model.editGroupMetadataModel

                modelWithPage : Model
                modelWithPage =
                    { model | editGroupMetadataModel = result.model }
            in
            if result.deleteRequested then
                case config.route of
                    GroupRoute groupId _ ->
                        deleteGroup config modelWithPage groupId

                    _ ->
                        ( modelWithPage, Cmd.none, [] )

            else if result.archiveRequested then
                case model.loadedGroup of
                    Just loaded ->
                        toggleArchiveGroup config modelWithPage loaded

                    Nothing ->
                        ( modelWithPage, Cmd.none, [] )

            else
                case ( result.metadataOutput, model.loadedGroup ) of
                    ( Just change, Just loaded ) ->
                        runSubmit (OnGroupMetadataActionSaved loaded.summary.id)
                            config
                            modelWithPage
                            (\ctx -> GroupOps.event ctx loaded (Event.GroupMetadataUpdated change))

                    _ ->
                        ( modelWithPage, Cmd.none, [] )

        SettleTransaction tx ->
            case model.loadedGroup of
                Just loaded ->
                    let
                        output : NewEntryShared.Output
                        output =
                            NewEntryShared.TransferOutput
                                { amountCents = tx.amount
                                , currency = loaded.summary.defaultCurrency
                                , defaultCurrencyAmount = Nothing
                                , fromMemberId = tx.from
                                , toMemberId = tx.to
                                , notes = Nothing
                                , date = Date.posixToDate config.currentTime
                                }
                    in
                    runSubmit (OnEntrySaved loaded.summary.id) config model (\ctx -> GroupOps.newEntry ctx loaded output)

                Nothing ->
                    ( model, Cmd.none, [] )

        SaveSettlementPreferences prefData ->
            case model.loadedGroup of
                Just loaded ->
                    runSubmit (OnEntryActionSaved loaded.summary.id)
                        config
                        model
                        (\ctx -> GroupOps.event ctx loaded (Event.SettlementPreferencesUpdated prefData))

                Nothing ->
                    ( model, Cmd.none, [] )

        ToggleNotification ->
            case model.loadedGroup of
                Just loaded ->
                    case currentUserRootId model loaded of
                        Just userRootId ->
                            ( model, Cmd.none, [ ToggleGroupNotification loaded.summary.id userRootId ] )

                        Nothing ->
                            ( model, Cmd.none, [] )

                Nothing ->
                    ( model, Cmd.none, [] )

        -- Async response handlers
        OnEntrySaved groupId (ConcurrentTask.Success envelope) ->
            case applyAndSync config groupId envelope model of
                Just ( syncModel, syncCmd, timeOutputs ) ->
                    case config.route of
                        GroupRoute _ (Tab BalanceTab) ->
                            ( syncModel, syncCmd, ShowToast Toast.Success (T.toastSettlementRecorded config.i18n) :: timeOutputs )

                        _ ->
                            ( syncModel, syncCmd, NavigateTo (GroupRoute groupId (Tab EntriesTab)) :: timeOutputs )

                Nothing ->
                    ( model, Cmd.none, [] )

        OnEntrySaved _ _ ->
            ( model, Cmd.none, [ ShowToast Toast.Error (T.toastEntrySaveError config.i18n) ] )

        OnEntryActionSaved groupId (ConcurrentTask.Success envelope) ->
            let
                ( syncModel, syncCmd, timeOutputs ) =
                    applyAndSync config groupId envelope model
                        |> Maybe.withDefault ( model, Cmd.none, [] )
            in
            case Toast.entryActionMessage config.i18n envelope.payload of
                Just message ->
                    ( syncModel, syncCmd, ShowToast Toast.Success message :: timeOutputs )

                Nothing ->
                    ( syncModel, syncCmd, timeOutputs )

        OnEntryActionSaved _ _ ->
            ( model, Cmd.none, [ ShowToast Toast.Error (T.toastEntryActionError config.i18n) ] )

        OnMemberActionSaved groupId (ConcurrentTask.Success envelope) ->
            case applyAndSync config groupId envelope model of
                Just ( syncModel, syncCmd, timeOutputs ) ->
                    case config.route of
                        GroupRoute gid AddVirtualMember ->
                            ( { syncModel | addMemberModel = Page.Group.AddMember.init }
                            , syncCmd
                            , NavigateTo (GroupRoute gid (Tab MembersTab)) :: timeOutputs
                            )

                        GroupRoute gid (EditMemberMetadata _) ->
                            ( syncModel, syncCmd, NavigateTo (GroupRoute gid (Tab MembersTab)) :: timeOutputs )

                        _ ->
                            let
                                ( initModel, initCmd ) =
                                    initPagesIfNeeded config (routeToGroupView config.route) syncModel
                            in
                            ( initModel, Cmd.batch [ syncCmd, initCmd ], timeOutputs )

                Nothing ->
                    ( model, Cmd.none, [] )

        OnMemberActionSaved _ _ ->
            ( model, Cmd.none, [ ShowToast Toast.Error (T.toastMemberActionError config.i18n) ] )

        OnGroupMetadataActionSaved groupId (ConcurrentTask.Success envelope) ->
            case appendEventAndRecompute model groupId envelope of
                Just updatedModel ->
                    let
                        modelWithUnpushed : Model
                        modelWithUnpushed =
                            addUnpushedIdToModel envelope.id updatedModel

                        ( modelAfterSummary, summaryCmd, summaryOutputs ) =
                            syncGroupSummaryName config groupId modelWithUnpushed

                        ( syncModel, syncCmd ) =
                            triggerSyncInternal config groupId modelAfterSummary
                    in
                    ( syncModel
                    , Cmd.batch [ summaryCmd, syncCmd ]
                    , NavigateTo (GroupRoute groupId (Tab MembersTab)) :: UpdateCurrentTime envelope.clientTimestamp :: summaryOutputs
                    )

                Nothing ->
                    ( model, Cmd.none, [] )

        OnGroupMetadataActionSaved _ _ ->
            ( model, Cmd.none, [ ShowToast Toast.Error (T.toastGroupSettingsError config.i18n) ] )

        OnGroupRemoved groupId (ConcurrentTask.Success _) ->
            let
                memberRootId : Member.Id
                memberRootId =
                    model.loadedGroup
                        |> Maybe.andThen (currentUserRootId model)
                        |> Maybe.withDefault ""
            in
            ( { model | loadedGroup = Nothing }
            , Cmd.none
            , [ RemoveGroup groupId memberRootId
              , ShowToast Toast.Success (T.toastGroupRemoved config.i18n)
              , NavigateTo Home
              ]
            )

        OnGroupRemoved _ _ ->
            ( model, Cmd.none, [ ShowToast Toast.Error (T.toastGroupRemoveError config.i18n) ] )

        OnGroupSummarySaved (ConcurrentTask.Success _) ->
            ( model, Cmd.none, [] )

        OnGroupSummarySaved _ ->
            ( model, Cmd.none, [] )

        OnGroupEventsLoaded groupId (ConcurrentTask.Success result) ->
            let
                ( modelAfterLoad, initCmd ) =
                    case applyLoadedGroup config groupId result.events result.groupKey result.syncCursor result.unpushedIds model of
                        Just m ->
                            initPagesIfNeeded config (routeToGroupView config.route) m

                        Nothing ->
                            ( model, Cmd.none )

                -- Always try to sync. Works for both:
                -- - Previously synced groups (has cursor, pulls new events)
                -- - Imported groups (no cursor, pulls everything from server)
                -- If sync fails because group doesn't exist on server (newly created),
                -- the error handler will request server group creation.
                ( syncModel, syncCmd ) =
                    triggerSyncInternal config groupId modelAfterLoad
            in
            ( syncModel, Cmd.batch [ syncCmd, initCmd ], [] )

        OnGroupEventsLoaded _ _ ->
            ( model, Cmd.none, [] )

        OnGroupSynced groupId pushedIds (ConcurrentTask.Success syncResult) ->
            case model.loadedGroup of
                Just loaded ->
                    if loaded.summary.id == groupId then
                        let
                            result : GroupOps.SyncApplyResult
                            result =
                                GroupOps.applySyncResult pushedIds syncResult loaded

                            ( runner, taskCmds ) =
                                ( model.runner, Cmd.none )
                                    |> Runner.andRun PostSyncTasksDone (GroupOps.postSyncTasks config.db groupId config.pbClient result)

                            ( modelAfterSync, initCmd ) =
                                { model
                                    | loadedGroup = Just result.updatedGroup
                                    , runner = runner
                                    , syncInProgress = False
                                }
                                    |> initPagesIfNeeded config (routeToGroupView config.route)

                            ( summaryModel, summaryCmd, summaryOutputs ) =
                                syncGroupSummaryName config groupId modelAfterSync
                        in
                        -- If new events were added during sync, trigger follow-up
                        if Set.isEmpty result.updatedGroup.unpushedIds then
                            ( summaryModel, Cmd.batch [ taskCmds, summaryCmd, initCmd ], summaryOutputs )

                        else
                            let
                                ( followUpModel, followUpCmd ) =
                                    triggerSyncInternal config groupId summaryModel
                            in
                            ( followUpModel, Cmd.batch [ taskCmds, summaryCmd, followUpCmd, initCmd ], summaryOutputs )

                    else
                        ( { model | syncInProgress = False }, Cmd.none, [] )

                Nothing ->
                    ( { model | syncInProgress = False }, Cmd.none, [] )

        OnGroupSynced _ _ (ConcurrentTask.Error err) ->
            -- Sync failed — check if group needs to be created on server first
            case ( err, model.loadedGroup ) of
                ( Server.PbError PocketBase.NotFound, Just loaded ) ->
                    ( { model | syncInProgress = False }
                    , Cmd.none
                    , [ RequestServerGroupCreation loaded.summary.id loaded.groupKey ]
                    )

                ( Server.PbError PocketBase.Unauthorized, Just loaded ) ->
                    if loaded.syncCursor == Nothing then
                        -- Never synced + auth failed → group likely doesn't exist on server
                        ( { model | syncInProgress = False }
                        , Cmd.none
                        , [ RequestServerGroupCreation loaded.summary.id loaded.groupKey ]
                        )

                    else
                        ( { model | syncInProgress = False }
                        , Cmd.none
                        , [ ShowToast Toast.Error ("Sync: " ++ Server.errorToString err) ]
                        )

                _ ->
                    ( { model | syncInProgress = False }
                    , Cmd.none
                    , [ ShowToast Toast.Error ("Sync: " ++ Server.errorToString err) ]
                    )

        OnGroupSynced _ _ (ConcurrentTask.UnexpectedError _) ->
            ( { model | syncInProgress = False }, Cmd.none, [] )

        PostSyncTasksDone (ConcurrentTask.Success ()) ->
            ( model, Cmd.none, [] )

        PostSyncTasksDone _ ->
            ( model, Cmd.none, [] )

        OnPocketbaseEvent value ->
            case model.loadedGroup of
                Just loaded ->
                    case Json.Decode.decodeValue PocketBase.Realtime.decodeEvent value of
                        Ok ( _, PocketBase.Realtime.Created record ) ->
                            let
                                ( realtimeModel, realtimeCmd ) =
                                    handleRealtimeRecord config loaded record model
                            in
                            ( realtimeModel, realtimeCmd, [] )

                        _ ->
                            ( model, Cmd.none, [] )

                Nothing ->
                    ( model, Cmd.none, [] )

        ScrollToEntryResult _ ->
            ( model, Cmd.none, [] )



-- INTERNAL HELPERS


{-| Extract the GroupView from a Route, defaulting to Tab BalanceTab.
-}
routeToGroupView : Route -> GroupView
routeToGroupView route =
    case route of
        GroupRoute _ groupView ->
            groupView

        _ ->
            Tab BalanceTab


{-| Build a GroupOps.Context from our config and model.
-}
submitContext : (ConcurrentTask.Response Idb.Error Event.Envelope -> Msg) -> UpdateConfig -> Model -> GroupOps.Context Msg
submitContext onComplete config model =
    { runner = model.runner
    , onComplete = onComplete
    , randomSeed = model.randomSeed
    , uuidState = model.uuidState
    , currentTime = config.currentTime
    , db = config.db
    , identity = config.identity
    }


{-| Build context, run a submit function, apply the returned state to model.
-}
runSubmit : (ConcurrentTask.Response Idb.Error Event.Envelope -> Msg) -> UpdateConfig -> Model -> (GroupOps.Context Msg -> ( GroupOps.State Msg, Cmd Msg )) -> ( Model, Cmd Msg, List Output )
runSubmit onComplete config model submitFn =
    let
        ( state, cmd ) =
            submitFn (submitContext onComplete config model)
    in
    ( { model | runner = state.runner, randomSeed = state.randomSeed, uuidState = state.uuidState }
    , cmd
    , []
    )


{-| Submit an entry action (delete/restore), checking loadedGroup.
-}
submitEntryAction : UpdateConfig -> Model -> (GroupOps.Context Msg -> LoadedGroup -> ( GroupOps.State Msg, Cmd Msg )) -> ( Model, Cmd Msg, List Output )
submitEntryAction config model action =
    case model.loadedGroup of
        Just loaded ->
            runSubmit (OnEntryActionSaved loaded.summary.id) config model (\ctx -> action ctx loaded)

        Nothing ->
            ( model, Cmd.none, [] )


{-| Submit member metadata update, with optional rename if name changed.
-}
submitMemberMetadata : UpdateConfig -> Model -> LoadedGroup -> Page.Group.EditMemberMetadata.Output -> ( Model, Cmd Msg, List Output )
submitMemberMetadata config model loaded output =
    let
        ( modelAfterMeta, metaCmd, _ ) =
            runSubmit (OnMemberActionSaved loaded.summary.id)
                config
                model
                (\ctx -> GroupOps.event ctx loaded (Event.MemberMetadataUpdated { rootId = output.memberId, metadata = output.metadata }))
    in
    if output.newName /= output.oldName then
        let
            ( modelAfterRename, renameCmd, _ ) =
                runSubmit (OnMemberActionSaved loaded.summary.id)
                    config
                    modelAfterMeta
                    (\ctx ->
                        GroupOps.event ctx
                            loaded
                            (Event.MemberRenamed
                                { rootId = output.memberId
                                , oldName = output.oldName
                                , newName = output.newName
                                }
                            )
                    )
        in
        ( modelAfterRename, Cmd.batch [ metaCmd, renameCmd ], [] )

    else
        ( modelAfterMeta, metaCmd, [] )


handleEntriesTabOutput : UpdateConfig -> Model -> Page.Group.EntriesTab.Output -> ( Model, Cmd Msg, List Output )
handleEntriesTabOutput config model output =
    case output of
        Page.Group.EntriesTab.DeleteOutput entryId ->
            submitEntryAction config model (\ctx ld -> GroupOps.deleteEntry ctx ld entryId)

        Page.Group.EntriesTab.RestoreOutput entryId ->
            submitEntryAction config model (\ctx ld -> GroupOps.restoreEntry ctx ld entryId)

        Page.Group.EntriesTab.EditOutput entryId ->
            case config.route of
                GroupRoute groupId _ ->
                    ( model, Cmd.none, [ NavigateTo (GroupRoute groupId (EditEntry entryId)) ] )

                _ ->
                    ( model, Cmd.none, [] )

        Page.Group.EntriesTab.DuplicateOutput entryId ->
            case ( config.route, model.loadedGroup ) of
                ( GroupRoute groupId _, Just loaded ) ->
                    case Dict.get entryId loaded.groupState.entries of
                        Just entryState ->
                            let
                                pending : PendingEntry
                                pending =
                                    case entryState.currentVersion.kind of
                                        Entry.Expense data ->
                                            PendingExpense data

                                        Entry.Transfer data ->
                                            PendingTransfer data
                            in
                            ( { model | pendingEntry = Just pending }
                            , Cmd.none
                            , [ NavigateTo (GroupRoute groupId NewEntry) ]
                            )

                        Nothing ->
                            ( model, Cmd.none, [] )

                _ ->
                    ( model, Cmd.none, [] )


handleMembersTabOutput : UpdateConfig -> Model -> Page.Group.MembersTab.Output -> ( Model, Cmd Msg, List Output )
handleMembersTabOutput config model output =
    case model.loadedGroup of
        Just loaded ->
            let
                submit : Event.Payload -> ( Model, Cmd Msg, List Output )
                submit payload =
                    runSubmit (OnMemberActionSaved loaded.summary.id) config model (\ctx -> GroupOps.event ctx loaded payload)
            in
            case output of
                Page.Group.MembersTab.RetireOutput memberId ->
                    submit (Event.MemberRetired { rootId = memberId })

                Page.Group.MembersTab.UnretireOutput memberId ->
                    submit (Event.MemberUnretired { rootId = memberId })

                Page.Group.MembersTab.EditMetadataOutput memberId ->
                    case config.route of
                        GroupRoute groupId _ ->
                            ( model, Cmd.none, [ NavigateTo (GroupRoute groupId (EditMemberMetadata memberId)) ] )

                        _ ->
                            ( model, Cmd.none, [] )

        Nothing ->
            ( model, Cmd.none, [] )


{-| Append event to loaded group, mark as unpushed, trigger sync, and emit time update.
Returns Nothing if the loaded group doesn't match the groupId.
-}
applyAndSync : UpdateConfig -> Group.Id -> Event.Envelope -> Model -> Maybe ( Model, Cmd Msg, List Output )
applyAndSync config groupId envelope model =
    appendEventAndRecompute model groupId envelope
        |> Maybe.map (addUnpushedIdToModel envelope.id)
        |> Maybe.map
            (\m ->
                let
                    ( summaryModel, summaryCmd, summaryOutputs ) =
                        syncGroupSummaryName config groupId m

                    ( syncModel, syncCmd ) =
                        triggerSyncInternal config groupId summaryModel
                in
                ( syncModel, Cmd.batch [ summaryCmd, syncCmd ], UpdateCurrentTime envelope.clientTimestamp :: summaryOutputs )
            )


{-| Append an event to the loaded group and recompute state.
-}
appendEventAndRecompute : Model -> Group.Id -> Event.Envelope -> Maybe Model
appendEventAndRecompute model groupId envelope =
    mapLoadedGroup (GroupOps.appendEvent envelope) groupId model


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


{-| Add an event ID to the in-memory unpushed set of the loaded group.
-}
addUnpushedIdToModel : String -> Model -> Model
addUnpushedIdToModel eventId model =
    case model.loadedGroup of
        Just loaded ->
            { model | loadedGroup = Just (GroupOps.addUnpushedId eventId loaded) }

        Nothing ->
            model


{-| Internal sync trigger. Skips if sync is already in progress.
-}
triggerSyncInternal : UpdateConfig -> Group.Id -> Model -> ( Model, Cmd Msg )
triggerSyncInternal config groupId model =
    if model.syncInProgress then
        ( model, Cmd.none )

    else
        case ( config.pbClient, model.loadedGroup ) of
            ( Just client, Just loaded ) ->
                if loaded.summary.id == groupId then
                    let
                        unpushedEvents : List Event.Envelope
                        unpushedEvents =
                            List.filter (\e -> Set.member e.id loaded.unpushedIds) loaded.events
                                |> List.reverse

                        notifyContext : Maybe PushServer.NotifyContext
                        notifyContext =
                            case ( List.isEmpty unpushedEvents, currentUserRootId model loaded ) of
                                ( False, Just actorId ) ->
                                    Just
                                        { groupId = groupId
                                        , groupName = loaded.groupState.groupMeta.name
                                        , actorRootId = actorId
                                        , actorName = GroupState.resolveMemberName loaded.groupState actorId
                                        , entries = loaded.groupState.entries
                                        , url = Route.toPath (GroupRoute groupId (Tab ActivityTab))
                                        }

                                _ ->
                                    Nothing

                        verifySignatures : Server.SyncResult -> ConcurrentTask x Server.SyncResult
                        verifySignatures syncResult =
                            EventVerification.filterVerifiedEvents loaded.groupState syncResult.pullResult.events
                                |> ConcurrentTask.mapError never
                                |> ConcurrentTask.map
                                    (\verifiedEvents ->
                                        { syncResult
                                            | pullResult =
                                                { events = verifiedEvents
                                                , cursor = syncResult.pullResult.cursor
                                                }
                                        }
                                    )
                    in
                    ( model.runner, Cmd.none )
                        |> Runner.andRun (OnGroupSynced groupId loaded.unpushedIds)
                            (Server.authenticateAndSync
                                { client = client, groupId = groupId, groupKey = loaded.groupKey }
                                config.identity.publicKeyHash
                                { unpushedEvents = unpushedEvents
                                , pullCursor = loaded.syncCursor
                                , notifyContext = notifyContext
                                }
                                |> ConcurrentTask.andThen verifySignatures
                            )
                        |> Tuple.mapFirst (\r -> { model | runner = r, syncInProgress = True })

                else
                    ( model, Cmd.none )

            _ ->
                ( model, Cmd.none )


{-| After a group event is applied, sync the summary fields and persist to IndexedDB.
-}
syncGroupSummaryName : UpdateConfig -> Group.Id -> Model -> ( Model, Cmd Msg, List Output )
syncGroupSummaryName config groupId model =
    case model.loadedGroup of
        Just loaded ->
            let
                updatedSummary : Group.Summary
                updatedSummary =
                    { id = groupId
                    , name = loaded.groupState.groupMeta.name
                    , defaultCurrency = loaded.summary.defaultCurrency
                    , isSubscribed = loaded.summary.isSubscribed
                    , isArchived = loaded.summary.isArchived
                    , createdAt = loaded.groupState.groupMeta.createdAt
                    , memberCount = Dict.size loaded.groupState.members
                    , myBalanceCents =
                        currentUserRootId model loaded
                            |> Maybe.andThen (\rid -> Dict.get rid loaded.groupState.balances)
                            |> Maybe.map .netBalance
                            |> Maybe.withDefault 0
                    }

                updatedModel : Model
                updatedModel =
                    { model | loadedGroup = Just { loaded | summary = updatedSummary } }
            in
            ( model.runner, Cmd.none )
                |> Runner.andRun OnGroupSummarySaved (Storage.saveGroupSummary config.db updatedSummary)
                |> (\( r, cmd ) -> ( { updatedModel | runner = r }, cmd, [ UpdateGroupSummary updatedSummary ] ))

        Nothing ->
            ( model, Cmd.none, [] )


toggleArchiveGroup : UpdateConfig -> Model -> LoadedGroup -> ( Model, Cmd Msg, List Output )
toggleArchiveGroup config model loaded =
    let
        updatedSummary : Group.Summary
        updatedSummary =
            { id = loaded.summary.id
            , name = loaded.summary.name
            , defaultCurrency = loaded.summary.defaultCurrency
            , isSubscribed = loaded.summary.isSubscribed
            , isArchived = not loaded.summary.isArchived
            , createdAt = loaded.summary.createdAt
            , memberCount = loaded.summary.memberCount
            , myBalanceCents = loaded.summary.myBalanceCents
            }

        updatedModel : Model
        updatedModel =
            { model | loadedGroup = Just { loaded | summary = updatedSummary } }
    in
    ( model.runner, Cmd.none )
        |> Runner.andRun OnGroupSummarySaved (Storage.saveGroupSummary config.db updatedSummary)
        |> (\( r, cmd ) ->
                ( { updatedModel | runner = r }
                , cmd
                , [ UpdateGroupSummary updatedSummary, NavigateTo Home ]
                )
           )


deleteGroup : UpdateConfig -> Model -> Group.Id -> ( Model, Cmd Msg, List Output )
deleteGroup config model groupId =
    ( model.runner, Cmd.none )
        |> Runner.andRun (OnGroupRemoved groupId) (Storage.deleteGroup config.db groupId)
        |> (\( r, cmd ) -> ( { model | runner = r }, cmd, [] ))


{-| Apply loaded group data from IndexedDB, constructing a LoadedGroup.
-}
applyLoadedGroup : UpdateConfig -> Group.Id -> List Event.Envelope -> Symmetric.Key -> Maybe String -> Set String -> Model -> Maybe Model
applyLoadedGroup config groupId events groupKey syncCursor unpushedIds model =
    Dict.get groupId config.groups
        |> Maybe.map (\summary -> GroupOps.initLoadedGroup events summary groupKey syncCursor unpushedIds)
        |> Maybe.map (\loaded -> { model | loadedGroup = Just loaded })


{-| Initialize the sub-page model for a given group view, if the needed data is available.
Mutation pages (NewEntry, EditEntry, AddVirtualMember, EditMemberMetadata, EditGroupMetadata)
are only initialized when the user is a member.
-}
initPagesIfNeeded : UpdateConfig -> GroupView -> Model -> ( Model, Cmd Msg )
initPagesIfNeeded config groupView model =
    case model.loadedGroup of
        Just loaded ->
            case ( groupView, currentUserRootId model loaded ) of
                ( NewEntry, Just userRootId ) ->
                    let
                        entryFormConfig : NewEntryShared.Config
                        entryFormConfig =
                            memberEntryFormConfig config userRootId loaded
                    in
                    case model.pendingEntry of
                        Just (PendingExpense data) ->
                            ( { model | newEntryModel = Page.Group.NewEntry.initDuplicate entryFormConfig (Entry.Expense data), pendingEntry = Nothing }, Cmd.none )

                        Just (PendingTransfer data) ->
                            ( { model | newEntryModel = Page.Group.NewEntry.initDuplicate entryFormConfig (Entry.Transfer data), pendingEntry = Nothing }, Cmd.none )

                        Nothing ->
                            ( { model | newEntryModel = Page.Group.NewEntry.init entryFormConfig }, Cmd.none )

                ( HighlightEntry entryId, _ ) ->
                    let
                        isDeleted : Bool
                        isDeleted =
                            Dict.get entryId loaded.groupState.entries
                                |> Maybe.map .isDeleted
                                |> Maybe.withDefault False
                    in
                    ( { model
                        | activeTab = EntriesTab
                        , entriesTabModel = Page.Group.EntriesTab.initWithHighlight entryId isDeleted
                      }
                    , scrollToEntryCmd entryId
                    )

                ( EditEntry entryId, Just userRootId ) ->
                    case Dict.get entryId loaded.groupState.entries of
                        Just entryState ->
                            ( { model | newEntryModel = Page.Group.NewEntry.initFromEntry (memberEntryFormConfig config userRootId loaded) entryState.currentVersion }, Cmd.none )

                        Nothing ->
                            ( model, Cmd.none )

                ( EditMemberMetadata memberId, Just _ ) ->
                    case Dict.get memberId loaded.groupState.members of
                        Just memberState ->
                            ( { model | editMemberMetadataModel = Page.Group.EditMemberMetadata.init memberState.rootId memberState.name memberState.metadata }, Cmd.none )

                        Nothing ->
                            ( model, Cmd.none )

                ( EditGroupMetadata, Just _ ) ->
                    ( { model | editGroupMetadataModel = Page.Group.EditGroupMetadata.init loaded.groupState.groupMeta }, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        Nothing ->
            ( model, Cmd.none )


{-| DOM id for an entry card element.
-}
entryDomId : Entry.Id -> String
entryDomId entryId =
    "entry-" ++ entryId


{-| Scroll to an entry card after a short delay to allow the DOM to render.
-}
scrollToEntryCmd : Entry.Id -> Cmd Msg
scrollToEntryCmd entryId =
    Process.sleep 50
        |> Task.andThen (\_ -> Browser.Dom.getElement (entryDomId entryId))
        |> Task.andThen (\el -> Browser.Dom.setViewport 0 el.element.y)
        |> Task.attempt ScrollToEntryResult


{-| Build entry form config for a confirmed member.
-}
memberEntryFormConfig : UpdateConfig -> Member.Id -> LoadedGroup -> NewEntryShared.Config
memberEntryFormConfig config userRootId loaded =
    { currentUserRootId = userRootId
    , activeMembersRootIds = List.map .rootId (GroupState.activeMembers loaded.groupState)
    , today = Date.posixToDate config.currentTime
    , defaultCurrency = loaded.summary.defaultCurrency
    }


{-| Resolve the current user's member root ID within a loaded group.
Returns Nothing if the user is not a member of this group.
-}
currentUserRootId : Model -> LoadedGroup -> Maybe Member.Id
currentUserRootId model loaded =
    GroupState.resolveMemberRootId loaded.groupState model.identityHash


{-| Handle an incoming realtime event record.
-}
handleRealtimeRecord : UpdateConfig -> LoadedGroup -> Json.Decode.Value -> Model -> ( Model, Cmd Msg )
handleRealtimeRecord config loaded record model =
    case Json.Decode.decodeValue Server.realtimeEventDecoder record of
        Ok serverEvt ->
            if serverEvt.groupId == loaded.summary.id then
                case Json.Decode.decodeString Symmetric.encryptedDataDecoder serverEvt.eventData of
                    Ok _ ->
                        -- We need to decrypt async, but for now just trigger a pull
                        triggerSyncInternal config loaded.summary.id model

                    Err _ ->
                        ( model, Cmd.none )

            else
                ( model, Cmd.none )

        Err _ ->
            ( model, Cmd.none )



-- VIEW


{-| Result of rendering a group page: the main content plus an optional
viewport-level overlay (e.g. the tab bar) to be placed in Ui.layout's Ui.inFront.
-}
type alias ViewResult msg =
    { content : Ui.Element msg
    , overlay : Maybe (Ui.Element msg)
    }


{-| Render the group page for a given route, dispatching to the right sub-page view.
Handles loading state internally.
-}
view : ViewConfig msg -> GroupView -> Model -> ViewResult msg
view config groupView model =
    case model.loadedGroup of
        Just loaded ->
            if loaded.summary.id == config.groupId then
                viewGroupPage config groupView loaded model

            else
                { content = viewLoadingShell config, overlay = Nothing }

        Nothing ->
            { content = viewLoadingShell config, overlay = Nothing }


viewLoadingShell : ViewConfig msg -> Ui.Element msg
viewLoadingShell config =
    UI.Shell.pageShell { title = T.shellPartage config.i18n, onBack = config.onNavigateHome } <|
        Ui.el [ Ui.Font.size Theme.font.sm, Ui.Font.color Theme.base.textSubtle ]
            (Ui.text (T.loadingGroup config.i18n))


viewGroupPage : ViewConfig msg -> GroupView -> LoadedGroup -> Model -> ViewResult msg
viewGroupPage config groupView loaded model =
    let
        noOverlay : Ui.Element msg -> ViewResult msg
        noOverlay content =
            { content = content, overlay = Nothing }

        maybeUserRootId : Maybe Member.Id
        maybeUserRootId =
            currentUserRootId model loaded
    in
    case ( groupView, maybeUserRootId ) of
        ( Tab tab, _ ) ->
            viewTabs config maybeUserRootId loaded { model | activeTab = tab }

        ( HighlightEntry _, _ ) ->
            viewTabs config maybeUserRootId loaded { model | activeTab = EntriesTab }

        ( Join _, _ ) ->
            -- Handled by Main.elm, should not reach here
            noOverlay Ui.none

        ( NewEntry, Just _ ) ->
            noOverlay <|
                pageShell config (T.shellNewEntry config.i18n) <|
                    Page.Group.NewEntry.view config.i18n
                        (GroupState.activeMembers loaded.groupState)
                        (config.toMsg << NewEntryMsg)
                        model.newEntryModel

        ( EditEntry _, Just _ ) ->
            noOverlay <|
                pageShell config (T.editEntryTitle config.i18n) <|
                    Page.Group.NewEntry.view config.i18n
                        (GroupState.activeMembers loaded.groupState)
                        (config.toMsg << NewEntryMsg)
                        model.newEntryModel

        ( AddVirtualMember, Just _ ) ->
            noOverlay <|
                pageShell config (T.memberAddTitle config.i18n) <|
                    Page.Group.AddMember.view config.i18n
                        (config.toMsg << AddMemberMsg)
                        model.addMemberModel

        ( EditMemberMetadata _, Just _ ) ->
            noOverlay <|
                pageShell config (T.memberEditMetadataButton config.i18n) <|
                    Page.Group.EditMemberMetadata.view config.i18n
                        (config.toMsg << EditMemberMetadataMsg)
                        model.editMemberMetadataModel

        ( EditGroupMetadata, Just _ ) ->
            noOverlay <|
                pageShell config (T.groupSettingsTitle config.i18n) <|
                    Page.Group.EditGroupMetadata.view config.i18n
                        loaded.summary.isArchived
                        (config.toMsg << EditGroupMetadataMsg)
                        model.editGroupMetadataModel

        -- Non-member trying to access a mutation page: fallback to balance tab
        ( _, Nothing ) ->
            viewTabs config Nothing loaded { model | activeTab = BalanceTab }


pageShell : ViewConfig msg -> String -> Ui.Element msg -> Ui.Element msg
pageShell config title content =
    UI.Shell.pageShell { title = title, onBack = config.onGoBack } content


viewTabs : ViewConfig msg -> Maybe Member.Id -> LoadedGroup -> Model -> ViewResult msg
viewTabs config maybeUserRootId loaded model =
    let
        tabHref : GroupTab -> String
        tabHref tab =
            Route.toPath (GroupRoute config.groupId (Tab tab))

        fab : Ui.Element msg
        fab =
            case maybeUserRootId of
                Just _ ->
                    UI.Components.fab
                        { label = "+"
                        , href = Route.toPath (GroupRoute config.groupId NewEntry)
                        , onPress = config.toMsg (RequestNavigation NewEntry)
                        }

                Nothing ->
                    Ui.none
    in
    { content =
        UI.Shell.tabbedShell
            { title = loaded.groupState.groupMeta.name
            , subtitle = ""
            , onBack = config.onNavigateHome
            , content =
                case maybeUserRootId of
                    Just _ ->
                        tabContent config maybeUserRootId loaded model

                    Nothing ->
                        Ui.column [ Ui.spacing Theme.spacing.md, Ui.width Ui.fill ]
                            [ UI.Components.readOnlyBanner config.i18n
                            , tabContent config maybeUserRootId loaded model
                            ]
            }
    , overlay =
        Just <|
            Ui.column [ Ui.spacing Theme.spacing.lg ]
                [ fab

                -- Tab bar
                , UI.Shell.tabBar
                    { balance = T.tabBalance config.i18n
                    , entries = T.tabEntries config.i18n
                    , members = T.tabMembers config.i18n
                    , activity = T.tabActivity config.i18n
                    }
                    tabHref
                    model.activeTab
                    (\tab -> config.toMsg (RequestNavigation (Tab tab)))
                ]
    }


tabContent : ViewConfig msg -> Maybe Member.Id -> LoadedGroup -> Model -> Ui.Element msg
tabContent config maybeUserRootId loaded model =
    case model.activeTab of
        BalanceTab ->
            Page.Group.BalanceTab.view config.i18n
                { onRecordTransfer = \tx -> config.toMsg (SettleTransaction tx)
                , onSavePreferences = \prefData -> config.toMsg (SaveSettlementPreferences prefData)
                , onNewTransfer = \payData -> config.toMsg (RequestTransfer payData)
                , newTransferHref = Route.toPath (GroupRoute config.groupId NewEntry)
                , toMsg = config.toMsg << BalanceTabMsg
                }
                maybeUserRootId
                model.balanceTabModel
                loaded.groupState

        EntriesTab ->
            Page.Group.EntriesTab.view config.i18n
                { onNewEntry = config.toMsg (RequestNavigation NewEntry)
                , newEntryHref = Route.toPath (GroupRoute config.groupId NewEntry)
                , entryLinkHref = \entryId -> config.origin ++ Route.toPath (GroupRoute config.groupId (HighlightEntry entryId))
                , toMsg = config.toMsg << EntriesTabMsg
                }
                maybeUserRootId
                config.today
                model.entriesTabModel
                loaded.groupState

        MembersTab ->
            Page.Group.MembersTab.view config.i18n
                { onAddMember = config.toMsg (RequestNavigation AddVirtualMember)
                , addMemberHref = Route.toPath (GroupRoute config.groupId AddVirtualMember)
                , onEditGroupMetadata = config.toMsg (RequestNavigation EditGroupMetadata)
                , editGroupMetadataHref = Route.toPath (GroupRoute config.groupId EditGroupMetadata)
                , inviteLink = config.origin ++ Route.toPath (GroupRoute config.groupId (Join (Symmetric.exportKey loaded.groupKey)))
                , isSynced = loaded.syncCursor /= Nothing
                , onToggleNotification = config.toMsg ToggleNotification
                , isSubscribed = loaded.summary.isSubscribed
                , pushActive = config.pushActive
                }
                (config.toMsg << MembersTabMsg)
                model.membersTabModel
                maybeUserRootId
                loaded.groupState

        ActivityTab ->
            let
                allMembers : List ( Member.Id, String )
                allMembers =
                    GroupState.activeMembers loaded.groupState
                        |> List.map (\m -> ( m.rootId, m.name ))
                        |> List.sortBy Tuple.second
            in
            Page.Group.ActivityTab.view config.i18n
                { resolveName = GroupState.resolveMemberName loaded.groupState
                , currentUserRootId = maybeUserRootId
                , groupDefaultCurrency = loaded.summary.defaultCurrency
                , entryLinkHref = \entryId -> Route.toPath (GroupRoute config.groupId (HighlightEntry entryId))
                , onNavigateToEntry = \entryId -> config.toMsg (RequestNavigation (HighlightEntry entryId))
                , toMsg = config.toMsg << ActivityTabMsg
                , allMembers = allMembers
                }
                model.activityTabModel
                loaded.groupState.activities
