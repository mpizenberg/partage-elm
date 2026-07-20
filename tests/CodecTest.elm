module CodecTest exposing (suite)

import Domain.Currency as Currency exposing (Currency)
import Domain.Date as Date exposing (Date)
import Domain.Entry as Entry exposing (Beneficiary(..), Category(..), Kind(..))
import Domain.Event as Event exposing (Payload(..))
import Domain.Group as Group
import Domain.Member as Member
import Domain.Settlement as Settlement
import Expect
import Fuzz exposing (Fuzzer)
import Json.Decode as Decode
import Json.Encode as Encode
import Test exposing (Test, describe, fuzz, test)
import Time


suite : Test
suite =
    describe "JSON Codecs"
        [ currencyTests
        , dateTests
        , summaryTests
        , linkTests
        , memberTypeTests
        , paymentInfoTests
        , memberMetadataTests
        , categoryTests
        , payerTests
        , beneficiaryTests
        , entryMetadataTests
        , transferDataTests
        , expenseDataTests
        , kindTests
        , entryTests
        , groupMetadataChangeTests
        , settlementPreferenceTests
        , payloadTests
        , envelopeTests
        , forwardCompatTests
        ]



-- Fuzzers


currencyFuzzer : Fuzzer Currency
currencyFuzzer =
    Fuzz.oneOf (List.map Fuzz.constant Currency.allCurrencies)


dateFuzzer : Fuzzer Date
dateFuzzer =
    Fuzz.map3 Date
        (Fuzz.intRange 2000 2100)
        (Fuzz.intRange 1 12)
        (Fuzz.intRange 1 28)


linkFuzzer : Fuzzer Group.Link
linkFuzzer =
    Fuzz.map2 Group.Link
        Fuzz.string
        Fuzz.string


memberTypeFuzzer : Fuzzer Member.Type
memberTypeFuzzer =
    Fuzz.oneOf
        [ Fuzz.constant Member.Real
        , Fuzz.constant Member.Virtual
        ]


paymentInfoFuzzer : Fuzzer Member.PaymentInfo
paymentInfoFuzzer =
    Fuzz.map8 Member.PaymentInfo
        (Fuzz.maybe Fuzz.string)
        (Fuzz.maybe Fuzz.string)
        (Fuzz.maybe Fuzz.string)
        (Fuzz.maybe Fuzz.string)
        (Fuzz.maybe Fuzz.string)
        (Fuzz.maybe Fuzz.string)
        (Fuzz.maybe Fuzz.string)
        (Fuzz.maybe Fuzz.string)


memberMetadataFuzzer : Fuzzer Member.Metadata
memberMetadataFuzzer =
    Fuzz.map4 Member.Metadata
        (Fuzz.maybe Fuzz.string)
        (Fuzz.maybe Fuzz.string)
        (Fuzz.maybe paymentInfoFuzzer)
        (Fuzz.maybe Fuzz.string)


categoryFuzzer : Fuzzer Category
categoryFuzzer =
    Fuzz.oneOf
        [ Fuzz.constant Food
        , Fuzz.constant Transport
        , Fuzz.constant Accommodation
        , Fuzz.constant Entertainment
        , Fuzz.constant Shopping
        , Fuzz.constant Groceries
        , Fuzz.constant Utilities
        , Fuzz.constant Healthcare
        , Fuzz.constant Other
        ]


payerFuzzer : Fuzzer Entry.Payer
payerFuzzer =
    Fuzz.map2 Entry.Payer
        Fuzz.string
        Fuzz.int


beneficiaryFuzzer : Fuzzer Beneficiary
beneficiaryFuzzer =
    Fuzz.oneOf
        [ Fuzz.map2 (\mid s -> ShareBeneficiary { memberId = mid, shares = s })
            Fuzz.string
            Fuzz.int
        , Fuzz.map2 (\mid a -> ExactBeneficiary { memberId = mid, amount = a })
            Fuzz.string
            Fuzz.int
        ]


posixFuzzer : Fuzzer Time.Posix
posixFuzzer =
    Fuzz.map (\i -> Time.millisToPosix (abs i)) Fuzz.int


