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
import SampleData
import Translations as T exposing (I18n, Language(..))
import UI.Components
import UI.Shell
import UI.Theme as Theme
import Ui
import Ui.Font
import Url


port navCmd : Navigation.CommandPort msg


port onNavEvent : Navigation.EventPort msg


type alias Flags =
    { initialUrl : String
    , language : String
    }


type alias Model =
    { route : Route
    , identity : Maybe String
    , i18n : I18n
    , language : Language
    }


type Msg
    = OnNavEvent Navigation.Event
    | NavigateTo Route
    | SwitchTab GroupTab
    | SwitchLanguage Language


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

        language =
            flags.language
                |> T.languageFromString
                |> Maybe.withDefault En

        i18n =
            T.init language

        ( guardedRoute, cmd ) =
            applyRouteGuard identity route
    in
    ( { route = guardedRoute
      , identity = identity
      , i18n = i18n
      , language = language
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

        SwitchLanguage lang ->
            ( { model | language = lang, i18n = T.init lang }
            , Cmd.none
            )


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
    let
        i18n =
            model.i18n

        langSelector =
            UI.Components.languageSelector model.language SwitchLanguage
    in
    case model.route of
        Setup ->
            UI.Shell.appShell { title = T.shellPartage i18n, headerExtra = langSelector, content = Page.Setup.view i18n }

        Home ->
            UI.Shell.appShell { title = T.shellPartage i18n, headerExtra = langSelector, content = Page.Home.view i18n NavigateTo }

        NewGroup ->
            UI.Shell.appShell { title = T.shellNewGroup i18n, headerExtra = langSelector, content = Page.NewGroup.view i18n }

        GroupRoute groupId (Tab tab) ->
            if groupId == SampleData.groupId then
                Page.Group.view i18n langSelector tab SwitchTab

            else
                UI.Shell.appShell { title = T.shellPartage i18n, headerExtra = langSelector, content = Page.NotFound.view i18n }

        GroupRoute groupId (Join _) ->
            if groupId == SampleData.groupId then
                UI.Shell.appShell
                    { title = T.shellJoinGroup i18n
                    , headerExtra = langSelector
                    , content =
                        Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ]
                            (Ui.text (T.joinGroupComingSoon i18n))
                    }

            else
                UI.Shell.appShell { title = T.shellPartage i18n, headerExtra = langSelector, content = Page.NotFound.view i18n }

        GroupRoute groupId NewEntry ->
            if groupId == SampleData.groupId then
                UI.Shell.appShell
                    { title = T.shellNewEntry i18n
                    , headerExtra = langSelector
                    , content =
                        Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ]
                            (Ui.text (T.newEntryComingSoon i18n))
                    }

            else
                UI.Shell.appShell { title = T.shellPartage i18n, headerExtra = langSelector, content = Page.NotFound.view i18n }

        About ->
            UI.Shell.appShell { title = T.shellPartage i18n, headerExtra = langSelector, content = Page.About.view i18n }

        NotFound ->
            UI.Shell.appShell { title = T.shellPartage i18n, headerExtra = langSelector, content = Page.NotFound.view i18n }
