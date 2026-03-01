module CodecTest exposing (suite)

import Domain.Currency as Currency exposing (Currency(..))
import Domain.Date as Date exposing (Date)
import Domain.Entry as Entry exposing (Beneficiary(..), Category(..), Kind(..))
import Domain.Event as Event exposing (Payload(..))
import Domain.Group as Group
import Domain.Member as Member
import Expect
import Fuzz exposing (Fuzzer)
import Identity
import Json.Decode as Decode
import Json.Encode as Encode
import Test exposing (..)
import Time


suite : Test
suite =
    describe "JSON Codecs"
        [ currencyTests
        , dateTests
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
        , payloadTests
        , envelopeTests
        ]



-- Fuzzers


currencyFuzzer : Fuzzer Currency
currencyFuzzer =
    Fuzz.oneOf
        [ Fuzz.constant USD
        , Fuzz.constant EUR
        , Fuzz.constant GBP
        , Fuzz.constant CHF
        ]


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
    Fuzz.map7 Entry.TransferData
        Fuzz.int
        currencyFuzzer
        (Fuzz.maybe Fuzz.int)
        dateFuzzer
        Fuzz.string
        Fuzz.string
        (Fuzz.maybe Fuzz.string)


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


kindFuzzer : Fuzzer Kind
kindFuzzer =
    Fuzz.oneOf
        [ Fuzz.map Expense expenseDataFuzzer
        , Fuzz.map Transfer transferDataFuzzer
        ]


entryFuzzer : Fuzzer Entry.Entry
entryFuzzer =
    Fuzz.map2 Entry.Entry
        entryMetadataFuzzer
        kindFuzzer


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
        , Fuzz.map3 (\rid prev new -> MemberReplaced { rootId = rid, previousId = prev, newId = new }) Fuzz.string Fuzz.string Fuzz.string
        , Fuzz.map2 (\rid meta -> MemberMetadataUpdated { rootId = rid, metadata = meta }) Fuzz.string memberMetadataFuzzer
        , Fuzz.map EntryAdded entryFuzzer
        , Fuzz.map EntryModified entryFuzzer
        , Fuzz.map (\rid -> EntryDeleted { rootId = rid }) Fuzz.string
        , Fuzz.map (\rid -> EntryUndeleted { rootId = rid }) Fuzz.string
        , Fuzz.map GroupMetadataUpdated groupMetadataChangeFuzzer
        ]


envelopeFuzzer : Fuzzer Event.Envelope
envelopeFuzzer =
    Fuzz.map4 Event.Envelope
        Fuzz.string
        posixFuzzer
        Fuzz.string
        payloadFuzzer



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


payloadTests : Test
payloadTests =
    fuzz payloadFuzzer "Payload roundtrips" <|
        roundtrip Event.encodePayload Event.payloadDecoder


envelopeTests : Test
envelopeTests =
    fuzz envelopeFuzzer "Envelope roundtrips" <|
        roundtrip Event.encodeEnvelope Event.envelopeDecoder
