module RouteTest exposing (suite)

import Dict
import Expect
import Route exposing (GroupView(..), Route(..))
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Route"
        [ describe "join fragment grammar key[.extra]"
            [ test "a bare key is taken whole" <|
                \_ ->
                    Route.fromAppUrl
                        { path = [ "join", "g1" ], queryParameters = Dict.empty, fragment = Just "s3cretKey=" }
                        |> Expect.equal (GroupRoute "g1" (Join "s3cretKey="))
            , test "everything after the first dot is ignored" <|
                \_ ->
                    Route.fromAppUrl
                        { path = [ "join", "g1" ], queryParameters = Dict.empty, fragment = Just "s3cretKey=.attestation.v2" }
                        |> Expect.equal (GroupRoute "g1" (Join "s3cretKey="))
            , test "a missing fragment yields an empty key" <|
                \_ ->
                    Route.fromAppUrl
                        { path = [ "join", "g1" ], queryParameters = Dict.empty, fragment = Nothing }
                        |> Expect.equal (GroupRoute "g1" (Join ""))
            ]
        ]
