module Route exposing (GroupTab(..), GroupView(..), Route(..))

{-| Application routing types.
-}

import Domain.Group as Group


{-| Top-level application routes.
-}
type Route
    = Setup
    | Home
    | NewGroup
    | GroupRoute Group.Id GroupView
    | About
    | NotFound


{-| Sub-routes within a group page.
-}
type GroupView
    = Join String
    | Tab GroupTab
    | NewEntry


{-| The tabs available within a group's main view.
-}
type GroupTab
    = BalanceTab
    | EntriesTab
    | MembersTab
    | ActivitiesTab
