module PwaState exposing (Model, Msg, OutMsg(..), PushSetup, configureTask, enableNotificationsMsg, init, notificationUnavailable, pushIsActive, pushServerUrl, subscription, update, viewBanners, withCachedPushServer)

{-| PWA state management, extracted from Main.elm.

Handles online/offline status, update/install banners,
notification permissions, push subscriptions, and VAPID key.

`Msg` is opaque — Main only wraps it via `PwaStateMsg`. All message
construction happens internally through `subscription`, `initTask`,
`viewBanners`, and `enableNotificationsMsg`.

-}

import ConcurrentTask
import ErrorLog
import Infra.ConcurrentTaskExtra as Runner exposing (TaskRunner)
import Infra.PushServer as PushServer
import Json.Decode
import Json.Encode
import Pwa
import Translations exposing (I18n)
import UI.Components
import Ui


type alias Model =
    { isOnline : Bool
    , updateAvailable : Bool
    , installHint : Pwa.InstallHint
    , installHintDismissed : Bool
    , justInstalled : Bool
    , notificationPermission : Maybe Pwa.NotificationPermission
    , pushSubscription : Maybe Json.Encode.Value
    , pushSetup : PushSetup
    }


{-| How far the deployment's push configuration has been resolved. The push
server is not known at build time: it is fetched from the relay, so every state
between "nothing known yet" and "ready to subscribe" is reachable and the UI
distinguishes them — `Pending` still offers to enable, `Unreachable` says so.
-}
type PushSetup
    = PushUnconfigured
    | PushPending String
    | PushUnreachable String
    | PushReady String String


init : { isOnline : Bool, installHint : String } -> Model
init flags =
    { isOnline = flags.isOnline
    , updateAvailable = False
    , installHint = Pwa.installHintFromString flags.installHint
    , installHintDismissed = False
    , justInstalled = False
    , notificationPermission = Nothing
    , pushSubscription = Nothing
    , pushSetup = PushUnconfigured
    }


{-| The push server this deployment addresses, once known.
-}
pushServerUrl : Model -> Maybe String
pushServerUrl model =
    case model.pushSetup of
        PushUnconfigured ->
            Nothing

        PushPending url ->
            Just url

        PushUnreachable url ->
            Just url

        PushReady url _ ->
            Just url


{-| A push server is configured but did not answer, so enabling cannot work.
-}
notificationUnavailable : Model -> Bool
notificationUnavailable model =
    case model.pushSetup of
        PushUnreachable _ ->
            True

        _ ->
            False


{-| Start from the push server the relay last reported, so the notification
surfaces are present from the first paint and survive an offline launch.
-}
withCachedPushServer : Maybe String -> Model -> Model
withCachedPushServer cached model =
    case cached of
        Just url ->
            { model | pushSetup = PushPending url }

        Nothing ->
            model


{-| Resolve the deployment's push configuration: ask the relay which push server
to use, then ask that server for its VAPID key. Call once storage is open, so
the cached URL can carry the app until the answer arrives — and stand in for it
when the relay cannot be reached.

    ( runner, initCmds )
        |> PwaState.configureTask
            { serverUrl = serverUrl, cachedPushServerUrl = cached }
            PwaStateMsg

-}
configureTask :
    { serverUrl : String, cachedPushServerUrl : Maybe String }
    -> (Msg -> msg)
    -> ( TaskRunner msg, Cmd msg )
    -> ( TaskRunner msg, Cmd msg )
configureTask { serverUrl, cachedPushServerUrl } toMsg =
    Runner.andRun (toMsg << OnPushSetup)
        (PushServer.fetchPushConfig serverUrl
            |> ConcurrentTask.onError (\_ -> ConcurrentTask.succeed cachedPushServerUrl)
            |> ConcurrentTask.andThen
                (\configured ->
                    case configured of
                        Just url ->
                            PushServer.fetchVapidKey url
                                |> ConcurrentTask.map (PushReady url)
                                |> ConcurrentTask.onError (\_ -> ConcurrentTask.succeed (PushUnreachable url))

                        Nothing ->
                            ConcurrentTask.succeed PushUnconfigured
                )
        )


{-| Subscribe to PWA events from the JS runtime.

    PwaState.subscription pwaIn PwaStateMsg

-}
subscription : ((Json.Decode.Value -> msg) -> Sub msg) -> (Msg -> msg) -> Sub msg
subscription pwaIn toMsg =
    pwaIn (toMsg << GotPwaEvent << Pwa.decodeEvent)


type Msg
    = GotPwaEvent (Result Json.Decode.Error Pwa.Event)
    | AcceptUpdate
    | RequestInstall
    | DismissInstallHint
    | DismissJustInstalled
    | EnableNotifications
    | OnPushSetup (ConcurrentTask.Response PushServer.Error PushSetup)


type OutMsg
    = ShowToastError
    | NavigateToUrl String
    | CameOnline
    | RegisterPushTopics { pushServerUrl : String, subscription : Json.Encode.Value }
    | PushServerUrlResolved (Maybe String)
    | LogError ErrorLog.Source ErrorLog.Severity String


{-| Registering this device's topics needs both halves, and either can arrive
first: the push server is resolved over the network while the browser reports an
existing subscription on its own schedule.
-}
registerTopics : Model -> List OutMsg
registerTopics model =
    case ( pushServerUrl model, model.pushSubscription ) of
        ( Just url, Just sub ) ->
            [ RegisterPushTopics { pushServerUrl = url, subscription = sub } ]

        _ ->
            []


