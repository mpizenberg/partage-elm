module ChangelogTest exposing (suite)

import Changelog
import Expect
import Set
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Changelog"
        [ describe "entry list invariants"
            [ test "dates are unique, so a marker names exactly one entry" <|
                \_ ->
                    let
                        dates : List String
                        dates =
                            List.map .date Changelog.entries
                    in
                    Set.size (Set.fromList dates)
                        |> Expect.equal (List.length dates)
            , test "entries are ordered newest first" <|
                \_ ->
                    let
                        dates : List String
                        dates =
                            List.map .date Changelog.entries
                    in
                    dates
                        |> Expect.equal (List.reverse (List.sort dates))
            ]
        , describe "hasUnseen"
            [ test "an install that never recorded a marker is shown nothing" <|
                \_ ->
                    Changelog.hasUnseen Nothing
                        |> Expect.equal False
            , test "a reader up to date with the newest entry is shown nothing" <|
                \_ ->
                    Changelog.hasUnseen (Just Changelog.latest)
                        |> Expect.equal False
            , test "a marker predating the newest entry has something to show" <|
                \_ ->
                    Changelog.hasUnseen (Just "2000-01-01")
                        |> Expect.equal True
            , test "a marker past every published entry is shown nothing" <|
                \_ ->
                    Changelog.hasUnseen (Just "2999-01-01")
                        |> Expect.equal False
            ]
        ]
