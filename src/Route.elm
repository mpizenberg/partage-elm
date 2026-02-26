module Route exposing (GroupTab(..), GroupView(..), Route(..), fromAppUrl, toAppUrl, toPath)

{-| Application routing types with URL parsing and serialization.
-}

import AppUrl exposing (AppUrl)
import Dict
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


{-| Parse an AppUrl into a Route.
-}
fromAppUrl : AppUrl -> Route
fromAppUrl appUrl =
    case appUrl.path of
        [] ->
            Home

        [ "setup" ] ->
            Setup

        [ "groups", "new" ] ->
            NewGroup

        [ "join", groupId ] ->
            GroupRoute groupId (Join (Maybe.withDefault "" appUrl.fragment))

        [ "groups", groupId ] ->
            GroupRoute groupId (Tab BalanceTab)

        [ "groups", groupId, "entries" ] ->
            GroupRoute groupId (Tab EntriesTab)

        [ "groups", groupId, "members" ] ->
            GroupRoute groupId (Tab MembersTab)

        [ "groups", groupId, "activities" ] ->
            GroupRoute groupId (Tab ActivitiesTab)

        [ "groups", groupId, "new-entry" ] ->
            GroupRoute groupId NewEntry

        [ "about" ] ->
            About

        _ ->
            NotFound


{-| Convert a Route to an AppUrl for port-based navigation.
-}
toAppUrl : Route -> AppUrl
toAppUrl route =
    case route of
        GroupRoute groupId (Join key) ->
            { path = [ "join", groupId ]
            , queryParameters = Dict.empty
            , fragment = Just key
            }

        _ ->
            AppUrl.fromPath (toPathSegments route)


toPathSegments : Route -> List String
toPathSegments route =
    case route of
        Home ->
            []

        Setup ->
            [ "setup" ]

        NewGroup ->
            [ "groups", "new" ]

        GroupRoute groupId (Join _) ->
            [ "join", groupId ]

        GroupRoute groupId (Tab BalanceTab) ->
            [ "groups", groupId ]

        GroupRoute groupId (Tab EntriesTab) ->
            [ "groups", groupId, "entries" ]

        GroupRoute groupId (Tab MembersTab) ->
            [ "groups", groupId, "members" ]

        GroupRoute groupId (Tab ActivitiesTab) ->
            [ "groups", groupId, "activities" ]

        GroupRoute groupId NewEntry ->
            [ "groups", groupId, "new-entry" ]

        About ->
            [ "about" ]

        NotFound ->
            []


{-| Serialize a Route to a URL path string.
-}
toPath : Route -> String
toPath route =
    case route of
        Home ->
            "/"

        Setup ->
            "/setup"

        NewGroup ->
            "/groups/new"

        GroupRoute groupId (Join key) ->
            "/join/" ++ groupId ++ "#" ++ key

        GroupRoute groupId (Tab BalanceTab) ->
            "/groups/" ++ groupId

        GroupRoute groupId (Tab EntriesTab) ->
            "/groups/" ++ groupId ++ "/entries"

        GroupRoute groupId (Tab MembersTab) ->
            "/groups/" ++ groupId ++ "/members"

        GroupRoute groupId (Tab ActivitiesTab) ->
            "/groups/" ++ groupId ++ "/activities"

        GroupRoute groupId NewEntry ->
            "/groups/" ++ groupId ++ "/new-entry"

        About ->
            "/about"

        NotFound ->
            "/"
