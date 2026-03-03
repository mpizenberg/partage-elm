module Page.Group exposing
    ( InitConfig
    , Model
    , Msg
    , Output(..)
    , UpdateConfig
    , ViewConfig
    , handleNavigation
    , init
    , pocketbaseEventMsg
    , resetLoadedGroup
    , setIdentityHash
    , taskSubscription
    , triggerSync
    , update
    , view
    )

{-| Group page shell with tab routing, using real group data.

Owns its own ConcurrentTask.Pool and handles all group business logic
(event submission, sync, loading, output handling) internally.

-}

import ConcurrentTask
import Dict exposing (Dict)
import Domain.Currency exposing (Currency(..))
import Domain.Date as Date exposing (Date)
import Domain.Entry as Entry
import Domain.Event as Event
import Domain.Group as Group
import Domain.GroupState as GroupState exposing (GroupState)
import Domain.Member as Member
import Domain.Settlement as Settlement
import Identity exposing (Identity)
import IndexedDb as Idb
import Json.Decode
import Json.Encode
import Page.Group.ActivityTab
import Page.Group.AddMember
import Page.Group.BalanceTab
import Page.Group.EditGroupMetadata
import Page.Group.EditMemberMetadata
import Page.Group.EntriesTab
import Page.Group.EntryDetail
import Page.Group.MemberDetail
import Page.Group.MembersTab
import Page.Group.NewEntry
import Page.NotFound
import PocketBase
import PocketBase.Realtime
import Random
import Route exposing (GroupTab(..), GroupView(..), Route(..))
import Server
import Set exposing (Set)
import Storage exposing (GroupSummary)
import Submit exposing (LoadedGroup)
import Time
import Translations as T exposing (I18n)
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
    , randomSeed : Random.Seed
    , uuidState : UUID.V7State
    }


{-| Runtime dependencies provided by Main on each update call.
-}
type alias UpdateConfig =
    { sendTask : Json.Encode.Value -> Cmd Msg
    , db : Idb.Db
    , identity : Identity
    , pbClient : Maybe PocketBase.Client
    , currentTime : Time.Posix
    , route : Route
    , i18n : I18n
    , groups : Dict Group.Id GroupSummary
    }


{-| View configuration, much simpler than the old Context.
-}
type alias ViewConfig msg =
    { i18n : I18n
    , toMsg : Msg -> msg
    , today : Date
    , groupId : Group.Id
    }



-- MODEL


type alias Model =
    -- ConcurrentTask pool and RNG state
    { pool : ConcurrentTask.Pool Msg
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

    -- Member pages
    , memberDetailModel : Page.Group.MemberDetail.Model
    , addMemberModel : Page.Group.AddMember.Model
    , editMemberMetadataModel : Page.Group.EditMemberMetadata.Model

    -- Entry pages
    , newEntryModel : Page.Group.NewEntry.Model
    , entryDetailModel : Page.Group.EntryDetail.Model
    , pendingTransfer : Maybe { toMemberId : Member.Id, amountCents : Int }

    -- Group pages
    , editGroupMetadataModel : Page.Group.EditGroupMetadata.Model
    }



-- MSG


taskSubscription : { send : Json.Encode.Value -> Cmd Msg, receive : (Json.Decode.Value -> Msg) -> Sub Msg } -> Model -> Sub Msg
taskSubscription ports model =
    ConcurrentTask.onProgress
        { send = ports.send
        , receive = ports.receive
        , onProgress = OnTaskProgress
        }
        model.pool


pocketbaseEventMsg : Json.Decode.Value -> Msg
pocketbaseEventMsg =
    OnPocketbaseEvent


type
    Msg
    -- Pool progress
    = OnTaskProgress ( ConcurrentTask.Pool Msg, Cmd Msg )
      -- Navigation
    | RequestNavigation GroupView
      -- Tabs
    | EntriesTabMsg Page.Group.EntriesTab.Msg
    | BalanceTabMsg Page.Group.BalanceTab.Msg
    | ActivityTabMsg Page.Group.ActivityTab.Msg
      -- Member pages
    | MemberDetailMsg Page.Group.MemberDetail.Msg
    | AddMemberMsg Page.Group.AddMember.Msg
    | EditMemberMetadataMsg Page.Group.EditMemberMetadata.Msg
      -- Entry pages
    | NewEntryMsg Page.Group.NewEntry.Msg
    | EntryDetailMsg Page.Group.EntryDetail.Msg
      -- Group pages
    | EditGroupMetadataMsg Page.Group.EditGroupMetadata.Msg
      -- User actions
    | PayMember { toMemberId : Member.Id, amountCents : Int }
    | SettleTransaction Settlement.Transaction
    | SaveSettlementPreferences { memberRootId : Member.Id, preferredRecipients : List Member.Id }
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



