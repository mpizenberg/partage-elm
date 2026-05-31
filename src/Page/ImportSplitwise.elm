module Page.ImportSplitwise exposing
    ( Effect(..)
    , Model
    , Msg
    , Output
    , init
    , rateFetched
    , update
    , view
    )

{-| Confirmation step for importing a Splitwise CSV: pick the group name, the
importer's name, the default currency, and a conversion rate for any other
currency found in the file. Submitting yields an `Output` that the app turns
into a new group (see `GroupOps.importSplitwiseGroup`).
-}

import Dict exposing (Dict)
import Domain.Currency as Currency exposing (Currency)
import Infra.ExchangeRate as ExchangeRate
import SplitwiseImport exposing (Parsed)
import Translations as T exposing (I18n)
import UI.Components
import UI.Theme as Theme
import Ui
import Ui.Font
import Ui.Input


type Model
    = Model Data


type alias Data =
    { parsed : Parsed
    , groupName : String
    , creatorName : String
    , defaultCurrency : Currency
    , rateInputs : Dict String String
    , rateStatus : Dict String RateStatus
    , submitted : Bool
    }


type RateStatus
    = RateIdle
    | RateLoading
    | RateFailed


{-| Validated result of the confirmation step. `rates` maps each non-default
currency code to its value in the default currency.
-}
type alias Output =
    { groupName : String
    , creatorName : String
    , defaultCurrency : Currency
    , rates : Dict String Float
    , parsed : Parsed
    }


type Msg
    = InputGroupName String
    | InputCreatorName String
    | SelectCurrency Currency
    | InputRate Currency String
    | FetchRate Currency
    | Submit


type Effect
    = NoEffect
    | RequestRate { base : Currency, quote : Currency }
    | Done Output


{-| Build the initial model from a parsed file and a suggested group name
(typically the filename without extension). The default currency starts as the
most-used currency across the rows.
-}
init : { groupName : String, parsed : Parsed } -> Model
init { groupName, parsed } =
    Model
        { parsed = parsed
        , groupName = groupName
        , creatorName = ""
        , defaultCurrency = mostUsedCurrency parsed
        , rateInputs = Dict.empty
        , rateStatus = Dict.empty
        , submitted = False
        }


mostUsedCurrency : Parsed -> Currency
mostUsedCurrency parsed =
    let
        counts : Dict String Int
        counts =
            List.foldl
                (\row acc -> Dict.update (Currency.currencyCode row.currency) (\n -> Just (1 + Maybe.withDefault 0 n)) acc)
                Dict.empty
                parsed.rows
    in
    SplitwiseImport.usedCurrencies parsed
        |> List.sortBy (\c -> negate (Maybe.withDefault 0 (Dict.get (Currency.currencyCode c) counts)))
        |> List.head
        |> Maybe.withDefault Currency.EUR


{-| Currencies that need a conversion rate: every used currency except the
chosen default.
-}
otherCurrencies : Data -> List Currency
otherCurrencies data =
    SplitwiseImport.usedCurrencies data.parsed
        |> List.filter (\c -> c /= data.defaultCurrency)


{-| Record the result of a rate fetch (Nothing means it failed).
-}
rateFetched : Currency -> Maybe Float -> Model -> Model
rateFetched currency result (Model data) =
    let
        code : String
        code =
            Currency.currencyCode currency
    in
    case result of
        Just rate ->
            Model
                { data
                    | rateInputs = Dict.insert code (formatRate rate) data.rateInputs
                    , rateStatus = Dict.insert code RateIdle data.rateStatus
                }

        Nothing ->
            Model { data | rateStatus = Dict.insert code RateFailed data.rateStatus }


