module SuspicionAuditTest exposing (suite)

import Domain.Currency exposing (Currency(..))
import Domain.Entry as Entry exposing (Kind(..))
import Domain.Event exposing (Envelope, Payload(..))
import Domain.GroupState as GroupState exposing (GroupState)
import Domain.Member as Member
import Domain.SuspicionAudit as SuspicionAudit exposing (Kind(..))
import Expect
import Test exposing (Test, describe, test)
import TestHelpers exposing (defaultExpenseData, makeEnvelope, makeExpenseEntry)


attackerMetadata : Member.Metadata
attackerMetadata =
    let
        emptyPay : Member.PaymentInfo
        emptyPay =
            Member.emptyPaymentInfo

        emptyMeta : Member.Metadata
        emptyMeta =
            Member.emptyMetadata
    in
    { emptyMeta | payment = Just { emptyPay | iban = Just "MALLORY-IBAN" } }


stateOf : List Envelope -> GroupState
stateOf events =
    GroupState.applyEvents events GroupState.empty


{-| Admin creates real member Bob; Bob links a device and adds a genuine entry,
so Bob is self-present. Mallory self-creates a member (needs no consent) and
rewrites Bob's payment info to her own IBAN.
-}
foreignPaymentEvents : List Envelope
foreignPaymentEvents =
    [ makeEnvelope "g" 0 "admin" (GroupCreated { name = "Trip", defaultCurrency = EUR })
    , makeEnvelope "m-admin" 1 "admin" (MemberCreated { memberId = "admin", name = "Admin", memberType = Member.Real, addedBy = "admin" })
    , makeEnvelope "m-bob" 2 "admin" (MemberCreated { memberId = "bob", name = "Bob", memberType = Member.Real, addedBy = "admin" })
    , makeEnvelope "link-bob" 3 "bob-dev" (MemberLinked { rootId = "bob", deviceId = "bob-dev", seq = 0 })
    , makeEnvelope "e-bob" 100 "bob-dev" (EntryAdded (makeExpenseEntry "entry-bob" 100 defaultExpenseData))
    , makeEnvelope "m-mallory" 200 "mallory" (MemberCreated { memberId = "mallory", name = "Mallory", memberType = Member.Real, addedBy = "mallory" })
    , makeEnvelope "meta-hijack" 300 "mallory" (MemberMetadataUpdated { rootId = "bob", metadata = attackerMetadata })
    ]


{-| Attacker grafts a second device onto Bob's established root and uses it only
to hijack Bob's entry — the grafted-device tamper pattern.
-}
graftEvents : List Envelope
graftEvents =
    [ makeEnvelope "g" 0 "admin" (GroupCreated { name = "Trip", defaultCurrency = EUR })
    , makeEnvelope "m-admin" 1 "admin" (MemberCreated { memberId = "admin", name = "Admin", memberType = Member.Real, addedBy = "admin" })
    , makeEnvelope "m-bob" 2 "admin" (MemberCreated { memberId = "bob", name = "Bob", memberType = Member.Real, addedBy = "admin" })
    , makeEnvelope "link-bob" 3 "bob-dev" (MemberLinked { rootId = "bob", deviceId = "bob-dev", seq = 0 })
    , makeEnvelope "e-bob" 100 "bob-dev" (EntryAdded (makeExpenseEntry "entry-bob" 100 defaultExpenseData))
    , makeEnvelope "link-mal" 400 "mal-dev" (MemberLinked { rootId = "bob", deviceId = "mal-dev", seq = 1 })
    , makeEnvelope "e-mal" 500 "mal-dev" (EntryModified graftHijack)
    ]


graftHijack : Entry.Entry
graftHijack =
    Entry.replace (makeExpenseEntry "entry-bob" 100 defaultExpenseData).meta
        "mal-dev"
        (Expense { defaultExpenseData | description = "Hijacked" })


suite : Test
suite =
    describe "SuspicionAudit"
        [ foreignPaymentSuite
        , graftedDeviceSuite
        , suppressionSuite
        , dismissKeySuite
        ]