entryMetadataFuzzer : Fuzzer Entry.Metadata
entryMetadataFuzzer =
    Fuzz.map7 Entry.Metadata
        Fuzz.string
        Fuzz.string
        (Fuzz.maybe Fuzz.string)
        (Fuzz.intRange 0 100)
        Fuzz.bool
        Fuzz.string
        posixFuzzer


transferDataFuzzer : Fuzzer Entry.TransferData
transferDataFuzzer =
    Fuzz.constant Entry.TransferData
        |> Fuzz.andMap (Fuzz.maybe Fuzz.string)
        |> Fuzz.andMap Fuzz.int
        |> Fuzz.andMap currencyFuzzer
        |> Fuzz.andMap (Fuzz.maybe Fuzz.int)
        |> Fuzz.andMap dateFuzzer
        |> Fuzz.andMap Fuzz.string
        |> Fuzz.andMap Fuzz.string
        |> Fuzz.andMap (Fuzz.maybe Fuzz.string)
        |> Fuzz.andMap (Fuzz.list linkFuzzer)


expenseDataFuzzer : Fuzzer Entry.ExpenseData
expenseDataFuzzer =
    Fuzz.constant Entry.ExpenseData
        |> Fuzz.andMap Fuzz.string
        |> Fuzz.andMap Fuzz.int
        |> Fuzz.andMap currencyFuzzer
        |> Fuzz.andMap (Fuzz.maybe Fuzz.int)
        |> Fuzz.andMap dateFuzzer
        |> Fuzz.andMap (Fuzz.list payerFuzzer)
        |> Fuzz.andMap (Fuzz.list beneficiaryFuzzer)
        |> Fuzz.andMap (Fuzz.maybe categoryFuzzer)
        |> Fuzz.andMap (Fuzz.maybe Fuzz.string)
        |> Fuzz.andMap (Fuzz.maybe Fuzz.string)
        |> Fuzz.andMap (Fuzz.list linkFuzzer)


incomeDataFuzzer : Fuzzer Entry.IncomeData
incomeDataFuzzer =
    Fuzz.constant Entry.IncomeData
        |> Fuzz.andMap Fuzz.string
        |> Fuzz.andMap Fuzz.int
        |> Fuzz.andMap currencyFuzzer
        |> Fuzz.andMap (Fuzz.maybe Fuzz.int)
        |> Fuzz.andMap dateFuzzer
        |> Fuzz.andMap Fuzz.string
        |> Fuzz.andMap (Fuzz.list beneficiaryFuzzer)
        |> Fuzz.andMap (Fuzz.maybe Fuzz.string)
        |> Fuzz.andMap (Fuzz.list linkFuzzer)


kindFuzzer : Fuzzer Kind
kindFuzzer =
    Fuzz.oneOf
        [ Fuzz.map Expense expenseDataFuzzer
        , Fuzz.map Transfer transferDataFuzzer
        , Fuzz.map Income incomeDataFuzzer
        ]


entryFuzzer : Fuzzer Entry.Entry
entryFuzzer =
    Fuzz.map2 Entry.Entry
        entryMetadataFuzzer
        kindFuzzer


settlementPreferenceFuzzer : Fuzzer Settlement.Preference
settlementPreferenceFuzzer =
    Fuzz.map2 Settlement.Preference
        Fuzz.string
        (Fuzz.list Fuzz.string)


groupMetadataChangeFuzzer : Fuzzer Event.GroupMetadataChange
groupMetadataChangeFuzzer =
    Fuzz.map4 Event.GroupMetadataChange
        (Fuzz.maybe Fuzz.string)
        (Fuzz.maybe (Fuzz.maybe Fuzz.string))
        (Fuzz.maybe (Fuzz.maybe Fuzz.string))
        (Fuzz.maybe (Fuzz.list linkFuzzer))


