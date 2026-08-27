module ServerTest exposing (suite)

import ConcurrentTask.Http as Http
import Dict
import Expect
import Infra.Server as Server
import Json.Encode as Encode
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Infra.Server"
        [ test "recognizes the relay's read-only refusal" <|
            \_ ->
                frozenError
                    |> Server.isFrozen
                    |> Expect.equal True
        , test "renders the read-only refusal distinctly" <|
            \_ ->
                frozenError
                    |> Server.errorToString
                    |> Expect.equal "Relay is read-only (403)"
        , test "does not classify another rejection as read-only" <|
            \_ ->
                badStatus 401 Encode.null
                    |> Server.isFrozen
                    |> Expect.equal False
        ]


{-| A refusal as it reaches Elm: `BadStatus` carries whatever the HTTP runtime
put in `body`, and a request that expected no body gets `null`.
-}
frozenError : Server.Error
frozenError =
    badStatus 403 Encode.null


badStatus : Int -> Encode.Value -> Server.Error
badStatus statusCode body =
    Server.HttpError <|
        Http.BadStatus
            { url = "https://relay.example.com/api/groups/g/events"
            , statusCode = statusCode
            , statusText = ""
            , headers = Dict.empty
            }
            body
