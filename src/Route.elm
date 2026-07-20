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
    = Welcome
    | Home
    | NewGroup
    | ImportSplitwise
    | GroupRoute Group.Id GroupView
    | About
    | ErrorLog
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
    | MergeMember Member.Id (Maybe Member.Id)
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
            Welcome

        [ "welcome" ] ->
            Welcome

        [ "groups" ] ->
            Home

        [ "groups", "new" ] ->
            NewGroup

        [ "groups", "import-splitwise" ] ->
            ImportSplitwise

        [ "join", groupId ] ->
            -- The fragment grammar is `key[.extra]`: everything after the
            -- first `.` is reserved for future use (e.g. invite attestations)
            -- and ignored, so old clients keep accepting new invite links.
            GroupRoute groupId
                (Join
                    (Maybe.withDefault "" appUrl.fragment
                        |> String.split "."
                        |> List.head
                        |> Maybe.withDefault ""
                    )
                )

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

        [ "groups", groupId, "members", sourceId, "merge" ] ->
            GroupRoute groupId (MergeMember sourceId Nothing)

        [ "groups", groupId, "members", sourceId, "merge", targetId ] ->
            GroupRoute groupId (MergeMember sourceId (Just targetId))

        [ "groups", groupId, "settings" ] ->
            GroupRoute groupId EditGroupMetadata

        [ "about" ] ->
            About

        [ "error-log" ] ->
            ErrorLog

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
        Welcome ->
            []

        Home ->
            [ "groups" ]

        NewGroup ->
            [ "groups", "new" ]

        ImportSplitwise ->
            [ "groups", "import-splitwise" ]

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

        GroupRoute groupId (MergeMember sourceId Nothing) ->
            [ "groups", groupId, "members", sourceId, "merge" ]

        GroupRoute groupId (MergeMember sourceId (Just targetId)) ->
            [ "groups", groupId, "members", sourceId, "merge", targetId ]

        GroupRoute groupId EditGroupMetadata ->
            [ "groups", groupId, "settings" ]

        About ->
            [ "about" ]

        ErrorLog ->
            [ "error-log" ]

        NotFound ->
            []


{-| Serialize a Route to a URL path string.

Note: `Welcome` always serializes to `/`. The `/welcome` URL is
accepted as an alias only at parse time (in `fromAppUrl`).

-}
toPath : Route -> String
toPath route =
    case route of
        Welcome ->
            "/"

        Home ->
            "/groups"

        NewGroup ->
            "/groups/new"

        ImportSplitwise ->
            "/groups/import-splitwise"

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

        GroupRoute groupId (MergeMember sourceId Nothing) ->
            "/groups/" ++ groupId ++ "/members/" ++ sourceId ++ "/merge"

        GroupRoute groupId (MergeMember sourceId (Just targetId)) ->
            "/groups/" ++ groupId ++ "/members/" ++ sourceId ++ "/merge/" ++ targetId

        GroupRoute groupId EditGroupMetadata ->
            "/groups/" ++ groupId ++ "/settings"

        About ->
            "/about"

        ErrorLog ->
            "/error-log"

        NotFound ->
            "/"