payloadFuzzer : Fuzzer Payload
payloadFuzzer =
    Fuzz.oneOf
        [ Fuzz.map4 (\mid name mt addedBy -> MemberCreated { memberId = mid, name = name, memberType = mt, addedBy = addedBy })
            Fuzz.string
            Fuzz.string
            memberTypeFuzzer
            Fuzz.string
        , Fuzz.map3 (\rid oldN newN -> MemberRenamed { rootId = rid, oldName = oldN, newName = newN })
            Fuzz.string
            Fuzz.string
            Fuzz.string
        , Fuzz.map (\rid -> MemberRetired { rootId = rid }) Fuzz.string
        , Fuzz.map (\rid -> MemberUnretired { rootId = rid }) Fuzz.string
        , Fuzz.map3 (\rid deviceId seq -> MemberLinked { rootId = rid, deviceId = deviceId, seq = seq }) Fuzz.string Fuzz.string Fuzz.int
        , Fuzz.map2 (\rid meta -> MemberMetadataUpdated { rootId = rid, metadata = meta }) Fuzz.string memberMetadataFuzzer
        , Fuzz.map EntryAdded entryFuzzer
        , Fuzz.map EntryModified entryFuzzer
        , Fuzz.map (\rid -> EntryDeleted { rootId = rid }) Fuzz.string
        , Fuzz.map (\rid -> EntryUndeleted { rootId = rid }) Fuzz.string
        , Fuzz.map GroupMetadataUpdated groupMetadataChangeFuzzer
        , Fuzz.map2 (\rid prefs -> SettlementPreferencesUpdated { memberRootId = rid, preferredRecipients = prefs })
            Fuzz.string
            (Fuzz.list Fuzz.string)
        ]


envelopeFuzzer : Fuzzer Event.Envelope
envelopeFuzzer =
    Fuzz.map5 Event.wrap
        Fuzz.string
        posixFuzzer
        (Fuzz.map2 (\authorId pk -> { id = authorId, publicKey = pk }) Fuzz.string Fuzz.string)
        payloadFuzzer
        Fuzz.string



-- Roundtrip helper


roundtrip : (a -> Encode.Value) -> Decode.Decoder a -> a -> Expect.Expectation
roundtrip encode decoder value =
    value
        |> encode
        |> Decode.decodeValue decoder
        |> Expect.equal (Ok value)



-- Tests


currencyTests : Test
currencyTests =
    fuzz currencyFuzzer "Currency roundtrips" <|
        roundtrip Currency.encodeCurrency Currency.currencyDecoder


dateTests : Test
dateTests =
    fuzz dateFuzzer "Date roundtrips" <|
        roundtrip Date.encodeDate Date.dateDecoder


summaryTests : Test
summaryTests =
    describe "Group.Summary"
        [ test "round-trips including lastSyncedAt" <|
            \_ ->
                let
                    summary : Group.Summary
                    summary =
                        { id = "g1"
                        , name = "Trip"
                        , defaultCurrency = Currency.EUR
                        , isSubscribed = True
                        , isArchived = False
                        , createdAt = Time.millisToPosix 1000
                        , memberCount = 4
                        , myBalanceCents = -250
                        , lastSyncedAt = Time.millisToPosix 987654321
                        }
                in
                Group.encodeSummary summary
                    |> Decode.decodeValue Group.summaryDecoder
                    |> Expect.equal (Ok summary)
        , test "defaults lastSyncedAt to createdAt when absent (pre-upgrade records)" <|
            \_ ->
                """{"id":"g1","n":"Trip","dc":"eur","sub":false,"ar":false,"ca":5000,"mc":2,"mb":0}"""
                    |> Decode.decodeString Group.summaryDecoder
                    |> Result.map .lastSyncedAt
                    |> Expect.equal (Ok (Time.millisToPosix 5000))
        ]


linkTests : Test
linkTests =
    fuzz linkFuzzer "Link roundtrips" <|
        roundtrip Group.encodeLink Group.linkDecoder


memberTypeTests : Test
memberTypeTests =
    fuzz memberTypeFuzzer "Member.Type roundtrips" <|
        roundtrip Member.encodeType Member.typeDecoder


