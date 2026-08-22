module Infra.RelayConfig exposing (Config, Error, fetch)

{-| The settings a deployment chooses, served by the relay that serves the app.

Reading them from the running process rather than baking them into the build is
what lets an operator repoint or reconfigure a deployment with an environment
variable and a restart. Everything the deployment ships without comes back
empty, and a relay older than a setting omits its field entirely, so no single
setting can fail the whole configuration.

-}

import ConcurrentTask exposing (ConcurrentTask)
import ConcurrentTask.Http as Http
import Json.Decode as Decode


type alias Error =
    Http.Error


type alias Config =
    { pushServerUrl : Maybe String
    , feedbackProjectId : Maybe String
    }


fetch : String -> ConcurrentTask Error Config
fetch serverUrl =
    Http.get
        { url = serverUrl ++ "/api/config"
        , headers = []
        , expect =
            Http.expectJson
                (Decode.map2 Config
                    (configured "pushServerUrl")
                    (configured "feedbackProjectId")
                )
        , timeout = Nothing
        }


configured : String -> Decode.Decoder (Maybe String)
configured field =
    Decode.oneOf [ Decode.field field Decode.string, Decode.succeed "" ]
        |> Decode.map
            (\value ->
                if String.isEmpty value then
                    Nothing

                else
                    Just value
            )
