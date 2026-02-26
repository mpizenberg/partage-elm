module Page.Group exposing (view)

import AppUrl exposing (AppUrl)
import Domain.Group as Group
import Html exposing (Html, a, div, h1, li, nav, p, text, ul)
import Html.Attributes exposing (href, style)
import Html.Events
import Json.Decode
import Route exposing (GroupTab(..))


view : Group.Id -> GroupTab -> (AppUrl -> msg) -> Html msg
view groupId activeTab onNavigate =
    div []
        [ h1 [] [ text ("Group: " ++ groupId) ]
        , nav []
            [ ul [ style "display" "flex", style "gap" "1rem", style "list-style" "none", style "padding" "0" ]
                [ tabLink onNavigate groupId BalanceTab activeTab "Balance"
                , tabLink onNavigate groupId EntriesTab activeTab "Entries"
                , tabLink onNavigate groupId MembersTab activeTab "Members"
                , tabLink onNavigate groupId ActivitiesTab activeTab "Activities"
                ]
            ]
        , tabContent activeTab
        ]


tabLink : (AppUrl -> msg) -> Group.Id -> GroupTab -> GroupTab -> String -> Html msg
tabLink onNavigate groupId tab activeTab label =
    let
        isActive =
            tab == activeTab

        route =
            Route.GroupRoute groupId (Route.Tab tab)

        path =
            Route.toPath route
    in
    li []
        [ a
            [ href path
            , onClickPreventDefault (onNavigate (Route.toAppUrl route))
            , style "font-weight"
                (if isActive then
                    "bold"

                 else
                    "normal"
                )
            ]
            [ text label ]
        ]


onClickPreventDefault : msg -> Html.Attribute msg
onClickPreventDefault msg =
    Html.Events.preventDefaultOn "click"
        (Json.Decode.succeed ( msg, True ))


tabContent : GroupTab -> Html msg
tabContent tab =
    case tab of
        BalanceTab ->
            div []
                [ p [] [ text "Balance overview will appear here." ] ]

        EntriesTab ->
            div []
                [ p [] [ text "Entry list will appear here." ] ]

        MembersTab ->
            div []
                [ p [] [ text "Member list will appear here." ] ]

        ActivitiesTab ->
            div []
                [ p [] [ text "Activity feed will appear here." ] ]
