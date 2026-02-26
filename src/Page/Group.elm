module Page.Group exposing (view)

{-| Group page shell with tab routing, using sample data for Phase 2.
-}

import Domain.GroupState exposing (GroupState)
import Domain.Member as Member
import Page.Group.ActivitiesTab
import Page.Group.BalanceTab
import Page.Group.EntriesTab
import Page.Group.MembersTab
import Route exposing (GroupTab(..))
import SampleData
import UI.Shell
import Ui


view : GroupTab -> (GroupTab -> msg) -> Ui.Element msg
view activeTab onTabClick =
    let
        state =
            SampleData.groupState

        currentUserRootId =
            SampleData.currentUserRootId

        resolveName =
            SampleData.resolveName
    in
    UI.Shell.groupShell
        { groupName = state.groupMeta.name
        , activeTab = activeTab
        , onTabClick = onTabClick
        , content = tabContent activeTab state currentUserRootId resolveName
        }


tabContent : GroupTab -> GroupState -> Member.Id -> (Member.Id -> String) -> Ui.Element msg
tabContent tab state currentUserRootId resolveName =
    case tab of
        BalanceTab ->
            Page.Group.BalanceTab.view state currentUserRootId resolveName

        EntriesTab ->
            Page.Group.EntriesTab.view state resolveName

        MembersTab ->
            Page.Group.MembersTab.view state currentUserRootId

        ActivitiesTab ->
            Page.Group.ActivitiesTab.view
