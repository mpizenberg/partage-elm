module Route exposing (GroupTab(..), GroupView(..), Route(..))

import Domain.Group as Group


type Route
    = Setup
    | Home
    | NewGroup
    | GroupRoute Group.Id GroupView
    | About
    | NotFound


type GroupView
    = Join String
    | Tab GroupTab
    | NewEntry


type GroupTab
    = BalanceTab
    | EntriesTab
    | MembersTab
    | ActivitiesTab
