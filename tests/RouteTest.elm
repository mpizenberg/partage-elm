module RouteTest exposing (suite)

import Dict
import Expect
import Route exposing (GroupView(..), Route(..))
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Route"
        [ describe "join fragment grammar key[.tail]"
            [ test "a bare key is taken whole" <|
                \_ ->
                    Route.fromAppUrl
                        { path = [ "join", "g1" ], queryParameters = Dict.empty, fragment = Just "s3cretKey=" }
                        |> Expect.equal (GroupRoute "g1" (Join { key = "s3cretKey=", tail = Nothing }))
            , test "everything after the first dot is the tail, kept verbatim" <|
                \_ ->
                    Route.fromAppUrl
                        { path = [ "join", "g1" ], queryParameters = Dict.empty, fragment = Just "s3cretKey=.attestation.v2" }
                        |> Expect.equal (GroupRoute "g1" (Join { key = "s3cretKey=", tail = Just "attestation.v2" }))
            , test "a missing fragment yields an empty key" <|
                \_ ->
                    Route.fromAppUrl
                        { path = [ "join", "g1" ], queryParameters = Dict.empty, fragment = Nothing }
                        |> Expect.equal (GroupRoute "g1" (Join { key = "", tail = Nothing }))
            , test "toPath keeps the tail after the key" <|
                \_ ->
                    Route.toPath (GroupRoute "g1" (Join { key = "k", tail = Just "3-e9" }))
                        |> Expect.equal "/join/g1#k.3-e9"
            , test "toPath omits the dot without a tail" <|
                \_ ->
                    Route.toPath (GroupRoute "g1" (Join { key = "k", tail = Nothing }))
                        |> Expect.equal "/join/g1#k"
            ]
        ]
