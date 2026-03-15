module Domain.Entry exposing
    ( Beneficiary(..)
    , Category(..)
    , Entry
    , ExpenseData
    , Id
    , IncomeData
    , Kind(..)
    , Metadata
    , Payer
    , TransferData
    , beneficiaryDecoder
    , categoryDecoder
    , encodeBeneficiary
    , encodeCategory
    , encodeEntry
    , encodeExpenseData
    , encodeKind
    , encodeMetadata
    , encodePayer
    , encodeTransferData
    , entryDecoder
    , entryMetadataDecoder
    , expenseDataDecoder
    , kindDecoder
    , newMetadata
    , payerDecoder
    , replace
    , transferDataDecoder
    )

{-| Ledger entries (expenses and transfers) with versioning metadata.
-}

import Domain.Currency as Currency exposing (Currency)
import Domain.Date as Date exposing (Date)
import Domain.Member as Member
import Json.Decode as Decode
import Json.Encode as Encode
import Time


{-| Unique identifier for an entry (expense or transfer).
-}
type alias Id =
    String


{-| An entry in the group ledger, combining version metadata with its content.
-}
type alias Entry =
    { meta : Metadata
    , kind : Kind
    }


{-| Helper function to link a new entry to the previous one it replaces.
-}
replace : Metadata -> Id -> Kind -> Entry
replace previousMetadata newId modified =
    { meta = { previousMetadata | id = newId, previousVersionId = Just previousMetadata.id, depth = previousMetadata.depth + 1 }
    , kind = modified
    }


{-| Version metadata for an entry. Entries form a version chain via rootId
and previousVersionId for conflict resolution.
-}
type alias Metadata =
    { id : Id
    , rootId : Id
    , previousVersionId : Maybe Id
    , depth : Int
    , isDeleted : Bool
    , createdBy : Member.Id
    , createdAt : Time.Posix
    }


{-| Create metadata for a new entry. Sets rootId equal to id
and previousVersionId to Nothing.
-}
newMetadata : Id -> Member.Id -> Time.Posix -> Metadata
newMetadata id memberId creationTime =
    { id = id
    , rootId = id
    , previousVersionId = Nothing
    , depth = 0
    , isDeleted = False
    , createdBy = memberId
    , createdAt = creationTime
    }


{-| The content of an entry: either a shared expense or a direct transfer.
-}
type Kind
    = Expense ExpenseData
    | Transfer TransferData
    | Income IncomeData


{-| Data for a shared expense: who paid, how much, and how it is split.
Amounts are in the smallest currency unit (e.g. cents).
-}
type alias ExpenseData =
    { description : String
    , amount : Int
    , currency : Currency
    , defaultCurrencyAmount : Maybe Int
    , date : Date
    , payers : List Payer
    , beneficiaries : List Beneficiary
    , category : Maybe Category
    , location : Maybe String
    , notes : Maybe String
    }


{-| Data for a direct money transfer between two members.
-}
type alias TransferData =
    { amount : Int
    , currency : Currency
    , defaultCurrencyAmount : Maybe Int
    , date : Date
    , from : Member.Id
    , to : Member.Id
    , notes : Maybe String
    }


{-| Data for an income received on behalf of the group.
The receiver collects money that is then split among beneficiaries.
-}
type alias IncomeData =
    { description : String
    , amount : Int
    , currency : Currency
    , defaultCurrencyAmount : Maybe Int
    , date : Date
    , receivedBy : Member.Id
    , beneficiaries : List Beneficiary
    , notes : Maybe String
    }


{-| A member who paid part (or all) of an expense.
-}
type alias Payer =
    { memberId : Member.Id
    , amount : Int
    }


{-| How a member benefits from an expense.
ShareBeneficiary splits proportionally by share count.
ExactBeneficiary assigns a fixed amount.
-}
type Beneficiary
    = ShareBeneficiary { memberId : Member.Id, shares : Int }
    | ExactBeneficiary { memberId : Member.Id, amount : Int }


{-| Expense category for filtering and reporting.
-}
type Category
    = Food
    | Transport
    | Accommodation
    | Entertainment
    | Shopping
    | Groceries
    | Utilities
    | Healthcare
    | Other


{-| Applicative helper for decoders with more than 8 fields.
-}
andMap : Decode.Decoder a -> Decode.Decoder (a -> b) -> Decode.Decoder b
andMap =
    Decode.map2 (|>)


{-| Encode a Category as a JSON string.
-}
encodeCategory : Category -> Encode.Value
encodeCategory category =
    Encode.string
        (case category of
            Food ->
                "food"

            Transport ->
                "transport"

            Accommodation ->
                "accommodation"

            Entertainment ->
                "entertainment"

            Shopping ->
                "shopping"

            Groceries ->
                "groceries"

            Utilities ->
                "utilities"

            Healthcare ->
                "healthcare"

            Other ->
                "other"
        )