foreignPaymentSuite : Test
foreignPaymentSuite =
    describe "ForeignPaymentEdit"
        [ test "flags a foreign rewrite of a self-present member's payment info" <|
            \_ ->
                SuspicionAudit.audit "admin" (stateOf foreignPaymentEvents) foreignPaymentEvents
                    |> Expect.equal
                        [ { culprit = "mallory"
                          , culpritLabel = "Mallory"
                          , kind = ForeignPaymentEdit { target = "bob" }
                          , eventIds = [ "meta-hijack" ]
                          }
                        ]
        , test "a member editing their own payment info is not flagged" <|
            \_ ->
                let
                    events : List Envelope
                    events =
                        foreignPaymentEvents
                            ++ [ makeEnvelope "meta-self" 400 "bob-dev" (MemberMetadataUpdated { rootId = "bob", metadata = attackerMetadata }) ]
                in
                SuspicionAudit.audit "admin" (stateOf events) events
                    |> List.filter (\f -> f.culprit == "bob-dev")
                    |> Expect.equal []
        , test "editing a virtual placeholder's payment info is not flagged" <|
            \_ ->
                let
                    events : List Envelope
                    events =
                        [ makeEnvelope "g" 0 "admin" (GroupCreated { name = "Trip", defaultCurrency = EUR })
                        , makeEnvelope "m-admin" 1 "admin" (MemberCreated { memberId = "admin", name = "Admin", memberType = Member.Real, addedBy = "admin" })
                        , makeEnvelope "m-ghost" 2 "admin" (MemberCreated { memberId = "ghost", name = "Ghost", memberType = Member.Virtual, addedBy = "admin" })
                        , makeEnvelope "meta-ghost" 300 "admin" (MemberMetadataUpdated { rootId = "ghost", metadata = attackerMetadata })
                        ]
                in
                SuspicionAudit.audit "someone" (stateOf events) events
                    |> Expect.equal []
        ]


graftedDeviceSuite : Test
graftedDeviceSuite =
    describe "GraftedDeviceTamper"
        [ test "flags a grafted device whose only activity alters existing entries" <|
            \_ ->
                SuspicionAudit.audit "admin" (stateOf graftEvents) graftEvents
                    |> Expect.equal
                        [ { culprit = "mal-dev"
                          , culpritLabel = "Bob"
                          , kind = GraftedDeviceTamper { root = "bob", graftSeq = 1 }
                          , eventIds = [ "e-mal" ]
                          }
                        ]
        , test "the member's own device with broad activity is not flagged" <|
            \_ ->
                SuspicionAudit.audit "admin" (stateOf graftEvents) graftEvents
                    |> List.filter (\f -> f.culprit == "bob-dev")
                    |> Expect.equal []
        , test "a first-device member who only edits is not flagged (no established root)" <|
            \_ ->
                let
                    events : List Envelope
                    events =
                        [ makeEnvelope "g" 0 "admin" (GroupCreated { name = "Trip", defaultCurrency = EUR })
                        , makeEnvelope "m-admin" 1 "admin" (MemberCreated { memberId = "admin", name = "Admin", memberType = Member.Real, addedBy = "admin" })
                        , makeEnvelope "m-bob" 2 "admin" (MemberCreated { memberId = "bob", name = "Bob", memberType = Member.Real, addedBy = "admin" })
                        , makeEnvelope "e-add" 90 "admin" (EntryAdded (makeExpenseEntry "entry-bob" 90 defaultExpenseData))
                        , makeEnvelope "link-bob" 3 "bob-dev" (MemberLinked { rootId = "bob", deviceId = "bob-dev", seq = 0 })
                        , makeEnvelope "e-bob" 100 "bob-dev" (EntryModified graftHijack)
                        ]
                in
                SuspicionAudit.audit "admin" (stateOf events) events
                    |> Expect.equal []
        ]


suppressionSuite : Test
suppressionSuite =
    describe "culprit-device suppression"
        [ test "the implicated device does not see its own finding" <|
            \_ ->
                SuspicionAudit.audit "mallory" (stateOf foreignPaymentEvents) foreignPaymentEvents
                    |> Expect.equal []
        , test "the grafted device does not see its own finding, but others do" <|
            \_ ->
                ( SuspicionAudit.audit "mal-dev" (stateOf graftEvents) graftEvents
                , SuspicionAudit.audit "bob-dev" (stateOf graftEvents) graftEvents |> List.length
                )
                    |> Expect.equal ( [], 1 )
        ]


dismissKeySuite : Test
dismissKeySuite =
    describe "dismissKey"
        [ test "encodes kind, culprit and offending events for a foreign edit" <|
            \_ ->
                SuspicionAudit.audit "admin" (stateOf foreignPaymentEvents) foreignPaymentEvents
                    |> List.map SuspicionAudit.dismissKey
                    |> Expect.equal [ "fpe:bob:mallory:meta-hijack" ]
        , test "a grafted-device key is distinct from a payment-edit key" <|
            \_ ->
                SuspicionAudit.audit "admin" (stateOf graftEvents) graftEvents
                    |> List.map SuspicionAudit.dismissKey
                    |> Expect.equal [ "gdt:bob:mal-dev:e-mal" ]
        ]