pushIsActive : Model -> Bool
pushIsActive model =
    model.notificationPermission == Just Pwa.Granted && model.pushSubscription /= Nothing


{-| An opaque Msg for enabling notifications. Used in Page.Home config.
-}
enableNotificationsMsg : Msg
enableNotificationsMsg =
    EnableNotifications


{-| Render the PWA banners (offline, update available, install prompt).
Wrap with `Ui.map PwaStateMsg` in Main.
-}
viewBanners : I18n -> Model -> Ui.Element Msg
viewBanners i18n model =
    UI.Components.pwaBanners i18n
        { isOnline = model.isOnline
        , updateAvailable = model.updateAvailable
        , installHint =
            if model.installHintDismissed || model.justInstalled then
                Pwa.NoInstallHint

            else
                model.installHint
        , justInstalled = model.justInstalled
        , onUpdate = AcceptUpdate
        , onInstall = RequestInstall
        , onDismissInstall = DismissInstallHint
        , onDismissJustInstalled = DismissJustInstalled
        }


update : (Json.Encode.Value -> Cmd msg) -> Msg -> Model -> ( Model, Cmd msg, List OutMsg )
update pwaOut msg model =
    case msg of
        GotPwaEvent (Ok event) ->
            handleEvent pwaOut event model

        GotPwaEvent (Err _) ->
            ( model, Cmd.none, [] )

        AcceptUpdate ->
            ( model, Pwa.acceptUpdate pwaOut, [] )

        RequestInstall ->
            ( model, Pwa.requestInstall pwaOut, [] )

        DismissInstallHint ->
            ( { model | installHintDismissed = True }, Cmd.none, [] )

        DismissJustInstalled ->
            ( { model | justInstalled = False }, Cmd.none, [] )

        EnableNotifications ->
            case ( model.pushSetup, model.notificationPermission ) of
                ( PushUnconfigured, _ ) ->
                    ( model, Cmd.none, [] )

                ( PushUnreachable _, _ ) ->
                    ( model, Cmd.none, [] )

                ( PushReady _ key, Just Pwa.Granted ) ->
                    ( model, Pwa.subscribePush pwaOut key, [] )

                _ ->
                    ( model, Pwa.requestNotificationPermission pwaOut, [] )

        OnPushSetup (ConcurrentTask.Success setup) ->
            let
                newModel : Model
                newModel =
                    { model | pushSetup = setup }
            in
            ( newModel
            , case ( setup, model.notificationPermission ) of
                ( PushReady _ key, Just Pwa.Granted ) ->
                    Pwa.subscribePush pwaOut key

                _ ->
                    Cmd.none
            , PushServerUrlResolved (pushServerUrl newModel) :: registerTopics newModel
            )

        OnPushSetup _ ->
            ( { model
                | pushSetup =
                    case pushServerUrl model of
                        Just url ->
                            PushUnreachable url

                        Nothing ->
                            PushUnconfigured
              }
            , Cmd.none
            , [ LogError ErrorLog.PwaSource ErrorLog.Err "Failed to resolve push configuration" ]
            )


handleEvent : (Json.Encode.Value -> Cmd msg) -> Pwa.Event -> Model -> ( Model, Cmd msg, List OutMsg )
handleEvent pwaOut event model =
    case event of
        Pwa.ConnectionChanged online ->
            ( { model | isOnline = online }
            , Cmd.none
            , if online then
                [ CameOnline ]

              else
                []
            )

        Pwa.UpdateAvailable ->
            ( { model | updateAvailable = True }, Cmd.none, [] )

        Pwa.InstallHintChanged newHint ->
            let
                justInstalled : Bool
                justInstalled =
                    newHint == Pwa.LaunchedAsInstalled && model.installHint /= Pwa.LaunchedAsInstalled
            in
            ( { model
                | installHint = newHint
                , installHintDismissed = model.installHintDismissed && newHint == model.installHint
                , justInstalled = model.justInstalled || justInstalled
              }
            , Cmd.none
            , []
            )

        Pwa.NotificationPermissionChanged permission ->
            let
                newModel : Model
                newModel =
                    { model | notificationPermission = Just permission }
            in
            case ( permission, model.pushSetup ) of
                ( Pwa.Granted, PushReady _ key ) ->
                    ( newModel, Pwa.subscribePush pwaOut key, [] )

                _ ->
                    ( newModel, Cmd.none, [] )

        Pwa.PushSubscription sub ->
            let
                newModel : Model
                newModel =
                    { model | pushSubscription = Just sub }
            in
            ( newModel, Cmd.none, registerTopics newModel )

        Pwa.PushSubscriptionError error ->
            -- The browser's reason is the only thing that distinguishes a denied
            -- permission from an unreachable push service, and the log is where
            -- it can still be read after the toast is gone.
            ( model
            , Cmd.none
            , [ ShowToastError
              , LogError ErrorLog.PushSource ErrorLog.Err ("Push subscription error: " ++ error)
              ]
            )

        Pwa.PushUnsubscribed ->
            ( { model | pushSubscription = Nothing }, Cmd.none, [] )

        Pwa.NotificationClicked data ->
            case Json.Decode.decodeValue (Json.Decode.field "url" Json.Decode.string) data of
                Ok url ->
                    ( model, Cmd.none, [ NavigateToUrl url ] )

                Err _ ->
                    ( model, Cmd.none, [] )
