port module Main exposing (main)

import AppUrl exposing (AppUrl)
import Browser
import ConcurrentTask
import Html exposing (Html)
import Identity exposing (Identity)
import Json.Decode
import Json.Encode
import Navigation
import Page.About
import Page.Group
import Page.Home
import Page.NewGroup
import Page.NotFound
import Page.Setup
import Random
import Route exposing (GroupTab(..), GroupView(..), Route(..))
import SampleData
import Translations as T exposing (I18n, Language(..))
import UI.Components
import UI.Shell
import UI.Theme as Theme
import UUID
import Ui
import Ui.Font
import Url
import WebCrypto


port navCmd : Navigation.CommandPort msg


port onNavEvent : Navigation.EventPort msg


port sendTask : Json.Encode.Value -> Cmd msg


port receiveTask : (Json.Decode.Value -> msg) -> Sub msg


type alias Flags =
    { initialUrl : String
    , language : String
    , randomSeed : List Int
    , currentTime : Int
    }


type alias Model =
    { route : Route
    , identity : Maybe Identity
    , generatingIdentity : Bool
    , i18n : I18n
    , language : Language
    , pool : ConcurrentTask.Pool Msg
    , uuidState : UUID.V7State
    }


type Msg
    = OnNavEvent Navigation.Event
    | NavigateTo Route
    | SwitchTab GroupTab
    | SwitchLanguage Language
    | GenerateIdentity
    | OnTaskProgress ( ConcurrentTask.Pool Msg, Cmd Msg )
    | OnIdentityGenerated (ConcurrentTask.Response WebCrypto.Error Identity)


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ Navigation.onEvent onNavEvent OnNavEvent
        , ConcurrentTask.onProgress
            { send = sendTask
            , receive = receiveTask
            , onProgress = OnTaskProgress
            }
            model.pool
        ]


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

        language =
            flags.language
                |> T.languageFromString
                |> Maybe.withDefault En

        i18n =
            T.init language

        initialSeed =
            List.foldl
                (\n acc -> Random.step (Random.int Random.minInt Random.maxInt) acc |> Tuple.second)
                (Random.initialSeed (List.sum flags.randomSeed))
                flags.randomSeed

        ( uuidState, _ ) =
            Random.step UUID.initialV7State initialSeed

        ( guardedRoute, cmd ) =
            applyRouteGuard Nothing route
    in
    ( { route = guardedRoute
      , identity = Nothing
      , generatingIdentity = False
      , i18n = i18n
      , language = language
      , pool = ConcurrentTask.pool
      , uuidState = uuidState
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

        GenerateIdentity ->
            let
                ( pool, cmd ) =
                    ConcurrentTask.attempt
                        { pool = model.pool
                        , send = sendTask
                        , onComplete = OnIdentityGenerated
                        }
                        Identity.generate
            in
            ( { model | pool = pool, generatingIdentity = True }, cmd )

        OnTaskProgress ( pool, cmd ) ->
            ( { model | pool = pool }, cmd )

        OnIdentityGenerated (ConcurrentTask.Success identity) ->
            let
                ( guardedRoute, cmd ) =
                    applyRouteGuard (Just identity) model.route
            in
            ( { model | identity = Just identity, generatingIdentity = False, route = guardedRoute }, cmd )

        OnIdentityGenerated _ ->
            ( { model | generatingIdentity = False }, Cmd.none )


applyRouteGuard : Maybe Identity -> Route -> ( Route, Cmd Msg )
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
            UI.Shell.appShell
                { title = T.shellPartage i18n
                , headerExtra = langSelector
                , content = Page.Setup.view i18n { onGenerate = GenerateIdentity, isGenerating = model.generatingIdentity }
                }

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
