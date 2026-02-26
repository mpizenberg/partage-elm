port module Main exposing (main)

import AppUrl exposing (AppUrl)
import Browser
import Html exposing (Html, a, div, nav, text, ul)
import Html.Attributes exposing (href, style)
import Html.Events
import Json.Decode
import Navigation
import Page.About
import Page.Group
import Page.Home
import Page.NewGroup
import Page.NotFound
import Page.Setup
import Route exposing (GroupTab(..), GroupView(..), Route(..))
import Url


port navCmd : Navigation.CommandPort msg


port onNavEvent : Navigation.EventPort msg


type alias Flags =
    { initialUrl : String
    }


type alias Model =
    { route : Route
    , identity : Maybe String
    }


type Msg
    = OnNavEvent Navigation.Event
    | NavigateTo AppUrl


main : Program Flags Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , subscriptions = subscriptions
        , view = view
        }


init : Flags -> ( Model, Cmd Msg )
init flags =
    let
        route =
            flags.initialUrl
                |> Url.fromString
                |> Maybe.map (AppUrl.fromUrl >> Route.fromAppUrl)
                |> Maybe.withDefault NotFound

        -- Dev workaround: hardcode identity to bypass guards during Phase 1
        identity =
            Just "dev"

        ( guardedRoute, cmd ) =
            applyRouteGuard identity route
    in
    ( { route = guardedRoute
      , identity = identity
      }
    , cmd
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        OnNavEvent event ->
            let
                route =
                    Route.fromAppUrl event.appUrl

                ( guardedRoute, cmd ) =
                    applyRouteGuard model.identity route
            in
            ( { model | route = guardedRoute }, cmd )

        NavigateTo appUrl ->
            ( model, Navigation.pushUrl navCmd appUrl )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Navigation.onEvent onNavEvent OnNavEvent


applyRouteGuard : Maybe String -> Route -> ( Route, Cmd Msg )
applyRouteGuard identity route =
    case identity of
        Nothing ->
            case route of
                Setup ->
                    ( route, Cmd.none )

                About ->
                    ( route, Cmd.none )

                GroupRoute _ (Join _) ->
                    ( route, Cmd.none )

                _ ->
                    ( Setup, Navigation.replaceUrl navCmd (AppUrl.fromPath [ "setup" ]) )

        Just _ ->
            case route of
                Setup ->
                    ( Home, Navigation.replaceUrl navCmd (AppUrl.fromPath []) )

                _ ->
                    ( route, Cmd.none )


view : Model -> Html Msg
view model =
    div [ style "max-width" "768px", style "margin" "0 auto", style "padding" "1rem" ]
        [ headerNav model.route
        , viewPage model
        ]


headerNav : Route -> Html Msg
headerNav currentRoute =
    nav [ style "margin-bottom" "1rem", style "padding-bottom" "0.5rem", style "border-bottom" "1px solid #ccc" ]
        [ ul [ style "display" "flex", style "gap" "1rem", style "list-style" "none", style "padding" "0", style "margin" "0" ]
            [ navLink currentRoute Home "Home"
            , navLink currentRoute (GroupRoute "test-id" (Tab BalanceTab)) "Test Group"
            , navLink currentRoute About "About"
            ]
        ]


navLink : Route -> Route -> String -> Html Msg
navLink currentRoute targetRoute label =
    let
        isActive =
            routePrefix currentRoute == routePrefix targetRoute
    in
    Html.li []
        [ a
            [ href (Route.toPath targetRoute)
            , onClickPreventDefault (NavigateTo (Route.toAppUrl targetRoute))
            , style "font-weight"
                (if isActive then
                    "bold"

                 else
                    "normal"
                )
            ]
            [ text label ]
        ]


routePrefix : Route -> String
routePrefix route =
    case route of
        GroupRoute id _ ->
            "group:" ++ id

        _ ->
            Route.toPath route


onClickPreventDefault : msg -> Html.Attribute msg
onClickPreventDefault msg =
    Html.Events.preventDefaultOn "click"
        (Json.Decode.succeed ( msg, True ))


viewPage : Model -> Html Msg
viewPage model =
    case model.route of
        Setup ->
            Page.Setup.view

        Home ->
            Page.Home.view

        NewGroup ->
            Page.NewGroup.view

        GroupRoute groupId (Tab tab) ->
            Page.Group.view groupId tab NavigateTo

        GroupRoute _ (Join _) ->
            div [] [ text "Join group — coming in Phase 5." ]

        GroupRoute _ NewEntry ->
            div [] [ text "New entry form — coming in Phase 5." ]

        About ->
            Page.About.view

        NotFound ->
            Page.NotFound.view