-- OUTPUT


{-| Outputs produced by Page.Group that Main needs to handle.
-}
type Output
    = NavigateTo Route
    | ShowToast Toast.ToastLevel String
    | UpdateGroupSummary GroupSummary
    | RemoveGroup Group.Id



-- INIT


init : InitConfig -> Model
init config =
    { pool = config.pool
    , randomSeed = config.randomSeed
    , uuidState = config.uuidState
    , identityHash = ""
    , loadedGroup = Nothing
    , syncInProgress = False
    , activeTab = BalanceTab
    , entriesTabModel = Page.Group.EntriesTab.init
    , balanceTabModel = Page.Group.BalanceTab.init
    , activityTabModel = Page.Group.ActivityTab.init
    , memberDetailModel = Page.Group.MemberDetail.init Member.emptyChainState
    , addMemberModel = Page.Group.AddMember.init
    , editMemberMetadataModel = Page.Group.EditMemberMetadata.init "" "" Member.emptyMetadata
    , newEntryModel = Page.Group.NewEntry.init { currentUserRootId = "", activeMembersRootIds = [], today = { year = 2000, month = 1, day = 1 }, defaultCurrency = EUR }
    , entryDetailModel = Page.Group.EntryDetail.init
    , pendingTransfer = Nothing
    , editGroupMetadataModel = Page.Group.EditGroupMetadata.init GroupState.empty.groupMeta
    }



-- EXPOSED FUNCTIONS


{-| Handle navigation to a group view. Combines ensureGroupLoaded + initPagesIfNeeded.
-}
handleNavigation : UpdateConfig -> Group.Id -> GroupView -> Model -> ( Model, Cmd Msg )
handleNavigation config groupId groupView model =
    let
        ( modelAfterLoad, loadCmd ) =
            ensureGroupLoaded config groupId model

        modelAfterInit : Model
        modelAfterInit =
            initPagesIfNeeded config groupView modelAfterLoad
    in
    ( modelAfterInit, loadCmd )


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


{-| Set the identity hash. Called by Main on OnInitComplete / OnIdentityGenerated.
-}
setIdentityHash : String -> Model -> Model
setIdentityHash hash model =
    { model | identityHash = hash }



-- UPDATE


