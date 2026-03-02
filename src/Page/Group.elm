module Page.Group exposing (Context, TabState, view)

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
    , onToggleDeleted : msg
    , onMemberClick : Member.Id -> msg
    , onAddMember : msg
    , onEditGroupMetadata : msg
    , onSettleTransaction : Settlement.Transaction -> msg
    , onPayMember : { toMemberId : Member.Id, amountCents : Int } -> msg
    , onSaveSettlementPreferences : { memberRootId : Member.Id, preferredRecipients : List Member.Id } -> msg
    , onToggleSettlementPreferences : msg
    , currentUserRootId : Member.Id
    , entryDetailPath : Entry.Id -> String
    , groupDefaultCurrency : Currency
    , today : Date
    , onEntriesTabMsg : Page.Group.EntriesTab.Msg -> msg
    , onActivityTabMsg : Page.Group.ActivityTab.Msg -> msg
    }


{-| Mutable tab state grouped with the active tab.
-}
type alias TabState =
    { activeTab : GroupTab
    , entriesTabModel : Page.Group.EntriesTab.Model
    , activityTabModel : Page.Group.ActivityTab.Model
    }


{-| Render the group page shell with tabs and the active tab's content.
-}
view : Context msg -> { showDeleted : Bool, showSettlementPreferences : Bool } -> Ui.Element msg -> GroupState -> TabState -> Ui.Element msg
view ctx { showDeleted, showSettlementPreferences } headerExtra groupState tabState =
    UI.Shell.groupShell
        { groupName = groupState.groupMeta.name
        , headerExtra = headerExtra
        , activeTab = tabState.activeTab
        , onTabClick = ctx.onTabClick
        , content = tabContent ctx showDeleted showSettlementPreferences groupState tabState
        , tabLabels =
            { balance = T.tabBalance ctx.i18n
            , entries = T.tabEntries ctx.i18n
            , members = T.tabMembers ctx.i18n
            , activity = T.tabActivity ctx.i18n
            }
        }


tabContent : Context msg -> Bool -> Bool -> GroupState -> TabState -> Ui.Element msg
tabContent ctx showDeleted showSettlementPreferences state tabState =
    case tabState.activeTab of
        BalanceTab ->
            Page.Group.BalanceTab.view ctx.i18n
                { onSettle = ctx.onSettleTransaction
                , onPayMember = ctx.onPayMember
                , onSavePreferences = ctx.onSaveSettlementPreferences
                , showPreferences = showSettlementPreferences
                , onTogglePreferences = ctx.onToggleSettlementPreferences
                }
                ctx.currentUserRootId
                state

        EntriesTab ->
            Page.Group.EntriesTab.view ctx.i18n
                { onNewEntry = ctx.onNewEntry
                , onEntryClick = ctx.onEntryClick
                , showDeleted = showDeleted
                , onToggleDeleted = ctx.onToggleDeleted
                , toMsg = ctx.onEntriesTabMsg
                }
                ctx.today
                tabState.entriesTabModel
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
                , toMsg = ctx.onActivityTabMsg
                , allMembers = allMembers
                }
                tabState.activityTabModel
                state.activities
