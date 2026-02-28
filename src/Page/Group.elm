module Page.Group exposing (Context, view)

{-| Group page shell with tab routing, using real group data.
-}

import Domain.Entry as Entry
import Domain.GroupState exposing (GroupState)
import Domain.Member as Member
import Page.Group.ActivitiesTab
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
    , currentUserRootId : Member.Id
    }


view : Context msg -> { showDeleted : Bool } -> Ui.Element msg -> GroupState -> GroupTab -> Ui.Element msg
view ctx { showDeleted } headerExtra groupState activeTab =
    UI.Shell.groupShell
        { groupName = groupState.groupMeta.name
        , headerExtra = headerExtra
        , activeTab = activeTab
        , onTabClick = ctx.onTabClick
        , content = tabContent ctx showDeleted groupState activeTab
        , tabLabels =
            { balance = T.tabBalance ctx.i18n
            , entries = T.tabEntries ctx.i18n
            , members = T.tabMembers ctx.i18n
            , activities = T.tabActivities ctx.i18n
            }
        }


tabContent : Context msg -> Bool -> GroupState -> GroupTab -> Ui.Element msg
tabContent ctx showDeleted state tab =
    case tab of
        BalanceTab ->
            Page.Group.BalanceTab.view ctx.i18n ctx.currentUserRootId state

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
                }
                ctx.currentUserRootId
                state

        ActivitiesTab ->
            Page.Group.ActivitiesTab.view ctx.i18n