update : Msg -> Model -> ( Model, Effect )
update msg (Model data) =
    case msg of
        InputGroupName s ->
            ( Model { data | groupName = s }, NoEffect )

        InputCreatorName s ->
            ( Model { data | creatorName = s }, NoEffect )

        SelectCurrency c ->
            ( Model { data | defaultCurrency = c }, NoEffect )

        InputRate currency s ->
            ( Model { data | rateInputs = Dict.insert (Currency.currencyCode currency) s data.rateInputs }, NoEffect )

        FetchRate currency ->
            if ExchangeRate.supports currency && ExchangeRate.supports data.defaultCurrency then
                ( Model { data | rateStatus = Dict.insert (Currency.currencyCode currency) RateLoading data.rateStatus }
                , RequestRate { base = currency, quote = data.defaultCurrency }
                )

            else
                ( Model { data | rateStatus = Dict.insert (Currency.currencyCode currency) RateFailed data.rateStatus }
                , NoEffect
                )

        Submit ->
            case validate data of
                Just output ->
                    ( Model data, Done output )

                Nothing ->
                    ( Model { data | submitted = True }, NoEffect )


validate : Data -> Maybe Output
validate data =
    let
        trimmedName : String
        trimmedName =
            String.trim data.groupName

        trimmedCreator : String
        trimmedCreator =
            String.trim data.creatorName

        parsedRates : List (Maybe ( String, Float ))
        parsedRates =
            otherCurrencies data
                |> List.map
                    (\c ->
                        Dict.get (Currency.currencyCode c) data.rateInputs
                            |> Maybe.andThen (parseRate >> Maybe.map (Tuple.pair (Currency.currencyCode c)))
                    )

        rates : Maybe (Dict String Float)
        rates =
            allJust parsedRates |> Maybe.map Dict.fromList
    in
    if String.isEmpty trimmedName || String.isEmpty trimmedCreator then
        Nothing

    else
        Maybe.map
            (\rateDict ->
                { groupName = trimmedName
                , creatorName = trimmedCreator
                , defaultCurrency = data.defaultCurrency
                , rates = rateDict
                , parsed = data.parsed
                }
            )
            rates


parseRate : String -> Maybe Float
parseRate raw =
    String.toFloat (String.replace "," "." (String.trim raw))
        |> Maybe.andThen
            (\r ->
                if r > 0 then
                    Just r

                else
                    Nothing
            )


formatRate : Float -> String
formatRate rate =
    String.fromFloat (toFloat (round (rate * 10000)) / 10000)


allJust : List (Maybe a) -> Maybe (List a)
allJust =
    List.foldr (\m acc -> Maybe.map2 (::) m acc) (Just [])



-- VIEW


view : I18n -> (Msg -> msg) -> Model -> Ui.Element msg
view i18n toMsg (Model data) =
    Ui.column [ Ui.spacing Theme.spacing.lg, Ui.width Ui.fill ]
        [ Ui.el
            [ Ui.Font.size Theme.font.sm
            , Ui.Font.color Theme.base.textSubtle
            , Ui.width Ui.fill
            ]
            (Ui.text (T.splitwiseImportHint i18n))
        , previewCard i18n data
        , textField i18n (T.splitwiseImportNameLabel i18n) (T.splitwiseImportNamePlaceholder i18n) data.groupName InputGroupName (data.submitted && String.isEmpty (String.trim data.groupName))
        , textField i18n (T.splitwiseImportYourNameLabel i18n) (T.splitwiseImportYourNamePlaceholder i18n) data.creatorName InputCreatorName (data.submitted && String.isEmpty (String.trim data.creatorName))
        , currencyField i18n data
        , ratesSection i18n data
        , UI.Components.btnPrimary []
            { label = T.splitwiseImportSubmit i18n
            , onPress = Submit
            }
        ]
        |> Ui.map toMsg


previewCard : I18n -> Data -> Ui.Element Msg
previewCard i18n data =
    UI.Components.card [ Ui.padding Theme.spacing.lg ]
        [ Ui.el [ Ui.Font.size Theme.font.sm, Ui.Font.color Theme.base.textSubtle ]
            (Ui.text
                (T.splitwiseImportPreview
                    { transactions = String.fromInt (List.length data.parsed.rows)
                    , members = String.fromInt (List.length data.parsed.memberNames)
                    }
                    i18n
                )
            )
        ]


