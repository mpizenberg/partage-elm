module ChangelogTest exposing (suite)

import Changelog
import Changelog.Latest
import Expect
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Changelog.hasUnseen"
        [ test "an install that never recorded a marker is shown nothing" <|
            \_ ->
                Changelog.hasUnseen Nothing
                    |> Expect.equal False
        , test "a reader up to date with the newest entry is shown nothing" <|
            \_ ->
                Changelog.hasUnseen (Just Changelog.Latest.date)
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
