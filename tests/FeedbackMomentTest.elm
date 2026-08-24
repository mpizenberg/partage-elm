module FeedbackMomentTest exposing (suite)

import Domain.FeedbackMoment as FeedbackMoment exposing (Trigger(..))
import Expect
import Json.Decode as Decode
import Json.Encode as Encode
import Test exposing (Test, describe, test)
import Time


day : Int -> Time.Posix
day n =
    Time.millisToPosix (n * 24 * 60 * 60 * 1000)


suite : Test
suite =
    describe "FeedbackMoment pacing"
        [ test "a fresh history allows anything" <|
            \_ ->
                FeedbackMoment.allow (day 0) "trip" Concluded FeedbackMoment.empty
                    |> Expect.equal True
        , test "one prompt silences every other trigger for a week" <|
            \_ ->
                let
                    history : FeedbackMoment.History
                    history =
                        FeedbackMoment.record (day 0) "trip" Concluded FeedbackMoment.empty
                in
                ( FeedbackMoment.allow (day 6) "flat" Prolific history
                , FeedbackMoment.allow (day 7) "flat" Prolific history
                )
                    |> Expect.equal ( False, True )
        , test "the same trigger stays silent for a month, in another group" <|
            \_ ->
                let
                    history : FeedbackMoment.History
                    history =
                        FeedbackMoment.record (day 0) "trip" Concluded FeedbackMoment.empty
                in
                ( FeedbackMoment.allow (day 29) "flat" Concluded history
                , FeedbackMoment.allow (day 30) "flat" Concluded history
                )
                    |> Expect.equal ( False, True )
        , test "a group is never asked the same question twice" <|
            \_ ->
                FeedbackMoment.empty
                    |> FeedbackMoment.record (day 0) "trip" Concluded
                    |> FeedbackMoment.allow (day 400) "trip" Concluded
                    |> Expect.equal False
        , test "the same group can still be asked a different question" <|
            \_ ->
                FeedbackMoment.empty
                    |> FeedbackMoment.record (day 0) "trip" Concluded
                    |> FeedbackMoment.allow (day 30) "trip" Refusal
                    |> Expect.equal True
        , test "the newest prompt drives the weekly window, not the oldest" <|
            \_ ->
                FeedbackMoment.empty
                    |> FeedbackMoment.record (day 0) "trip" Concluded
                    |> FeedbackMoment.record (day 30) "flat" Prolific
                    |> FeedbackMoment.allow (day 34) "hut" Refusal
                    |> Expect.equal False
        , test "a history survives a round trip through storage" <|
            \_ ->
                let
                    history : FeedbackMoment.History
                    history =
                        FeedbackMoment.empty
                            |> FeedbackMoment.record (day 0) "trip" Concluded
                            |> FeedbackMoment.record (day 10) "flat" Refusal
                in
                Encode.encode 0 (FeedbackMoment.encode history)
                    |> Decode.decodeString FeedbackMoment.decoder
                    |> Result.map
                        (\decoded ->
                            ( FeedbackMoment.allow (day 11) "trip" Concluded decoded
                            , FeedbackMoment.allow (day 45) "hut" Refusal decoded
                            , FeedbackMoment.allow (day 45) "hut" Prolific decoded
                            )
                        )
                    |> Expect.equal (Ok ( False, True, True ))
        ]
