module PwaState exposing (Model, Msg, OutMsg(..), enableNotificationsMsg, init, initTask, pushIsActive, subscription, update, viewBanners)

{-| PWA state management, extracted from Main.elm.

Handles online/offline status, update/install banners,
notification permissions, push subscriptions, and VAPID key.

`Msg` is opaque — Main only wraps it via `PwaStateMsg`. All message
construction happens internally through `subscription`, `initTask`,
`viewBanners`, and `enableNotificationsMsg`.

-}

import ConcurrentTask
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
    , installAvailable : Bool
    , notificationPermission : Maybe Pwa.NotificationPermission
    , pushSubscription : Maybe Json.Encode.Value
    , vapidKey : Maybe String
    }


init : { isOnline : Bool } -> Model
init flags =
    { isOnline = flags.isOnline
    , updateAvailable = False
    , installAvailable = False
    , notificationPermission = Nothing
    , pushSubscription = Nothing
    , vapidKey = Nothing
    }


{-| Start the VAPID key fetch task. Call during app init.

    ( runner, initCmds )
        |> PwaState.initTask PwaStateMsg

-}
initTask : (Msg -> msg) -> ( TaskRunner msg, Cmd msg ) -> ( TaskRunner msg, Cmd msg )
initTask toMsg =
    Runner.andRun (toMsg << OnVapidKeyFetched) PushServer.fetchVapidKey


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
    | DismissInstallBanner
    | EnableNotifications
    | OnVapidKeyFetched (ConcurrentTask.Response PushServer.Error String)


type OutMsg
    = ShowToastError
    | NavigateToUrl String
    | CameOnline


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
        , installAvailable = model.installAvailable
        , onUpdate = AcceptUpdate
        , onInstall = RequestInstall
        , onDismissInstall = DismissInstallBanner
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
            ( { model | installAvailable = False }, Pwa.requestInstall pwaOut, [] )

        DismissInstallBanner ->
            ( { model | installAvailable = False }, Cmd.none, [] )

        EnableNotifications ->
            case model.notificationPermission of
                Just Pwa.Granted ->
                    case model.vapidKey of
                        Just key ->
                            ( model, Pwa.subscribePush pwaOut key, [] )

                        Nothing ->
                            ( model, Cmd.none, [] )

                _ ->
                    ( model, Pwa.requestNotificationPermission pwaOut, [] )

        OnVapidKeyFetched (ConcurrentTask.Success key) ->
            let
                newModel : Model
                newModel =
                    { model | vapidKey = Just key }
            in
            case model.notificationPermission of
                Just Pwa.Granted ->
                    ( newModel, Pwa.subscribePush pwaOut key, [] )

                _ ->
                    ( newModel, Cmd.none, [] )

        OnVapidKeyFetched _ ->
            ( model, Cmd.none, [] )


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

        Pwa.InstallAvailable ->
            ( { model | installAvailable = True }, Cmd.none, [] )

        Pwa.Installed ->
            ( { model | installAvailable = False }, Cmd.none, [] )

        Pwa.NotificationPermissionChanged permission ->
            let
                newModel : Model
                newModel =
                    { model | notificationPermission = Just permission }
            in
            case ( permission, model.vapidKey ) of
                ( Pwa.Granted, Just key ) ->
                    ( newModel, Pwa.subscribePush pwaOut key, [] )

                _ ->
                    ( newModel, Cmd.none, [] )

        Pwa.PushSubscription sub ->
            ( { model | pushSubscription = Just sub }, Cmd.none, [] )

        Pwa.PushSubscriptionError _ ->
            ( model, Cmd.none, [ ShowToastError ] )

        Pwa.PushUnsubscribed ->
            ( { model | pushSubscription = Nothing }, Cmd.none, [] )

        Pwa.NotificationClicked data ->
            case Json.Decode.decodeValue (Json.Decode.field "url" Json.Decode.string) data of
                Ok url ->
                    ( model, Cmd.none, [ NavigateToUrl url ] )

                Err _ ->
                    ( model, Cmd.none, [] )

        _ ->
            ( model, Cmd.none, [] )
