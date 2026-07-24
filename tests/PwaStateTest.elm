module PwaStateTest exposing (suite)

import Expect
import Pwa
import PwaState
import Test exposing (Test, describe, test)


grantedModel : Maybe String -> PwaState.Model
grantedModel pushServerUrl =
    let
        model : PwaState.Model
        model =
            PwaState.init { pushServerUrl = pushServerUrl, isOnline = True, installHint = "none" }
    in
    { model | notificationPermission = Just Pwa.Granted }


enable : PwaState.Model -> PwaState.Model
enable model =
    let
        ( newModel, _, _ ) =
            PwaState.update (\_ -> Cmd.none) PwaState.enableNotificationsMsg model
    in
    newModel


suite : Test
suite =
    describe "PwaState notification enabling"
        [ test "granted permission with no key and a push server flags the feature unavailable" <|
            \_ ->
                grantedModel (Just "https://push.example.com")
                    |> enable
                    |> .notificationUnavailable
                    |> Expect.equal True
        , test "a deployment without a push server never reports unavailable on enable" <|
            \_ ->
                grantedModel Nothing
                    |> enable
                    |> .notificationUnavailable
                    |> Expect.equal False
        ]
