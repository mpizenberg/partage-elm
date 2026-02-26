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
import Translations as T exposing (I18n)
import UI.Shell
import Ui


view : I18n -> Ui.Element msg -> GroupTab -> (GroupTab -> msg) -> Ui.Element msg
view i18n headerExtra activeTab onTabClick =
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
        , headerExtra = headerExtra
        , activeTab = activeTab
        , onTabClick = onTabClick
        , content = tabContent i18n activeTab state currentUserRootId resolveName
        , tabLabels =
            { balance = T.tabBalance i18n
            , entries = T.tabEntries i18n
            , members = T.tabMembers i18n
            , activities = T.tabActivities i18n
            }
        }


tabContent : I18n -> GroupTab -> GroupState -> Member.Id -> (Member.Id -> String) -> Ui.Element msg
tabContent i18n tab state currentUserRootId resolveName =
    case tab of
        BalanceTab ->
            Page.Group.BalanceTab.view i18n state currentUserRootId resolveName

        EntriesTab ->
            Page.Group.EntriesTab.view i18n state resolveName

        MembersTab ->
            Page.Group.MembersTab.view i18n state currentUserRootId

        ActivitiesTab ->
            Page.Group.ActivitiesTab.view i18n
