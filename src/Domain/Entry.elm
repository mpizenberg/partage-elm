module Domain.Entry exposing
    ( Beneficiary(..)
    , Category(..)
    , Entry
    , ExpenseData
    , Id
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


encodePayer : Payer -> Encode.Value
encodePayer payer =
    Encode.object
        [ ( "memberId", Encode.string payer.memberId )
        , ( "amount", Encode.int payer.amount )
        ]


payerDecoder : Decode.Decoder Payer
payerDecoder =
    Decode.map2 Payer
        (Decode.field "memberId" Decode.string)
        (Decode.field "amount" Decode.int)


encodeBeneficiary : Beneficiary -> Encode.Value
encodeBeneficiary beneficiary =
    case beneficiary of
        ShareBeneficiary data ->
            Encode.object
                [ ( "type", Encode.string "share" )
                , ( "memberId", Encode.string data.memberId )
                , ( "shares", Encode.int data.shares )
                ]

        ExactBeneficiary data ->
            Encode.object
                [ ( "type", Encode.string "exact" )
                , ( "memberId", Encode.string data.memberId )
                , ( "amount", Encode.int data.amount )
                ]


beneficiaryDecoder : Decode.Decoder Beneficiary
beneficiaryDecoder =
    Decode.field "type" Decode.string
        |> Decode.andThen
            (\t ->
                case t of
                    "share" ->
                        Decode.map2 (\mid s -> ShareBeneficiary { memberId = mid, shares = s })
                            (Decode.field "memberId" Decode.string)
                            (Decode.field "shares" Decode.int)

                    "exact" ->
                        Decode.map2 (\mid a -> ExactBeneficiary { memberId = mid, amount = a })
                            (Decode.field "memberId" Decode.string)
                            (Decode.field "amount" Decode.int)

                    _ ->
                        Decode.fail ("Unknown beneficiary type: " ++ t)
            )


encodeMetadata : Metadata -> Encode.Value
encodeMetadata meta =
    Encode.object
        ([ ( "id", Encode.string meta.id )
         , ( "rootId", Encode.string meta.rootId )
         , ( "depth", Encode.int meta.depth )
         , ( "isDeleted", Encode.bool meta.isDeleted )
         , ( "createdBy", Encode.string meta.createdBy )
         , ( "createdAt", Encode.int (Time.posixToMillis meta.createdAt) )
         ]
            ++ (case meta.previousVersionId of
                    Just prevId ->
                        [ ( "previousVersionId", Encode.string prevId ) ]

                    Nothing ->
                        []
               )
        )


entryMetadataDecoder : Decode.Decoder Metadata
entryMetadataDecoder =
    Decode.map7 Metadata
        (Decode.field "id" Decode.string)
        (Decode.field "rootId" Decode.string)
        (Decode.maybe (Decode.field "previousVersionId" Decode.string))
        (Decode.field "depth" Decode.int)
        (Decode.field "isDeleted" Decode.bool)
        (Decode.field "createdBy" Decode.string)
        (Decode.field "createdAt" (Decode.map Time.millisToPosix Decode.int))


encodeExpenseData : ExpenseData -> Encode.Value
encodeExpenseData data =
    Encode.object
        ([ ( "description", Encode.string data.description )
         , ( "amount", Encode.int data.amount )
         , ( "currency", Currency.encodeCurrency data.currency )
         , ( "date", Date.encodeDate data.date )
         , ( "payers", Encode.list encodePayer data.payers )
         , ( "beneficiaries", Encode.list encodeBeneficiary data.beneficiaries )
         ]
            ++ List.filterMap identity
                [ Maybe.map (\v -> ( "defaultCurrencyAmount", Encode.int v )) data.defaultCurrencyAmount
                , Maybe.map (\v -> ( "category", encodeCategory v )) data.category
                , Maybe.map (\v -> ( "location", Encode.string v )) data.location
                , Maybe.map (\v -> ( "notes", Encode.string v )) data.notes
                ]
        )


expenseDataDecoder : Decode.Decoder ExpenseData
expenseDataDecoder =
    Decode.succeed ExpenseData
        |> andMap (Decode.field "description" Decode.string)
        |> andMap (Decode.field "amount" Decode.int)
        |> andMap (Decode.field "currency" Currency.currencyDecoder)
        |> andMap (Decode.maybe (Decode.field "defaultCurrencyAmount" Decode.int))
        |> andMap (Decode.field "date" Date.dateDecoder)
        |> andMap (Decode.field "payers" (Decode.list payerDecoder))
        |> andMap (Decode.field "beneficiaries" (Decode.list beneficiaryDecoder))
        |> andMap (Decode.maybe (Decode.field "category" categoryDecoder))
        |> andMap (Decode.maybe (Decode.field "location" Decode.string))
        |> andMap (Decode.maybe (Decode.field "notes" Decode.string))


encodeTransferData : TransferData -> Encode.Value
encodeTransferData data =
    Encode.object
        ([ ( "amount", Encode.int data.amount )
         , ( "currency", Currency.encodeCurrency data.currency )
         , ( "date", Date.encodeDate data.date )
         , ( "from", Encode.string data.from )
         , ( "to", Encode.string data.to )
         ]
            ++ List.filterMap identity
                [ Maybe.map (\v -> ( "defaultCurrencyAmount", Encode.int v )) data.defaultCurrencyAmount
                , Maybe.map (\v -> ( "notes", Encode.string v )) data.notes
                ]
        )


transferDataDecoder : Decode.Decoder TransferData
transferDataDecoder =
    Decode.map7 TransferData
        (Decode.field "amount" Decode.int)
        (Decode.field "currency" Currency.currencyDecoder)
        (Decode.maybe (Decode.field "defaultCurrencyAmount" Decode.int))
        (Decode.field "date" Date.dateDecoder)
        (Decode.field "from" Decode.string)
        (Decode.field "to" Decode.string)
        (Decode.maybe (Decode.field "notes" Decode.string))


encodeKind : Kind -> Encode.Value
encodeKind kind =
    case kind of
        Expense data ->
            Encode.object
                [ ( "type", Encode.string "expense" )
                , ( "data", encodeExpenseData data )
                ]

        Transfer data ->
            Encode.object
                [ ( "type", Encode.string "transfer" )
                , ( "data", encodeTransferData data )
                ]


kindDecoder : Decode.Decoder Kind
kindDecoder =
    Decode.field "type" Decode.string
        |> Decode.andThen
            (\t ->
                case t of
                    "expense" ->
                        Decode.map Expense (Decode.field "data" expenseDataDecoder)

                    "transfer" ->
                        Decode.map Transfer (Decode.field "data" transferDataDecoder)

                    _ ->
                        Decode.fail ("Unknown entry kind: " ++ t)
            )


encodeEntry : Entry -> Encode.Value
encodeEntry entry =
    Encode.object
        [ ( "meta", encodeMetadata entry.meta )
        , ( "kind", encodeKind entry.kind )
        ]


entryDecoder : Decode.Decoder Entry
entryDecoder =
    Decode.map2 Entry
        (Decode.field "meta" entryMetadataDecoder)
        (Decode.field "kind" kindDecoder)