textField : I18n -> String -> String -> String -> (String -> Msg) -> Bool -> Ui.Element Msg
textField i18n label placeholder value onChange showError =
    Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
        [ UI.Components.formLabel label True
        , Ui.Input.text
            [ Ui.width Ui.fill
            , Ui.padding Theme.spacing.sm
            , Ui.rounded Theme.radius.sm
            , Ui.border Theme.border
            , Ui.borderColor Theme.base.accent
            ]
            { onChange = onChange
            , text = value
            , placeholder = Just placeholder
            , label = Ui.Input.labelHidden label
            }
        , if showError then
            Ui.el [ Ui.Font.size Theme.font.sm, Ui.Font.color Theme.danger.text ]
                (Ui.text (T.fieldRequired i18n))

          else
            Ui.none
        ]


currencyField : I18n -> Data -> Ui.Element Msg
currencyField i18n data =
    Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
        [ UI.Components.formLabel (T.splitwiseImportDefaultCurrencyLabel i18n) True
        , Ui.row [ Ui.wrap, Ui.spacing Theme.spacing.xs ]
            (List.map
                (\c ->
                    UI.Components.chip
                        { label = Currency.currencyCode c
                        , selected = data.defaultCurrency == c
                        , onPress = SelectCurrency c
                        }
                )
                (SplitwiseImport.usedCurrencies data.parsed)
            )
        ]


ratesSection : I18n -> Data -> Ui.Element Msg
ratesSection i18n data =
    case otherCurrencies data of
        [] ->
            Ui.none

        others ->
            Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
                (UI.Components.formLabel (T.splitwiseImportRatesLabel i18n) True
                    :: Ui.el [ Ui.Font.size Theme.font.sm, Ui.Font.color Theme.base.textSubtle ]
                        (Ui.text (T.splitwiseImportRatesHint i18n))
                    :: List.map (rateRow i18n data) others
                )


rateRow : I18n -> Data -> Currency -> Ui.Element Msg
rateRow i18n data currency =
    let
        code : String
        code =
            Currency.currencyCode currency

        status : RateStatus
        status =
            Dict.get code data.rateStatus |> Maybe.withDefault RateIdle

        invalid : Bool
        invalid =
            data.submitted
                && (Dict.get code data.rateInputs |> Maybe.andThen parseRate |> (==) Nothing)
    in
    Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
        [ Ui.row [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill, Ui.contentCenterY ]
            [ Ui.el [ Ui.Font.size Theme.font.sm, Ui.width Ui.shrink ]
                (Ui.text ("1 " ++ code ++ " ="))
            , Ui.Input.text
                [ Ui.width Ui.fill
                , Ui.padding Theme.spacing.sm
                , Ui.rounded Theme.radius.sm
                , Ui.border Theme.border
                , Ui.borderColor Theme.base.accent
                ]
                { onChange = InputRate currency
                , text = Dict.get code data.rateInputs |> Maybe.withDefault ""
                , placeholder = Just "1.00"
                , label = Ui.Input.labelHidden code
                }
            , Ui.el [ Ui.Font.size Theme.font.sm, Ui.width Ui.shrink ]
                (Ui.text (Currency.currencyCode data.defaultCurrency))
            , UI.Components.btnOutline [ Ui.width Ui.shrink, Ui.paddingXY Theme.spacing.md Theme.spacing.sm ]
                { label =
                    if status == RateLoading then
                        T.newEntryFetchingRate i18n

                    else
                        T.newEntryFetchRate i18n
                , icon = Nothing
                , onPress = FetchRate currency
                }
            ]
        , if status == RateFailed then
            Ui.el [ Ui.Font.size Theme.font.sm, Ui.Font.color Theme.danger.text ]
                (Ui.text (T.newEntryRateError i18n))

          else if invalid then
            Ui.el [ Ui.Font.size Theme.font.sm, Ui.Font.color Theme.danger.text ]
                (Ui.text (T.fieldRequired i18n))

          else
            Ui.none
        ]