{-| Decode a Category from a JSON string.
-}
categoryDecoder : Decode.Decoder Category
categoryDecoder =
    Decode.string
        |> Decode.andThen
            (\s ->
                case s of
                    "food" ->
                        Decode.succeed Food

                    "transport" ->
                        Decode.succeed Transport

                    "accommodation" ->
                        Decode.succeed Accommodation

                    "entertainment" ->
                        Decode.succeed Entertainment

                    "shopping" ->
                        Decode.succeed Shopping

                    "groceries" ->
                        Decode.succeed Groceries

                    "utilities" ->
                        Decode.succeed Utilities

                    "healthcare" ->
                        Decode.succeed Healthcare

                    "other" ->
                        Decode.succeed Other

                    _ ->
                        Decode.fail ("Unknown category: " ++ s)
            )


{-| Encode a Payer as a JSON object.
-}
encodePayer : Payer -> Encode.Value
encodePayer payer =
    Encode.object
        [ ( "m", Encode.string payer.memberId )
        , ( "a", Encode.int payer.amount )
        ]


{-| Decode a Payer from JSON.
-}
payerDecoder : Decode.Decoder Payer
payerDecoder =
    Decode.map2 Payer
        (Decode.field "m" Decode.string)
        (Decode.field "a" Decode.int)


{-| Encode a Beneficiary as a tagged JSON object.
-}
encodeBeneficiary : Beneficiary -> Encode.Value
encodeBeneficiary beneficiary =
    case beneficiary of
        ShareBeneficiary data ->
            Encode.object
                [ ( "t", Encode.string "share" )
                , ( "m", Encode.string data.memberId )
                , ( "s", Encode.int data.shares )
                ]

        ExactBeneficiary data ->
            Encode.object
                [ ( "t", Encode.string "exact" )
                , ( "m", Encode.string data.memberId )
                , ( "a", Encode.int data.amount )
                ]


{-| Decode a Beneficiary from a tagged JSON object.
-}
beneficiaryDecoder : Decode.Decoder Beneficiary
beneficiaryDecoder =
    Decode.field "t" Decode.string
        |> Decode.andThen
            (\t ->
                case t of
                    "share" ->
                        Decode.map2 (\mid s -> ShareBeneficiary { memberId = mid, shares = s })
                            (Decode.field "m" Decode.string)
                            (Decode.field "s" Decode.int)

                    "exact" ->
                        Decode.map2 (\mid a -> ExactBeneficiary { memberId = mid, amount = a })
                            (Decode.field "m" Decode.string)
                            (Decode.field "a" Decode.int)

                    _ ->
                        Decode.fail ("Unknown beneficiary type: " ++ t)
            )


{-| Encode entry Metadata as a JSON object.
-}
encodeMetadata : Metadata -> Encode.Value
encodeMetadata meta =
    Encode.object
        ([ ( "id", Encode.string meta.id )
         , ( "r", Encode.string meta.rootId )
         , ( "dp", Encode.int meta.depth )
         , ( "del", Encode.bool meta.isDeleted )
         , ( "cb", Encode.string meta.createdBy )
         , ( "ca", Encode.int (Time.posixToMillis meta.createdAt) )
         ]
            ++ (case meta.previousVersionId of
                    Just prevId ->
                        [ ( "pv", Encode.string prevId ) ]

                    Nothing ->
                        []
               )
        )


{-| Decode entry Metadata from JSON.
-}
entryMetadataDecoder : Decode.Decoder Metadata
entryMetadataDecoder =
    Decode.map7 Metadata
        (Decode.field "id" Decode.string)
        (Decode.field "r" Decode.string)
        (Decode.maybe (Decode.field "pv" Decode.string))
        (Decode.field "dp" Decode.int)
        (Decode.field "del" Decode.bool)
        (Decode.field "cb" Decode.string)
        (Decode.field "ca" (Decode.map Time.millisToPosix Decode.int))


{-| Encode ExpenseData as a JSON object, omitting Nothing fields.
-}
encodeExpenseData : ExpenseData -> Encode.Value
encodeExpenseData data =
    Encode.object
        ([ ( "desc", Encode.string data.description )
         , ( "a", Encode.int data.amount )
         , ( "cur", Currency.encodeCurrency data.currency )
         , ( "dt", Date.encodeDate data.date )
         , ( "pay", Encode.list encodePayer data.payers )
         , ( "ben", Encode.list encodeBeneficiary data.beneficiaries )
         ]
            ++ List.filterMap identity
                [ Maybe.map (\v -> ( "dca", Encode.int v )) data.defaultCurrencyAmount
                , Maybe.map (\v -> ( "cat", encodeCategory v )) data.category
                , Maybe.map (\v -> ( "loc", Encode.string v )) data.location
                , Maybe.map (\v -> ( "nt", Encode.string v )) data.notes
                ]
        )