update : UpdateConfig -> Msg -> Model -> ( Model, Cmd Msg, List Output )
update config msg model =
    case msg of
        OnTaskProgress ( pool, cmd ) ->
            ( { model | pool = pool }, cmd, [] )

        RequestNavigation groupView ->
            case config.route of
                GroupRoute groupId _ ->
                    ( model, Cmd.none, [ NavigateTo (GroupRoute groupId groupView) ] )

                _ ->
                    ( model, Cmd.none, [] )

        -- Tab sub-page messages
        EntriesTabMsg subMsg ->
            ( { model | entriesTabModel = Page.Group.EntriesTab.update subMsg model.entriesTabModel }, Cmd.none, [] )

        BalanceTabMsg subMsg ->
            ( { model | balanceTabModel = Page.Group.BalanceTab.update subMsg model.balanceTabModel }, Cmd.none, [] )

        ActivityTabMsg subMsg ->
            ( { model | activityTabModel = Page.Group.ActivityTab.update subMsg model.activityTabModel }, Cmd.none, [] )

        -- Member detail
        MemberDetailMsg subMsg ->
            let
                ( memberDetailModel, maybeOutput ) =
                    Page.Group.MemberDetail.update subMsg model.memberDetailModel

                modelWithPage : Model
                modelWithPage =
                    { model | memberDetailModel = memberDetailModel }
            in
            case maybeOutput of
                Just detailOutput ->
                    handleMemberDetailOutput config modelWithPage detailOutput

                Nothing ->
                    ( modelWithPage, Cmd.none, [] )

        -- Add member
        AddMemberMsg subMsg ->
            let
                ( addMemberModel, maybeOutput ) =
                    Page.Group.AddMember.update subMsg model.addMemberModel

                modelWithPage : Model
                modelWithPage =
                    { model | addMemberModel = addMemberModel }
            in
            case ( maybeOutput, model.loadedGroup ) of
                ( Just addOutput, Just loaded ) ->
                    submitAddMember config modelWithPage loaded addOutput

                _ ->
                    ( modelWithPage, Cmd.none, [] )

        -- Edit member metadata
        EditMemberMetadataMsg subMsg ->
            let
                ( editModel, maybeOutput ) =
                    Page.Group.EditMemberMetadata.update subMsg model.editMemberMetadataModel

                modelWithPage : Model
                modelWithPage =
                    { model | editMemberMetadataModel = editModel }
            in
            case ( maybeOutput, model.loadedGroup ) of
                ( Just metaOutput, Just loaded ) ->
                    submitMemberMetadata config modelWithPage loaded metaOutput

                _ ->
                    ( modelWithPage, Cmd.none, [] )

        -- New entry / edit entry
        NewEntryMsg subMsg ->
            let
                ( newEntryModel, maybeOutput ) =
                    Page.Group.NewEntry.update subMsg model.newEntryModel

                modelWithPage : Model
                modelWithPage =
                    { model | newEntryModel = newEntryModel }
            in
            case ( maybeOutput, model.loadedGroup ) of
                ( Just entryOutput, Just loaded ) ->
                    case config.route of
                        GroupRoute _ (EditEntry entryId) ->
                            submitEditEntry config modelWithPage loaded entryId entryOutput

                        _ ->
                            submitNewEntry config modelWithPage loaded entryOutput

                _ ->
                    ( modelWithPage, Cmd.none, [] )

        -- Entry detail
        EntryDetailMsg subMsg ->
            let
                ( entryDetailModel, maybeOutput ) =
                    Page.Group.EntryDetail.update subMsg model.entryDetailModel

                modelWithPage : Model
                modelWithPage =
                    { model | entryDetailModel = entryDetailModel }
            in
            case maybeOutput of
                Just detailOutput ->
                    handleEntryDetailOutput config modelWithPage detailOutput

                Nothing ->
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

            else
                case ( result.metadataOutput, model.loadedGroup ) of
                    ( Just change, Just loaded ) ->
                        submitGroupMetadata config modelWithPage loaded change

                    _ ->
                        ( modelWithPage, Cmd.none, [] )

        -- User actions
        PayMember payData ->
            case config.route of
                GroupRoute groupId _ ->
                    ( { model | pendingTransfer = Just payData }
                    , Cmd.none
                    , [ NavigateTo (GroupRoute groupId NewEntry) ]
                    )

                _ ->
                    ( model, Cmd.none, [] )

        SettleTransaction tx ->
            case model.loadedGroup of
                Just loaded ->
                    let
                        output : Page.Group.NewEntry.Output
                        output =
                            Page.Group.NewEntry.TransferOutput
                                { amountCents = tx.amount
                                , currency = loaded.summary.defaultCurrency
                                , defaultCurrencyAmount = Nothing
                                , fromMemberId = tx.from
                                , toMemberId = tx.to
                                , notes = Nothing
                                , date = Date.posixToDate config.currentTime
                                }
                    in
                    submitNewEntry config model loaded output

                Nothing ->
                    ( model, Cmd.none, [] )

        SaveSettlementPreferences prefData ->
            case model.loadedGroup of
                Just loaded ->
                    submitEvent (OnEntryActionSaved loaded.summary.id)
                        config
                        model
                        loaded
                        (Event.SettlementPreferencesUpdated prefData)

                Nothing ->
                    ( model, Cmd.none, [] )

        -- Async response handlers
        OnEntrySaved groupId (ConcurrentTask.Success envelope) ->
            case appendEventAndRecompute model groupId envelope of
                Just updatedModel ->
                    let
                        modelWithUnpushed : Model
                        modelWithUnpushed =
                            addUnpushedIdToModel envelope.id updatedModel

                        ( syncModel, syncCmd ) =
                            triggerSyncInternal config groupId modelWithUnpushed
                    in
                    case config.route of
                        GroupRoute _ (Tab BalanceTab) ->
                            ( syncModel
                            , syncCmd
                            , [ ShowToast Toast.Success (T.toastSettlementRecorded config.i18n) ]
                            )

                        _ ->
                            ( syncModel
                            , syncCmd
                            , [ NavigateTo (GroupRoute groupId (Tab EntriesTab)) ]
                            )

                Nothing ->
                    ( model, Cmd.none, [] )

        OnEntrySaved _ _ ->
            ( model, Cmd.none, [ ShowToast Toast.Error (T.toastEntrySaveError config.i18n) ] )

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
                    triggerSyncInternal config groupId modelWithUnpushed
            in
            case Toast.entryActionMessage config.i18n envelope.payload of
                Just message ->
                    ( syncModel, syncCmd, [ ShowToast Toast.Success message ] )

                Nothing ->
                    ( syncModel, syncCmd, [] )

        OnEntryActionSaved _ _ ->
            ( model, Cmd.none, [ ShowToast Toast.Error (T.toastEntryActionError config.i18n) ] )

        OnMemberActionSaved groupId (ConcurrentTask.Success envelope) ->
            case appendEventAndRecompute model groupId envelope of
                Just updatedModel ->
                    let
                        modelWithUnpushed : Model
                        modelWithUnpushed =
                            addUnpushedIdToModel envelope.id updatedModel

                        ( syncModel, syncCmd ) =
                            triggerSyncInternal config groupId modelWithUnpushed
                    in
                    case config.route of
                        GroupRoute gid AddVirtualMember ->
                            ( { syncModel | addMemberModel = Page.Group.AddMember.init }
                            , syncCmd
                            , [ NavigateTo (GroupRoute gid (Tab MembersTab)) ]
                            )

                        GroupRoute gid (EditMemberMetadata memberId) ->
                            ( syncModel
                            , syncCmd
                            , [ NavigateTo (GroupRoute gid (MemberDetail memberId)) ]
                            )

                        _ ->
                            ( initPagesIfNeeded config (routeToGroupView config.route) syncModel
                            , syncCmd
                            , []
                            )

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
                    , NavigateTo (GroupRoute groupId (Tab MembersTab)) :: summaryOutputs
                    )

                Nothing ->
                    ( model, Cmd.none, [] )

        OnGroupMetadataActionSaved _ _ ->
            ( model, Cmd.none, [ ShowToast Toast.Error (T.toastGroupSettingsError config.i18n) ] )

        OnGroupRemoved groupId (ConcurrentTask.Success _) ->
            ( { model | loadedGroup = Nothing }
            , Cmd.none
            , [ RemoveGroup groupId
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
                modelAfterLoad : Model
                modelAfterLoad =
                    applyLoadedGroup config groupId result.events result.groupKey result.syncCursor result.unpushedIds model
                        |> Maybe.map (initPagesIfNeeded config (routeToGroupView config.route))
                        |> Maybe.withDefault model
            in
            -- Only sync if group has been synced before (has a cursor).
            -- Freshly created groups sync via OnServerGroupCreated instead.
            case result.syncCursor of
                Just _ ->
                    let
                        ( syncModel, syncCmd ) =
                            triggerSyncInternal config groupId modelAfterLoad
                    in
                    ( syncModel, syncCmd, [] )

                Nothing ->
                    ( modelAfterLoad, Cmd.none, [] )

        OnGroupEventsLoaded _ _ ->
            ( model, Cmd.none, [] )

        OnGroupSynced groupId pushedIds (ConcurrentTask.Success syncResult) ->
            case model.loadedGroup of
                Just loaded ->
                    if loaded.summary.id == groupId then
                        let
                            result : Submit.SyncApplyResult
                            result =
                                Submit.applySyncResult pushedIds syncResult loaded

                            ( taskPool, taskCmds ) =
                                ConcurrentTask.attempt
                                    { pool = model.pool
                                    , send = config.sendTask
                                    , onComplete = PostSyncTasksDone
                                    }
                                    (Submit.postSyncTasks config.db groupId config.pbClient result)

                            modelAfterSync : Model
                            modelAfterSync =
                                { model
                                    | loadedGroup = Just result.updatedGroup
                                    , pool = taskPool
                                    , syncInProgress = False
                                }
                                    |> initPagesIfNeeded config (routeToGroupView config.route)
                        in
                        -- If new events were added during sync, trigger follow-up
                        if Set.isEmpty result.updatedGroup.unpushedIds then
                            ( modelAfterSync, taskCmds, [] )

                        else
                            let
                                ( followUpModel, followUpCmd ) =
                                    triggerSyncInternal config groupId modelAfterSync
                            in
                            ( followUpModel, Cmd.batch [ taskCmds, followUpCmd ], [] )

                    else
                        ( { model | syncInProgress = False }, Cmd.none, [] )

                Nothing ->
                    ( { model | syncInProgress = False }, Cmd.none, [] )

        OnGroupSynced _ _ (ConcurrentTask.Error err) ->
            -- Sync failed — unpushedIds preserved, will retry on next sync
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


{-| Build a Submit.Context from our config and model. No Maybe — UpdateConfig guarantees identity.
-}
submitContext : (ConcurrentTask.Response Idb.Error Event.Envelope -> Msg) -> UpdateConfig -> Model -> Submit.Context Msg
submitContext onComplete config model =
    { pool = model.pool
    , sendTask = config.sendTask
    , onComplete = onComplete
    , randomSeed = model.randomSeed
    , uuidState = model.uuidState
    , currentTime = config.currentTime
    , db = config.db
    , identity = config.identity
    }


{-| Apply the pool/seed/uuid state returned from a Submit operation.
-}
applySubmitResult : Model -> ( Submit.State Msg, Cmd Msg ) -> ( Model, Cmd Msg )
applySubmitResult model ( state, cmd ) =
    ( { model
        | pool = state.pool
        , randomSeed = state.randomSeed
        , uuidState = state.uuidState
      }
    , cmd
    )


submitNewEntry : UpdateConfig -> Model -> LoadedGroup -> Page.Group.NewEntry.Output -> ( Model, Cmd Msg, List Output )
submitNewEntry config model loaded output =
    let
        ctx : Submit.Context Msg
        ctx =
            submitContext (OnEntrySaved loaded.summary.id) config model

        ( updatedModel, cmd ) =
            applySubmitResult model (Submit.newEntry ctx loaded output)
    in
    ( updatedModel, cmd, [] )


submitEditEntry : UpdateConfig -> Model -> LoadedGroup -> Entry.Id -> Page.Group.NewEntry.Output -> ( Model, Cmd Msg, List Output )
submitEditEntry config model loaded originalEntryId output =
    let
        ctx : Submit.Context Msg
        ctx =
            submitContext (OnEntrySaved loaded.summary.id) config model
    in
    case Submit.editEntry ctx loaded originalEntryId output of
        Just result ->
            let
                ( updatedModel, cmd ) =
                    applySubmitResult model result
            in
            ( updatedModel, cmd, [] )

        Nothing ->
            ( model, Cmd.none, [] )


submitEntryAction : UpdateConfig -> Model -> (Submit.Context Msg -> LoadedGroup -> ( Submit.State Msg, Cmd Msg )) -> ( Model, Cmd Msg, List Output )
submitEntryAction config model action =
    case model.loadedGroup of
        Just loaded ->
            let
                ctx : Submit.Context Msg
                ctx =
                    submitContext (OnEntryActionSaved loaded.summary.id) config model

                ( updatedModel, cmd ) =
                    applySubmitResult model (action ctx loaded)
            in
            ( updatedModel, cmd, [] )

        Nothing ->
            ( model, Cmd.none, [] )


submitEvent : (ConcurrentTask.Response Idb.Error Event.Envelope -> Msg) -> UpdateConfig -> Model -> LoadedGroup -> Event.Payload -> ( Model, Cmd Msg, List Output )
submitEvent onComplete config model loaded payload =
    let
        ctx : Submit.Context Msg
        ctx =
            submitContext onComplete config model

        ( updatedModel, cmd ) =
            applySubmitResult model (Submit.event ctx loaded payload)
    in
    ( updatedModel, cmd, [] )


submitAddMember : UpdateConfig -> Model -> LoadedGroup -> Page.Group.AddMember.Output -> ( Model, Cmd Msg, List Output )
submitAddMember config model loaded output =
    let
        ctx : Submit.Context Msg
        ctx =
            submitContext (OnMemberActionSaved loaded.summary.id) config model

        ( updatedModel, cmd ) =
            applySubmitResult model (Submit.addMember ctx loaded output)
    in
    ( updatedModel, cmd, [] )


submitMemberMetadata : UpdateConfig -> Model -> LoadedGroup -> Page.Group.EditMemberMetadata.Output -> ( Model, Cmd Msg, List Output )
submitMemberMetadata config model loaded output =
    let
        ctx1 : Submit.Context Msg
        ctx1 =
            submitContext (OnMemberActionSaved loaded.summary.id) config model

        ( modelAfterMeta, metaCmd ) =
            applySubmitResult model (Submit.event ctx1 loaded (Event.MemberMetadataUpdated { rootId = output.memberId, metadata = output.metadata }))
    in
    if output.newName /= output.oldName then
        let
            ctx2 : Submit.Context Msg
            ctx2 =
                submitContext (OnMemberActionSaved loaded.summary.id) config modelAfterMeta

            ( modelAfterRename, renameCmd ) =
                applySubmitResult modelAfterMeta
                    (Submit.event ctx2
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


submitGroupMetadata : UpdateConfig -> Model -> LoadedGroup -> Event.GroupMetadataChange -> ( Model, Cmd Msg, List Output )
submitGroupMetadata config model loaded change =
    submitEvent (OnGroupMetadataActionSaved loaded.summary.id)
        config
        model
        loaded
        (Event.GroupMetadataUpdated change)


handleEntryDetailOutput : UpdateConfig -> Model -> Page.Group.EntryDetail.Output -> ( Model, Cmd Msg, List Output )
handleEntryDetailOutput config model output =
    case output of
        Page.Group.EntryDetail.DeleteRequested ->
            case config.route of
                GroupRoute _ (EntryDetail entryId) ->
                    submitEntryAction config model (\ctx ld -> Submit.deleteEntry ctx ld entryId)

                _ ->
                    ( model, Cmd.none, [] )

        Page.Group.EntryDetail.RestoreRequested ->
            case config.route of
                GroupRoute _ (EntryDetail entryId) ->
                    submitEntryAction config model (\ctx ld -> Submit.restoreEntry ctx ld entryId)

                _ ->
                    ( model, Cmd.none, [] )

        Page.Group.EntryDetail.EditRequested ->
            case config.route of
                GroupRoute groupId (EntryDetail entryId) ->
                    ( model, Cmd.none, [ NavigateTo (GroupRoute groupId (EditEntry entryId)) ] )

                _ ->
                    ( model, Cmd.none, [] )

        Page.Group.EntryDetail.BackRequested ->
            case config.route of
                GroupRoute groupId _ ->
                    ( model, Cmd.none, [ NavigateTo (GroupRoute groupId (Tab EntriesTab)) ] )

                _ ->
                    ( model, Cmd.none, [] )


handleMemberDetailOutput : UpdateConfig -> Model -> Page.Group.MemberDetail.Output -> ( Model, Cmd Msg, List Output )
handleMemberDetailOutput config model output =
    case model.loadedGroup of
        Just loaded ->
            let
                submit : Event.Payload -> ( Model, Cmd Msg, List Output )
                submit =
                    submitEvent (OnMemberActionSaved loaded.summary.id) config model loaded
            in
            case output of
                Page.Group.MemberDetail.RenameOutput data ->
                    submit
                        (Event.MemberRenamed
                            { rootId = data.memberId
                            , oldName = data.oldName
                            , newName = data.newName
                            }
                        )

                Page.Group.MemberDetail.RetireOutput memberId ->
                    submit (Event.MemberRetired { rootId = memberId })

                Page.Group.MemberDetail.UnretireOutput memberId ->
                    submit (Event.MemberUnretired { rootId = memberId })

                Page.Group.MemberDetail.NavigateToEditMetadata ->
                    case config.route of
                        GroupRoute groupId (MemberDetail memberId) ->
                            ( model, Cmd.none, [ NavigateTo (GroupRoute groupId (EditMemberMetadata memberId)) ] )

                        _ ->
                            ( model, Cmd.none, [] )

                Page.Group.MemberDetail.NavigateBack ->
                    case config.route of
                        GroupRoute groupId _ ->
                            ( model, Cmd.none, [ NavigateTo (GroupRoute groupId (Tab MembersTab)) ] )

                        _ ->
                            ( model, Cmd.none, [] )

        Nothing ->
            ( model, Cmd.none, [] )


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
                                            config.identity.publicKeyHash
                                            { unpushedEvents = unpushedEvents
                                            , pullCursor = loaded.syncCursor
                                            }
                                    )

                        ( pool, cmd ) =
                            ConcurrentTask.attempt
                                { pool = model.pool
                                , send = config.sendTask
                                , onComplete = OnGroupSynced groupId pushedIds
                                }
                                syncTask
                    in
                    ( { model | pool = pool, syncInProgress = True }, cmd )

                else
                    ( model, Cmd.none )

            _ ->
                ( model, Cmd.none )


{-| After a group metadata event is applied, sync the group name in the summary and persist to IndexedDB.
-}
syncGroupSummaryName : UpdateConfig -> Group.Id -> Model -> ( Model, Cmd Msg, List Output )
syncGroupSummaryName config groupId model =
    case model.loadedGroup of
        Just loaded ->
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
                        , send = config.sendTask
                        , onComplete = OnGroupSummarySaved
                        }
                        (Storage.saveGroupSummary config.db updatedSummary)
            in
            ( { model
                | loadedGroup = Just { loaded | summary = updatedSummary }
                , pool = pool
              }
            , cmd
            , [ UpdateGroupSummary updatedSummary ]
            )

        Nothing ->
            ( model, Cmd.none, [] )


deleteGroup : UpdateConfig -> Model -> Group.Id -> ( Model, Cmd Msg, List Output )
deleteGroup config model groupId =
    let
        ( pool, cmd ) =
            ConcurrentTask.attempt
                { pool = model.pool
                , send = config.sendTask
                , onComplete = OnGroupRemoved groupId
                }
                (Storage.deleteGroup config.db groupId)
    in
    ( { model | pool = pool }, cmd, [] )


{-| Append an event to the loaded group and recompute state.
-}
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


{-| Apply loaded group data from IndexedDB, constructing a LoadedGroup.
-}
applyLoadedGroup : UpdateConfig -> Group.Id -> List Event.Envelope -> Symmetric.Key -> Maybe String -> Set String -> Model -> Maybe Model
applyLoadedGroup config groupId events groupKey syncCursor unpushedIds model =
    Dict.get groupId config.groups
        |> Maybe.map (\summary -> Submit.initLoadedGroup events summary groupKey syncCursor unpushedIds)
        |> Maybe.map (\loaded -> { model | loadedGroup = Just loaded })


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
            { model
                | loadedGroup =
                    Just { loaded | unpushedIds = Set.insert eventId loaded.unpushedIds }
            }

        Nothing ->
            model


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
    let
        ( pool, cmd ) =
            ConcurrentTask.attempt
                { pool = model.pool
                , send = config.sendTask
                , onComplete = OnGroupEventsLoaded groupId
                }
                (Storage.loadGroup config.db groupId)
    in
    ( { model | pool = pool, loadedGroup = Nothing }, cmd )


{-| Initialize the sub-page model for a given group view, if the needed data is available.
-}
initPagesIfNeeded : UpdateConfig -> GroupView -> Model -> Model
initPagesIfNeeded config groupView model =
    case model.loadedGroup of
        Just loaded ->
            let
                entryFormConfig : Page.Group.NewEntry.Config
                entryFormConfig =
                    { currentUserRootId =
                        GroupState.resolveMemberRootId loaded.groupState config.identity.publicKeyHash
                    , activeMembersRootIds = List.map .rootId (GroupState.activeMembers loaded.groupState)
                    , today = Date.posixToDate config.currentTime
                    , defaultCurrency = loaded.summary.defaultCurrency
                    }
            in
            case groupView of
                NewEntry ->
                    case model.pendingTransfer of
                        Just payData ->
                            { model | newEntryModel = Page.Group.NewEntry.initTransfer entryFormConfig payData, pendingTransfer = Nothing }

                        Nothing ->
                            { model | newEntryModel = Page.Group.NewEntry.init entryFormConfig }

                EntryDetail _ ->
                    { model | entryDetailModel = Page.Group.EntryDetail.init }

                EditEntry entryId ->
                    case Dict.get entryId loaded.groupState.entries of
                        Just entryState ->
                            { model | newEntryModel = Page.Group.NewEntry.initFromEntry entryFormConfig entryState.currentVersion }

                        Nothing ->
                            model

                MemberDetail memberId ->
                    case Dict.get memberId loaded.groupState.members of
                        Just memberState ->
                            { model | memberDetailModel = Page.Group.MemberDetail.init memberState }

                        Nothing ->
                            model

                EditMemberMetadata memberId ->
                    case Dict.get memberId loaded.groupState.members of
                        Just memberState ->
                            { model | editMemberMetadataModel = Page.Group.EditMemberMetadata.init memberState.rootId memberState.name memberState.metadata }

                        Nothing ->
                            model

                EditGroupMetadata ->
                    { model | editGroupMetadataModel = Page.Group.EditGroupMetadata.init loaded.groupState.groupMeta }

                _ ->
                    model

        Nothing ->
            model


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


{-| Resolve the current user's member root ID within a loaded group.
-}
currentUserRootId : Model -> LoadedGroup -> Member.Id
currentUserRootId model loaded =
    GroupState.resolveMemberRootId loaded.groupState model.identityHash



-- VIEW


{-| Render the group page for a given route, dispatching to the right sub-page view.
Handles loading state internally.
-}
view : ViewConfig msg -> Ui.Element msg -> GroupView -> Model -> Ui.Element msg
view config headerExtra groupView model =
    case model.loadedGroup of
        Just loaded ->
            if loaded.summary.id == config.groupId then
                viewGroupPage config headerExtra groupView loaded model

            else
                viewLoadingShell config headerExtra

        Nothing ->
            viewLoadingShell config headerExtra


viewLoadingShell : ViewConfig msg -> Ui.Element msg -> Ui.Element msg
viewLoadingShell config headerExtra =
    UI.Shell.appShell
        { title = T.shellPartage config.i18n
        , headerExtra = headerExtra
        , content =
            Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ]
                (Ui.text (T.loadingGroup config.i18n))
        }


