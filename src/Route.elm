module Route exposing (GroupTab(..), GroupView(..), Route(..), fromAppUrl, toAppUrl, toPath)

{-| Application routing types with URL parsing and serialization.
-}

import AppUrl exposing (AppUrl)
import Dict
import Domain.Entry as Entry
import Domain.Group as Group
import Domain.Member as Member


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
    | HighlightEntry Entry.Id
    | NewEntry
    | EditEntry Entry.Id
    | AddVirtualMember
    | EditMemberMetadata Member.Id
    | EditGroupMetadata


{-| The tabs available within a group's main view.
-}
type GroupTab
    = BalanceTab
    | EntriesTab
    | MembersTab
    | ActivityTab


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
            case Dict.get "highlight" appUrl.queryParameters |> Maybe.andThen List.head of
                Just entryId ->
                    GroupRoute groupId (HighlightEntry entryId)

                Nothing ->
                    GroupRoute groupId (Tab EntriesTab)

        [ "groups", groupId, "members" ] ->
            GroupRoute groupId (Tab MembersTab)

        [ "groups", groupId, "activity" ] ->
            GroupRoute groupId (Tab ActivityTab)

        [ "groups", groupId, "new-entry" ] ->
            GroupRoute groupId NewEntry

        [ "groups", groupId, "entries", entryId, "edit" ] ->
            GroupRoute groupId (EditEntry entryId)

        [ "groups", groupId, "members", "new" ] ->
            GroupRoute groupId AddVirtualMember

        [ "groups", groupId, "members", memberId, "edit" ] ->
            GroupRoute groupId (EditMemberMetadata memberId)

        [ "groups", groupId, "settings" ] ->
            GroupRoute groupId EditGroupMetadata

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

        GroupRoute groupId (HighlightEntry entryId) ->
            { path = [ "groups", groupId, "entries" ]
            , queryParameters = Dict.singleton "highlight" [ entryId ]
            , fragment = Nothing
            }

        _ ->
            AppUrl.fromPath (toPathSegments route)


{-| Convert a Route to a list of URL path segments.
-}
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

        GroupRoute groupId (HighlightEntry _) ->
            [ "groups", groupId, "entries" ]

        GroupRoute groupId (Tab MembersTab) ->
            [ "groups", groupId, "members" ]

        GroupRoute groupId (Tab ActivityTab) ->
            [ "groups", groupId, "activity" ]

        GroupRoute groupId NewEntry ->
            [ "groups", groupId, "new-entry" ]

        GroupRoute groupId (EditEntry entryId) ->
            [ "groups", groupId, "entries", entryId, "edit" ]

        GroupRoute groupId AddVirtualMember ->
            [ "groups", groupId, "members", "new" ]

        GroupRoute groupId (EditMemberMetadata memberId) ->
            [ "groups", groupId, "members", memberId, "edit" ]

        GroupRoute groupId EditGroupMetadata ->
            [ "groups", groupId, "settings" ]

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

        GroupRoute groupId (HighlightEntry entryId) ->
            "/groups/" ++ groupId ++ "/entries?highlight=" ++ entryId

        GroupRoute groupId (Tab MembersTab) ->
            "/groups/" ++ groupId ++ "/members"

        GroupRoute groupId (Tab ActivityTab) ->
            "/groups/" ++ groupId ++ "/activity"

        GroupRoute groupId NewEntry ->
            "/groups/" ++ groupId ++ "/new-entry"

        GroupRoute groupId (EditEntry entryId) ->
            "/groups/" ++ groupId ++ "/entries/" ++ entryId ++ "/edit"

        GroupRoute groupId AddVirtualMember ->
            "/groups/" ++ groupId ++ "/members/new"

        GroupRoute groupId (EditMemberMetadata memberId) ->
            "/groups/" ++ groupId ++ "/members/" ++ memberId ++ "/edit"

        GroupRoute groupId EditGroupMetadata ->
            "/groups/" ++ groupId ++ "/settings"

        About ->
            "/about"

        NotFound ->
            "/"
