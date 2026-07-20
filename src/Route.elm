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
    = Join { key : String, tail : Maybe String }
    | Tab GroupTab
    | HighlightEntry Entry.Id
    | NewEntry
    | EditEntry Entry.Id
    | AddVirtualMember
    | EditMemberMetadata Member.Id
    | MergeMember Member.Id (Maybe Member.Id)
    | EditGroupMetadata
    | Diagnostics


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
            -- The fragment grammar is `key[.tail]`: everything before the
            -- first `.` is the key; the tail carries the inviter's head
            -- attestation (spec §12.1) and is kept verbatim for the join
            -- flow to interpret (unknown formats are simply ignored).
            case String.split "." (Maybe.withDefault "" appUrl.fragment) of
                key :: rest ->
                    GroupRoute groupId
                        (Join
                            { key = key
                            , tail =
                                if List.isEmpty rest then
                                    Nothing

                                else
                                    Just (String.join "." rest)
                            }
                        )

                [] ->
                    GroupRoute groupId (Join { key = "", tail = Nothing })

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

        [ "groups", groupId, "diagnostics" ] ->
            GroupRoute groupId Diagnostics

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
        GroupRoute groupId (Join invite) ->
            { path = [ "join", groupId ]
            , queryParameters = Dict.empty
            , fragment = Just (joinFragment invite)
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

        GroupRoute groupId Diagnostics ->
            [ "groups", groupId, "diagnostics" ]

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

        GroupRoute groupId (Join invite) ->
            "/join/" ++ groupId ++ "#" ++ joinFragment invite

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

        GroupRoute groupId Diagnostics ->
            "/groups/" ++ groupId ++ "/diagnostics"

        About ->
            "/about"

        ErrorLog ->
            "/error-log"

        NotFound ->
            "/"


joinFragment : { key : String, tail : Maybe String } -> String
joinFragment invite =
    case invite.tail of
        Just tail ->
            invite.key ++ "." ++ tail

        Nothing ->
            invite.key