{-| Decode ExpenseData from JSON using applicative-style decoding.
-}
expenseDataDecoder : Decode.Decoder ExpenseData
expenseDataDecoder =
    Decode.succeed ExpenseData
        |> andMap (Decode.field "desc" Decode.string)
        |> andMap (Decode.field "a" Decode.int)
        |> andMap (Decode.field "cur" Currency.currencyDecoder)
        |> andMap (Decode.maybe (Decode.field "dca" Decode.int))
        |> andMap (Decode.field "dt" Date.dateDecoder)
        |> andMap (Decode.field "pay" (Decode.list payerDecoder))
        |> andMap (Decode.field "ben" (Decode.list beneficiaryDecoder))
        |> andMap (Decode.maybe (Decode.field "cat" categoryDecoder))
        |> andMap (Decode.maybe (Decode.field "loc" Decode.string))
        |> andMap (Decode.maybe (Decode.field "nt" Decode.string))


{-| Encode TransferData as a JSON object, omitting Nothing fields.
-}
encodeTransferData : TransferData -> Encode.Value
encodeTransferData data =
    Encode.object
        ([ ( "a", Encode.int data.amount )
         , ( "cur", Currency.encodeCurrency data.currency )
         , ( "dt", Date.encodeDate data.date )
         , ( "f", Encode.string data.from )
         , ( "to", Encode.string data.to )
         ]
            ++ List.filterMap identity
                [ Maybe.map (\v -> ( "dca", Encode.int v )) data.defaultCurrencyAmount
                , Maybe.map (\v -> ( "nt", Encode.string v )) data.notes
                ]
        )


{-| Decode TransferData from JSON.
-}
transferDataDecoder : Decode.Decoder TransferData
transferDataDecoder =
    Decode.map7 TransferData
        (Decode.field "a" Decode.int)
        (Decode.field "cur" Currency.currencyDecoder)
        (Decode.maybe (Decode.field "dca" Decode.int))
        (Decode.field "dt" Date.dateDecoder)
        (Decode.field "f" Decode.string)
        (Decode.field "to" Decode.string)
        (Decode.maybe (Decode.field "nt" Decode.string))


{-| Encode IncomeData as a JSON object, omitting Nothing fields.
-}
encodeIncomeData : IncomeData -> Encode.Value
encodeIncomeData data =
    Encode.object
        ([ ( "desc", Encode.string data.description )
         , ( "a", Encode.int data.amount )
         , ( "cur", Currency.encodeCurrency data.currency )
         , ( "dt", Date.encodeDate data.date )
         , ( "rb", Encode.string data.receivedBy )
         , ( "ben", Encode.list encodeBeneficiary data.beneficiaries )
         ]
            ++ List.filterMap identity
                [ Maybe.map (\v -> ( "dca", Encode.int v )) data.defaultCurrencyAmount
                , Maybe.map (\v -> ( "nt", Encode.string v )) data.notes
                ]
        )


{-| Decode IncomeData from JSON using applicative-style decoding.
-}
incomeDataDecoder : Decode.Decoder IncomeData
incomeDataDecoder =
    Decode.succeed IncomeData
        |> andMap (Decode.field "desc" Decode.string)
        |> andMap (Decode.field "a" Decode.int)
        |> andMap (Decode.field "cur" Currency.currencyDecoder)
        |> andMap (Decode.maybe (Decode.field "dca" Decode.int))
        |> andMap (Decode.field "dt" Date.dateDecoder)
        |> andMap (Decode.field "rb" Decode.string)
        |> andMap (Decode.field "ben" (Decode.list beneficiaryDecoder))
        |> andMap (Decode.maybe (Decode.field "nt" Decode.string))


{-| Encode a Kind as a tagged JSON object with "type" and "data" fields.
-}
encodeKind : Kind -> Encode.Value
encodeKind kind =
    case kind of
        Expense data ->
            Encode.object
                [ ( "t", Encode.string "expense" )
                , ( "d", encodeExpenseData data )
                ]

        Transfer data ->
            Encode.object
                [ ( "t", Encode.string "transfer" )
                , ( "d", encodeTransferData data )
                ]

        Income data ->
            Encode.object
                [ ( "t", Encode.string "income" )
                , ( "d", encodeIncomeData data )
                ]


{-| Decode a Kind from a tagged JSON object.
-}
kindDecoder : Decode.Decoder Kind
kindDecoder =
    Decode.field "t" Decode.string
        |> Decode.andThen
            (\t ->
                case t of
                    "expense" ->
                        Decode.map Expense (Decode.field "d" expenseDataDecoder)

                    "transfer" ->
                        Decode.map Transfer (Decode.field "d" transferDataDecoder)

                    "income" ->
                        Decode.map Income (Decode.field "d" incomeDataDecoder)

                    _ ->
                        Decode.fail ("Unknown entry kind: " ++ t)
            )


{-| Encode an Entry as a JSON object.
-}
encodeEntry : Entry -> Encode.Value
encodeEntry entry =
    Encode.object
        [ ( "m", encodeMetadata entry.meta )
        , ( "k", encodeKind entry.kind )
        ]


{-| Decode an Entry from JSON.
-}
entryDecoder : Decode.Decoder Entry
entryDecoder =
    Decode.map2 Entry
        (Decode.field "m" entryMetadataDecoder)
        (Decode.field "k" kindDecoder)
