module HandoffTest exposing (suite)

import Domain.Currency exposing (Currency(..))
import Domain.Group as Group
import Domain.Member as Member
import Expect
import Infra.Handoff as Handoff
import Infra.Identity exposing (Identity)
import Json.Encode as Encode
import Set
import Test exposing (Test, describe, test)
import Time


suite : Test
suite =
    describe "Infra.Handoff"
        [ describe "codec" codecTests
        , describe "merge" mergeTests
        ]


codecTests : List Test
codecTests =
    [ test "round-trips through encode and fromString" <|
        \_ ->
            Handoff.fromString (Encode.encode 0 (Handoff.encode payload))
                |> Expect.equal (Ok payload)
    , test "tolerates surrounding whitespace" <|
        \_ ->
            Handoff.fromString ("  \n" ++ Encode.encode 0 (Handoff.encode payload) ++ "\n ")
                |> Expect.equal (Ok payload)
    , test "rejects an unknown format" <|
        \_ ->
            Handoff.fromString """{"format":"partage-group-v1"}"""
                |> Expect.err
    , test "rejects garbage" <|
        \_ ->
            Handoff.fromString "not a payload"
                |> Expect.err
    ]


mergeTests : List Test
mergeTests =
    [ test "a destination with zero groups adopts the incoming identity, profile, and settings" <|
        \_ ->
            Handoff.merge payload
                { identity = Just (makeIdentity "dest-device" []), existingGroupIds = Set.empty }
                |> Expect.all
                    [ \plan -> plan.identity |> Expect.equal payload.identity
                    , \plan -> plan.adopted |> Expect.equal True
                    , \plan -> List.map (.summary >> .id) plan.groupsToAdd |> Expect.equal [ "g-1", "g-2" ]
                    , \plan -> plan.selfProfile |> Expect.equal (Just payload.selfProfile)
                    , \plan -> plan.language |> Expect.equal (Just "fr")
                    ]
    , test "a destination with no identity at all adopts too" <|
        \_ ->
            Handoff.merge payload { identity = Nothing, existingGroupIds = Set.empty }
                |> .identity
                |> Expect.equal payload.identity
    , test "a destination with groups keeps its identity and profile, gaining the incoming device ids" <|
        \_ ->
            Handoff.merge payload
                { identity = Just (makeIdentity "dest-device" [ "dest-old" ])
                , existingGroupIds = Set.singleton "g-other"
                }
                |> Expect.all
                    [ \plan -> plan.identity.publicKeyHash |> Expect.equal "dest-device"
                    , \plan ->
                        plan.identity.previousDeviceIds
                            |> Expect.equal [ "dest-old", "src-device", "src-old" ]
                    , \plan -> plan.adopted |> Expect.equal False
                    , \plan -> plan.selfProfile |> Expect.equal Nothing
                    , \plan -> plan.language |> Expect.equal Nothing
                    ]
    , test "groups already present are skipped, the rest are added" <|
        \_ ->
            Handoff.merge payload
                { identity = Just (makeIdentity "dest-device" [])
                , existingGroupIds = Set.fromList [ "g-1" ]
                }
                |> Expect.all
                    [ \plan -> List.map (.summary >> .id) plan.groupsToAdd |> Expect.equal [ "g-2" ]
                    , \plan -> plan.skippedGroupIds |> Expect.equal [ "g-1" ]
                    ]
    , test "receiving the same payload twice converges" <|
        \_ ->
            let
                afterFirst : Handoff.Plan
                afterFirst =
                    Handoff.merge payload { identity = Nothing, existingGroupIds = Set.empty }

                afterSecond : Handoff.Plan
                afterSecond =
                    Handoff.merge payload
                        { identity = Just afterFirst.identity
                        , existingGroupIds = Set.fromList (List.map (.summary >> .id) afterFirst.groupsToAdd)
                        }
            in
            afterSecond
                |> Expect.all
                    [ \plan -> plan.identity |> Expect.equal payload.identity
                    , \plan -> plan.groupsToAdd |> Expect.equal []
                    , \plan -> plan.skippedGroupIds |> Expect.equal [ "g-1", "g-2" ]
                    ]
    ]


payload : Handoff.Payload
payload =
    let
        base : Member.Metadata
        base =
            Member.emptyMetadata
    in
    { identity = makeIdentity "src-device" [ "src-old" ]
    , groups =
        [ { summary = makeSummary "g-1" "Trip", key = "key-1" }
        , { summary = makeSummary "g-2" "Flat", key = "key-2" }
        ]
    , selfProfile = { base | email = Just "me@example.com" }
    , language = Just "fr"
    , lastSeenChangelog = Just "2026-08-01"
    }


makeIdentity : String -> List String -> Identity
makeIdentity hash previous =
    { publicKeyHash = hash
    , signingKeyPair = { publicKey = "pub-" ++ hash, privateKey = "priv-" ++ hash }
    , previousDeviceIds = previous
    }


makeSummary : Group.Id -> String -> Group.Summary
makeSummary id name =
    { id = id
    , name = name
    , defaultCurrency = EUR
    , isSubscribed = True
    , isArchived = False
    , createdAt = Time.millisToPosix 1000
    , memberCount = 3
    , myBalanceCents = -250
    , lastSyncedAt = Time.millisToPosix 2000
    }