viewGroupPage : ViewConfig msg -> Ui.Element msg -> GroupView -> LoadedGroup -> Model -> Ui.Element msg
viewGroupPage config headerExtra groupView loaded model =
    let
        groupState : GroupState
        groupState =
            loaded.groupState

        userRootId : Member.Id
        userRootId =
            currentUserRootId model loaded
    in
    case groupView of
        Tab tab ->
            viewTabs config headerExtra groupState userRootId loaded { model | activeTab = tab }

        Join _ ->
            subPageShell headerExtra (T.shellJoinGroup config.i18n) <|
                Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ]
                    (Ui.text (T.joinGroupComingSoon config.i18n))

        NewEntry ->
            subPageShell headerExtra (T.shellNewEntry config.i18n) <|
                Page.Group.NewEntry.view config.i18n
                    (GroupState.activeMembers groupState)
                    (config.toMsg << NewEntryMsg)
                    model.newEntryModel

        EditEntry _ ->
            subPageShell headerExtra (T.editEntryTitle config.i18n) <|
                Page.Group.NewEntry.view config.i18n
                    (GroupState.activeMembers groupState)
                    (config.toMsg << NewEntryMsg)
                    model.newEntryModel

        EntryDetail entryId ->
            case Dict.get entryId groupState.entries of
                Just entryState ->
                    subPageShell headerExtra (T.entryDetailTitle config.i18n) <|
                        Page.Group.EntryDetail.view config.i18n
                            { currentUserRootId = userRootId
                            , resolveName = GroupState.resolveMemberName groupState
                            }
                            (config.toMsg << EntryDetailMsg)
                            model.entryDetailModel
                            entryState

                Nothing ->
                    subPageShell headerExtra (T.shellPartage config.i18n) <|
                        Page.NotFound.view config.i18n

        MemberDetail _ ->
            subPageShell headerExtra (T.memberDetailTitle config.i18n) <|
                Page.Group.MemberDetail.view config.i18n
                    userRootId
                    (config.toMsg << MemberDetailMsg)
                    model.memberDetailModel

        AddVirtualMember ->
            subPageShell headerExtra (T.memberAddTitle config.i18n) <|
                Page.Group.AddMember.view config.i18n
                    (config.toMsg << AddMemberMsg)
                    model.addMemberModel

        EditMemberMetadata _ ->
            subPageShell headerExtra (T.memberEditMetadataButton config.i18n) <|
                Page.Group.EditMemberMetadata.view config.i18n
                    (config.toMsg << EditMemberMetadataMsg)
                    model.editMemberMetadataModel

        EditGroupMetadata ->
            subPageShell headerExtra (T.groupSettingsTitle config.i18n) <|
                Page.Group.EditGroupMetadata.view config.i18n
                    (config.toMsg << EditGroupMetadataMsg)
                    model.editGroupMetadataModel


