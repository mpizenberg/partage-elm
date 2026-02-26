port module Main exposing (main)

import AppUrl exposing (AppUrl)
import Browser
import Html exposing (Html)
import Navigation
import Page.About
import Page.Group
import Page.Home
import Page.NewGroup
import Page.NotFound
import Page.Setup
import Route exposing (GroupTab(..), GroupView(..), Route(..))
import UI.Shell
import UI.Theme as Theme
import Ui
import Ui.Font
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
    | NavigateTo Route
    | SwitchTab GroupTab


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

        NavigateTo route ->
            ( model, Navigation.pushUrl navCmd (Route.toAppUrl route) )

        SwitchTab tab ->
            case model.route of
                GroupRoute groupId _ ->
                    let
                        newRoute =
                            GroupRoute groupId (Tab tab)
                    in
                    ( { model | route = newRoute }
                    , Navigation.replaceUrl navCmd (Route.toAppUrl newRoute)
                    )

                _ ->
                    ( model, Cmd.none )


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
    Ui.layout Ui.default [ Ui.height Ui.fill ] (viewPage model)


viewPage : Model -> Ui.Element Msg
viewPage model =
    case model.route of
        Setup ->
            UI.Shell.appShell { title = "Partage", content = Page.Setup.view }

        Home ->
            UI.Shell.appShell { title = "Partage", content = Page.Home.view NavigateTo }

        NewGroup ->
            UI.Shell.appShell { title = "New Group", content = Page.NewGroup.view }

        GroupRoute _ (Tab tab) ->
            Page.Group.view tab SwitchTab

        GroupRoute _ (Join _) ->
            UI.Shell.appShell
                { title = "Join Group"
                , content =
                    Ui.el [ Ui.Font.size 14, Ui.Font.color Theme.neutral500 ]
                        (Ui.text "Join group — coming in Phase 5.")
                }

        GroupRoute _ NewEntry ->
            UI.Shell.appShell
                { title = "New Entry"
                , content =
                    Ui.el [ Ui.Font.size 14, Ui.Font.color Theme.neutral500 ]
                        (Ui.text "New entry form — coming in Phase 5.")
                }

        About ->
            UI.Shell.appShell { title = "Partage", content = Page.About.view }

        NotFound ->
            UI.Shell.appShell { title = "Partage", content = Page.NotFound.view }
