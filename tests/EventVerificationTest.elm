module EventVerificationTest exposing (suite)

import Dict
import Domain.Event as Event exposing (Envelope, Payload(..))
import Domain.GroupState as GroupState
import Domain.Member as Member
import Expect
import Infra.EventVerification as EventVerification
import Test exposing (Test, describe, test)
import Time


suite : Test
suite =
    describe "EventVerification.collectKeys"
        [ test "a key known from state is not overridden by the batch" <|
            \_ ->
                let
                    state =
                        GroupState.applyEvents [ introduction "e1" 0 "alice" "alice-key" ] GroupState.empty
                in
                EventVerification.collectKeys state [ introduction "e2" 1000 "alice" "evil-key" ]
                    |> Dict.get "alice"
                    |> Expect.equal (Just "alice-key")
        , test "within a batch, the earliest introduction in sort order wins" <|
            \_ ->
                EventVerification.collectKeys GroupState.empty
                    [ introduction "e2" 1000 "alice" "late-key"
                    , introduction "e1" 500 "alice" "early-key"
                    ]
                    |> Dict.get "alice"
                    |> Expect.equal (Just "early-key")
        ]


introduction : Event.Id -> Int -> Member.Id -> String -> Envelope
introduction eventId ts memberId publicKey =
    Event.wrap eventId
        (Time.millisToPosix ts)
        { id = memberId, publicKey = publicKey }
        (MemberCreated { memberId = memberId, name = "Alice", memberType = Member.Real, addedBy = memberId })
        ""
