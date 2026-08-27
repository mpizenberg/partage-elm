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
        [ test "recognizes the relay's structured read-only response" <|
            \_ ->
                frozenError
                    |> Server.isFrozen
                    |> Expect.equal True
        , test "does not classify an unrelated 403 as read-only" <|
            \_ ->
                forbiddenError
                    |> Server.isFrozen
                    |> Expect.equal False
        , test "renders an unrelated 403 as a generic server error" <|
            \_ ->
                forbiddenError
                    |> Server.errorToString
                    |> Expect.equal "Server error (403)"
        , test "renders the structured read-only response distinctly" <|
            \_ ->
                frozenError
                    |> Server.errorToString
                    |> Expect.equal "Relay is read-only (403)"
        ]


frozenError : Server.Error
frozenError =
    badStatus 403 <|
        Encode.object
            [ ( "code", Encode.string "relay_read_only" ) ]


forbiddenError : Server.Error
forbiddenError =
    badStatus 403 <|
        Encode.object
            [ ( "code", Encode.string "forbidden" ) ]


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
