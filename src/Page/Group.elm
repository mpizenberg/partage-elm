module Page.Group exposing (Context, Model, Msg, init, update, view)

{-| Group page shell with tab routing, using real group data.
-}

import Domain.Currency exposing (Currency)
import Domain.Date exposing (Date)
import Domain.Entry as Entry
import Domain.GroupState as GroupState exposing (GroupState)
import Domain.Member as Member
import Domain.Settlement as Settlement
import Page.Group.ActivityTab
import Page.Group.BalanceTab
import Page.Group.EntriesTab
import Page.Group.MembersTab
import Route exposing (GroupTab(..))
import Translations as T exposing (I18n)
import UI.Shell
import Ui


{-| Rarely changing context provided by parent callers.
-}
type alias Context msg =
    { i18n : I18n
    , onTabClick : GroupTab -> msg
    , onNewEntry : msg
    , onEntryClick : Entry.Id -> msg
    , onMemberClick : Member.Id -> msg
    , onAddMember : msg
    , onEditGroupMetadata : msg
    , onSettleTransaction : Settlement.Transaction -> msg
    , onPayMember : { toMemberId : Member.Id, amountCents : Int } -> msg
    , onSaveSettlementPreferences : { memberRootId : Member.Id, preferredRecipients : List Member.Id } -> msg
    , currentUserRootId : Member.Id
    , entryDetailPath : Entry.Id -> String
    , groupDefaultCurrency : Currency
    , today : Date
    , toMsg : Msg -> msg
    }


type alias Model =
    { activeTab : GroupTab
    , entriesTabModel : Page.Group.EntriesTab.Model
    , balanceTabModel : Page.Group.BalanceTab.Model
    , activityTabModel : Page.Group.ActivityTab.Model
    }


type Msg
    = EntriesTabMsg Page.Group.EntriesTab.Msg
    | BalanceTabMsg Page.Group.BalanceTab.Msg
    | ActivityTabMsg Page.Group.ActivityTab.Msg


init : Model
init =
    { activeTab = BalanceTab
    , entriesTabModel = Page.Group.EntriesTab.init
    , balanceTabModel = Page.Group.BalanceTab.init
    , activityTabModel = Page.Group.ActivityTab.init
    }


update : Msg -> Model -> Model
update msg model =
    case msg of
        EntriesTabMsg subMsg ->
            { model | entriesTabModel = Page.Group.EntriesTab.update subMsg model.entriesTabModel }

        BalanceTabMsg subMsg ->
            { model | balanceTabModel = Page.Group.BalanceTab.update subMsg model.balanceTabModel }

        ActivityTabMsg subMsg ->
            { model | activityTabModel = Page.Group.ActivityTab.update subMsg model.activityTabModel }


{-| Render the group page shell with tabs and the active tab's content.
-}
view : Context msg -> Ui.Element msg -> GroupState -> Model -> Ui.Element msg
view ctx headerExtra groupState model =
    UI.Shell.groupShell
        { groupName = groupState.groupMeta.name
        , headerExtra = headerExtra
        , activeTab = model.activeTab
        , onTabClick = ctx.onTabClick
        , content = tabContent ctx groupState model
        , tabLabels =
            { balance = T.tabBalance ctx.i18n
            , entries = T.tabEntries ctx.i18n
            , members = T.tabMembers ctx.i18n
            , activity = T.tabActivity ctx.i18n
            }
        }


tabContent : Context msg -> GroupState -> Model -> Ui.Element msg
tabContent ctx state model =
    case model.activeTab of
        BalanceTab ->
            Page.Group.BalanceTab.view ctx.i18n
                { onSettle = ctx.onSettleTransaction
                , onPayMember = ctx.onPayMember
                , onSavePreferences = ctx.onSaveSettlementPreferences
                , toMsg = ctx.toMsg << BalanceTabMsg
                }
                ctx.currentUserRootId
                model.balanceTabModel
                state

        EntriesTab ->
            Page.Group.EntriesTab.view ctx.i18n
                { onNewEntry = ctx.onNewEntry
                , onEntryClick = ctx.onEntryClick
                , toMsg = ctx.toMsg << EntriesTabMsg
                }
                ctx.today
                model.entriesTabModel
                state

        MembersTab ->
            Page.Group.MembersTab.view ctx.i18n
                { onMemberClick = ctx.onMemberClick
                , onAddMember = ctx.onAddMember
                , onEditGroupMetadata = ctx.onEditGroupMetadata
                }
                ctx.currentUserRootId
                state

        ActivityTab ->
            let
                allMembers : List ( Member.Id, String )
                allMembers =
                    GroupState.activeMembers state
                        |> List.map (\m -> ( m.rootId, m.name ))
                        |> List.sortBy Tuple.second
            in
            Page.Group.ActivityTab.view ctx.i18n
                { resolveName = GroupState.resolveMemberName state
                , currentUserRootId = ctx.currentUserRootId
                , onEntryClick = ctx.onEntryClick
                , entryDetailPath = ctx.entryDetailPath
                , groupDefaultCurrency = ctx.groupDefaultCurrency
                , toMsg = ctx.toMsg << ActivityTabMsg
                , allMembers = allMembers
                }
                model.activityTabModel
                state.activities