paymentInfoTests : Test
paymentInfoTests =
    fuzz paymentInfoFuzzer "PaymentInfo roundtrips" <|
        roundtrip Member.encodePaymentInfo Member.paymentInfoDecoder


memberMetadataTests : Test
memberMetadataTests =
    fuzz memberMetadataFuzzer "Member.Metadata roundtrips" <|
        roundtrip Member.encodeMetadata Member.metadataDecoder


categoryTests : Test
categoryTests =
    fuzz categoryFuzzer "Category roundtrips" <|
        roundtrip Entry.encodeCategory Entry.categoryDecoder


payerTests : Test
payerTests =
    fuzz payerFuzzer "Payer roundtrips" <|
        roundtrip Entry.encodePayer Entry.payerDecoder


beneficiaryTests : Test
beneficiaryTests =
    fuzz beneficiaryFuzzer "Beneficiary roundtrips" <|
        roundtrip Entry.encodeBeneficiary Entry.beneficiaryDecoder


entryMetadataTests : Test
entryMetadataTests =
    fuzz entryMetadataFuzzer "Entry.Metadata roundtrips" <|
        roundtrip Entry.encodeMetadata Entry.entryMetadataDecoder


transferDataTests : Test
transferDataTests =
    fuzz transferDataFuzzer "TransferData roundtrips" <|
        roundtrip Entry.encodeTransferData Entry.transferDataDecoder


expenseDataTests : Test
expenseDataTests =
    fuzz expenseDataFuzzer "ExpenseData roundtrips" <|
        roundtrip Entry.encodeExpenseData Entry.expenseDataDecoder


kindTests : Test
kindTests =
    fuzz kindFuzzer "Kind roundtrips" <|
        roundtrip Entry.encodeKind Entry.kindDecoder


entryTests : Test
entryTests =
    fuzz entryFuzzer "Entry roundtrips" <|
        roundtrip Entry.encodeEntry Entry.entryDecoder


groupMetadataChangeTests : Test
groupMetadataChangeTests =
    fuzz groupMetadataChangeFuzzer "GroupMetadataChange roundtrips" <|
        roundtrip Event.encodeGroupMetadataChange Event.groupMetadataChangeDecoder


settlementPreferenceTests : Test
settlementPreferenceTests =
    fuzz settlementPreferenceFuzzer "Settlement.Preference roundtrips" <|
        roundtrip Settlement.encodePreference Settlement.decodePreference


payloadTests : Test
payloadTests =
    fuzz payloadFuzzer "Payload roundtrips" <|
        roundtrip Event.encodePayload Event.payloadDecoder


envelopeTests : Test
envelopeTests =
    fuzz envelopeFuzzer "Envelope roundtrips" <|
        roundtrip Event.encodeEnvelope Event.envelopeDecoder


