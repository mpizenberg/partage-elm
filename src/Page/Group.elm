module Page.Group exposing (Context, view)

{-| Group page shell with tab routing, using real group data.
-}

import Domain.Activity as Activity
import Domain.Entry as Entry
import Domain.Event as Event
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
    , currentUserRootId : Member.Id
    }


view : Context msg -> { showDeleted : Bool } -> Ui.Element msg -> GroupState -> List Event.Envelope -> GroupTab -> Ui.Element msg
view ctx { showDeleted } headerExtra groupState events activeTab =
    UI.Shell.groupShell
        { groupName = groupState.groupMeta.name
        , headerExtra = headerExtra
        , activeTab = activeTab
        , onTabClick = ctx.onTabClick
        , content = tabContent ctx showDeleted groupState events activeTab
        , tabLabels =
            { balance = T.tabBalance ctx.i18n
            , entries = T.tabEntries ctx.i18n
            , members = T.tabMembers ctx.i18n
            , activity = T.tabActivity ctx.i18n
            }
        }


tabContent : Context msg -> Bool -> GroupState -> List Event.Envelope -> GroupTab -> Ui.Element msg
tabContent ctx showDeleted state events tab =
    case tab of
        BalanceTab ->
            Page.Group.BalanceTab.view ctx.i18n ctx.currentUserRootId ctx.onSettleTransaction state

        EntriesTab ->
            Page.Group.EntriesTab.view ctx.i18n
                { onNewEntry = ctx.onNewEntry
                , onEntryClick = ctx.onEntryClick
                , showDeleted = showDeleted
                , onToggleDeleted = ctx.onToggleDeleted
                }
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
            Page.Group.ActivityTab.view ctx.i18n
                (GroupState.resolveMemberName state)
                (Activity.fromEvents events)