subPageShell : Ui.Element msg -> String -> Ui.Element msg -> Ui.Element msg
subPageShell headerExtra title content =
    UI.Shell.appShell { title = title, headerExtra = headerExtra, content = content }


viewTabs : ViewConfig msg -> Ui.Element msg -> GroupState -> Member.Id -> LoadedGroup -> Model -> Ui.Element msg
viewTabs config headerExtra groupState userRootId loaded model =
    UI.Shell.groupShell
        { groupName = groupState.groupMeta.name
        , headerExtra = headerExtra
        , activeTab = model.activeTab
        , onTabClick = \tab -> config.toMsg (RequestNavigation (Tab tab))
        , content = tabContent config groupState userRootId loaded model
        , tabLabels =
            { balance = T.tabBalance config.i18n
            , entries = T.tabEntries config.i18n
            , members = T.tabMembers config.i18n
            , activity = T.tabActivity config.i18n
            }
        }


tabContent : ViewConfig msg -> GroupState -> Member.Id -> LoadedGroup -> Model -> Ui.Element msg
tabContent config state userRootId loaded model =
    case model.activeTab of
        BalanceTab ->
            Page.Group.BalanceTab.view config.i18n
                { onSettle = \tx -> config.toMsg (SettleTransaction tx)
                , onPayMember = \payData -> config.toMsg (PayMember payData)
                , onSavePreferences = \prefData -> config.toMsg (SaveSettlementPreferences prefData)
                , toMsg = config.toMsg << BalanceTabMsg
                }
                userRootId
                model.balanceTabModel
                state

        EntriesTab ->
            Page.Group.EntriesTab.view config.i18n
                { onNewEntry = config.toMsg (RequestNavigation NewEntry)
                , onEntryClick = \entryId -> config.toMsg (RequestNavigation (EntryDetail entryId))
                , toMsg = config.toMsg << EntriesTabMsg
                }
                config.today
                model.entriesTabModel
                state

        MembersTab ->
            Page.Group.MembersTab.view config.i18n
                { onMemberClick = \memberId -> config.toMsg (RequestNavigation (MemberDetail memberId))
                , onAddMember = config.toMsg (RequestNavigation AddVirtualMember)
                , onEditGroupMetadata = config.toMsg (RequestNavigation EditGroupMetadata)
                }
                userRootId
                state

        ActivityTab ->
            let
                allMembers : List ( Member.Id, String )
                allMembers =
                    GroupState.activeMembers state
                        |> List.map (\m -> ( m.rootId, m.name ))
                        |> List.sortBy Tuple.second
            in
            Page.Group.ActivityTab.view config.i18n
                { resolveName = GroupState.resolveMemberName state
                , currentUserRootId = userRootId
                , onEntryClick = \entryId -> config.toMsg (RequestNavigation (EntryDetail entryId))
                , entryDetailPath = \entryId -> Route.toPath (GroupRoute config.groupId (EntryDetail entryId))
                , groupDefaultCurrency = loaded.summary.defaultCurrency
                , toMsg = config.toMsg << ActivityTabMsg
                , allMembers = allMembers
                }
                model.activityTabModel
                state.activities