forwardCompatTests : Test
forwardCompatTests =
    let
        -- Envelope as a newer app version might author it: an extra field at
        -- both the envelope level ("extra") and inside the payload ("future").
        wireJson : String
        wireJson =
            """{"id":"e1","ts":123,"by":"m1","v":1,"p":{"t":"ed","r":"entry1","future":"x"},"extra":true,"sig":"s"}"""

        decoded : Result Decode.Error Event.Envelope
        decoded =
            Decode.decodeString Event.envelopeDecoder wireJson
    in
    describe "Envelope forward compatibility"
        [ Test.test "unknown fields survive re-encoding" <|
            \_ ->
                decoded
                    |> Result.map (Event.encodeEnvelope >> Encode.encode 0)
                    |> Expect.equal (Ok wireJson)
        , Test.test "canonicalize keeps unknown fields and drops only sig" <|
            \_ ->
                decoded
                    |> Result.map Event.canonicalize
                    |> Expect.equal (Ok """{"id":"e1","ts":123,"by":"m1","v":1,"p":{"t":"ed","r":"entry1","future":"x"},"extra":true}""")
        , Test.test "unknown payload type decodes to Unknown and round trips" <|
            \_ ->
                let
                    json : String
                    json =
                        """{"id":"e2","ts":5,"by":"m1","p":{"t":"zz","x":1},"sig":"s"}"""
                in
                Decode.decodeString Event.envelopeDecoder json
                    |> Result.map (\env -> ( env.payload, env.version, Encode.encode 0 (Event.encodeEnvelope env) ))
                    |> Expect.equal (Ok ( Unknown, 1, json ))
        , Test.test "locally-authored envelopes sign the same shape they encode" <|
            \_ ->
                let
                    envelope : Event.Envelope
                    envelope =
                        Event.wrap "e1" (Time.millisToPosix 123) { id = "m1", publicKey = "pk1" } (EntryDeleted { rootId = "entry1" }) ""
                            |> Event.withSignature "s"
                in
                Decode.decodeString Event.envelopeDecoder (Encode.encode 0 (Event.encodeEnvelope envelope))
                    |> Result.map Event.canonicalize
                    |> Expect.equal (Ok (Event.canonicalize envelope))
        , Test.test "self member-creation introduces the author key at the envelope level" <|
            \_ ->
                let
                    envelope : Event.Envelope
                    envelope =
                        Event.wrap "e1"
                            (Time.millisToPosix 1)
                            { id = "m1", publicKey = "pk1" }
                            (MemberCreated { memberId = "m1", name = "Me", memberType = Member.Real, addedBy = "m1" })
                            "s"
                in
                ( envelope.authorKey
                , Encode.encode 0 (Event.encodeEnvelope envelope)
                    |> String.contains "\"key\":\"pk1\""
                )
                    |> Expect.equal ( Just "pk1", True )
        , Test.test "author key survives an unknown payload type" <|
            \_ ->
                let
                    json : String
                    json =
                        """{"id":"e3","ts":5,"by":"m1","v":1,"key":"pk1","p":{"t":"zz"},"sig":"s"}"""
                in
                Decode.decodeString Event.envelopeDecoder json
                    |> Result.map (\env -> ( env.payload, env.authorKey, Encode.encode 0 (Event.encodeEnvelope env) ))
                    |> Expect.equal (Ok ( Unknown, Just "pk1", json ))
        , Test.test "canonicalize matches JSON.stringify byte-for-byte on an externally-authored envelope" <|
            -- Fixture from scripts/generate-benchmark-group.mjs, which signs
            -- JSON.stringify of the sig-less envelope. Signatures on generated
            -- (and any JS-authored) events only verify if Elm's re-encoding of
            -- the parsed wire object — JWK escapes included — is identical.
            \_ ->
                let
                    wire : String
                    wire =
                        "{\"id\":\"0190d176-75c6-7708-840f-2fc887062cd7\",\"ts\":1721501119942,\"by\":\"d81a0c70d98a8a3c9e0171532b472da4058f51b623952fc6c7b3755141a90f9d\",\"v\":1,\"key\":\"{\\\"key_ops\\\":[\\\"verify\\\"],\\\"ext\\\":true,\\\"kty\\\":\\\"EC\\\",\\\"x\\\":\\\"nVGl5CbM6PR5_AvhBnZcMk2ngWCCnhaCjJ4Z63BebgA\\\",\\\"y\\\":\\\"JHzVUR5UJ6gxdAJ3d9ERrK-SrbjweLR6SguMWdeize8\\\",\\\"crv\\\":\\\"P-256\\\"}\",\"p\":{\"t\":\"mc\",\"m\":\"d81a0c70d98a8a3c9e0171532b472da4058f51b623952fc6c7b3755141a90f9d\",\"n\":\"Alice\",\"mt\":\"real\",\"ab\":\"d81a0c70d98a8a3c9e0171532b472da4058f51b623952fc6c7b3755141a90f9d\"},\"sig\":\"DCeYpEmWvpUdRJRyHJwnk5F6pSoDF72gmrXb6PKavCTRNQhBx9mL5XdCwUz38gAJ49NqvtOUF+GyBy/SGINJew==\"}"

                    canonical : String
                    canonical =
                        "{\"id\":\"0190d176-75c6-7708-840f-2fc887062cd7\",\"ts\":1721501119942,\"by\":\"d81a0c70d98a8a3c9e0171532b472da4058f51b623952fc6c7b3755141a90f9d\",\"v\":1,\"key\":\"{\\\"key_ops\\\":[\\\"verify\\\"],\\\"ext\\\":true,\\\"kty\\\":\\\"EC\\\",\\\"x\\\":\\\"nVGl5CbM6PR5_AvhBnZcMk2ngWCCnhaCjJ4Z63BebgA\\\",\\\"y\\\":\\\"JHzVUR5UJ6gxdAJ3d9ERrK-SrbjweLR6SguMWdeize8\\\",\\\"crv\\\":\\\"P-256\\\"}\",\"p\":{\"t\":\"mc\",\"m\":\"d81a0c70d98a8a3c9e0171532b472da4058f51b623952fc6c7b3755141a90f9d\",\"n\":\"Alice\",\"mt\":\"real\",\"ab\":\"d81a0c70d98a8a3c9e0171532b472da4058f51b623952fc6c7b3755141a90f9d\"}}"
                in
                Decode.decodeString Event.envelopeDecoder wire
                    |> Result.map (\env -> ( Event.canonicalize env, Encode.encode 0 (Event.encodeEnvelope env) ))
                    |> Expect.equal (Ok ( canonical, wire ))
        , Test.test "a generated expense envelope decodes to a real payload, not Unknown" <|
            \_ ->
                let
                    wire : String
                    wire =
                        "{\"id\":\"01920891-ca43-7835-8064-f4b893d6a61b\",\"ts\":1726720625219,\"by\":\"d81a0c70d98a8a3c9e0171532b472da4058f51b623952fc6c7b3755141a90f9d\",\"v\":1,\"p\":{\"t\":\"ea\",\"e\":{\"m\":{\"id\":\"01920526-57db-7da1-83f5-cfe9513802e9\",\"r\":\"01920526-57db-7da1-83f5-cfe9513802e9\",\"dp\":0,\"del\":false,\"cb\":\"d81a0c70d98a8a3c9e0171532b472da4058f51b623952fc6c7b3755141a90f9d\",\"ca\":1726663251931},\"k\":{\"t\":\"expense\",\"d\":{\"desc\":\"Taxi run\",\"a\":9876,\"cur\":\"eur\",\"dt\":{\"y\":2024,\"mo\":9,\"dy\":18},\"pay\":[{\"m\":\"d81a0c70d98a8a3c9e0171532b472da4058f51b623952fc6c7b3755141a90f9d\",\"a\":9876}],\"ben\":[{\"t\":\"share\",\"m\":\"35c0b05a-5a29-41e8-872b-b5b92d411b7b\",\"s\":1},{\"t\":\"share\",\"m\":\"2843f051-0cd7-4e07-a106-2ca064585611\",\"s\":1},{\"t\":\"share\",\"m\":\"e52f2df739338078a3d4333ea33ae92b775702f832cc53f00a9d1317a3f5b432\",\"s\":1},{\"t\":\"share\",\"m\":\"0d7d08a42b7e774884acba7d8adc1ef5f6418bc7e6f04697d9cee0c8e7346772\",\"s\":1}],\"loc\":\"Grenoble\",\"nt\":\"Split evenly as usual\"}}}},\"sig\":\"NHrtLOxNa4LivkXognLBg585rwL7yw49LQ2sPtgoR7Z4XsyNG5BJe+JaBS2VscmkEFhe55nCpFyKvXGoj058+Q==\"}"
                in
                Decode.decodeString Event.envelopeDecoder wire
                    |> Result.map
                        (\env ->
                            case env.payload of
                                EntryAdded entry ->
                                    ( entry.meta.depth
                                    , case entry.kind of
                                        Entry.Expense data ->
                                            ( data.description, data.amount, List.length data.beneficiaries )

                                        _ ->
                                            ( "not an expense", 0, 0 )
                                    )

                                _ ->
                                    ( -1, ( "not EntryAdded", 0, 0 ) )
                        )
                    |> Expect.equal (Ok ( 0, ( "Taxi run", 9876, 4 ) ))
        ]
