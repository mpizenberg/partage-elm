module Page.Group.NewEntry.Shared exposing
    ( Config
    , Effect(..)
    , EntryKind(..)
    , ModelData
    , Msg(..)
    , Output(..)
    , RateStatus(..)
    , SplitData(..)
    , SplitMode(..)
    , amountCurrencyField
    , dateField
    , decimalInputAttr
    , defaultCurrencyAmountField
    , errorWhen
    , fieldError
    , fieldTitle
    , formField
    , formHint
    , notesField
    , parseAmountCents
    , zeroAmountPlaceholder
    )

{-| Internal shared types, form helpers, and shared field views for NewEntry.

This module is internal to Page.Group.NewEntry — external code should import
Page.Group.NewEntry instead.

-}

import Dict exposing (Dict)
import Domain.Currency as Currency exposing (Currency)
import Domain.Date exposing (Date)
import Domain.Entry as Entry
import Domain.Member as Member
import FeatherIcons
import Field
import Form
import Form.NewEntry as NewEntry
import Format
import Html
import Html.Attributes
import Html.Events
import Infra.ExchangeRate as ExchangeRate
import Translations as T exposing (I18n)
import UI.Components
import UI.Theme as Theme
import Ui
import Ui.Font
import Ui.Input



-- TYPES


{-| Whether the entry being created is an expense or a transfer.
-}
type EntryKind
    = ExpenseKind
    | TransferKind
    | IncomeKind


type SplitMode
    = ShareSplit
    | ExactSplit


{-| How the expense is split among beneficiaries: by shares or exact amounts.
-}
type SplitData
    = ShareSplitData (List { memberId : Member.Id, shares : Int })
    | ExactSplitData (List { memberId : Member.Id, amount : Int })


{-| Status of an automated exchange-rate fetch for the default-currency amount.
-}
type RateStatus
    = RateIdle
    | RateLoading
    | RateFailed


{-| What the parent page should do after the form handles a message: nothing,
submit a validated entry, or fetch an exchange rate for a currency pair. This is
the form's way of telling the parent its intent without the parent having to
inspect the incoming message.
-}
type Effect
    = NoEffect
    | SubmitEntry Output
    | RequestRate { base : Currency, quote : Currency }


{-| The validated output produced on successful form submission.
-}
type Output
    = ExpenseOutput
        { description : String
        , amountCents : Int
        , currency : Currency
        , defaultCurrencyAmount : Maybe Int
        , notes : Maybe String
        , payers : List Entry.Payer
        , split : SplitData
        , category : Maybe Entry.Category
        , date : Date
        }
    | TransferOutput
        { description : Maybe String
        , amountCents : Int
        , currency : Currency
        , defaultCurrencyAmount : Maybe Int
        , fromMemberId : Member.Id
        , toMemberId : Member.Id
        , notes : Maybe String
        , date : Date
        }
    | IncomeOutput
        { description : String
        , amountCents : Int
        , currency : Currency
        , defaultCurrencyAmount : Maybe Int
        , notes : Maybe String
        , receivedBy : Member.Id
        , split : SplitData
        , date : Date
        }


type alias ModelData =
    { form : NewEntry.Form
    , submitted : Bool
    , isEditing : Bool
    , kind : EntryKind
    , kindLocked : Bool
    , payerAmounts : Dict Member.Id String
    , beneficiaries : Dict Member.Id Int
    , splitMode : SplitMode
    , exactAmounts : Dict Member.Id String
    , fromMemberId : Maybe Member.Id
    , toMemberId : Maybe Member.Id
    , receiverMemberId : Maybe Member.Id
    , category : Maybe Entry.Category
    , notes : String
    , currency : Currency
    , groupDefaultCurrency : Currency
    , defaultCurrencyAmount : String
    , rateStatus : RateStatus
    }


{-| Configuration needed to initialize the new entry form.
-}
type alias Config =
    { currentUserRootId : Member.Id
    , activeMembersRootIds : List Member.Id
    , today : Date
    , defaultCurrency : Currency
    , language : T.Language
    }


{-| Messages produced by user interaction on the new entry form.
-}
type Msg
    = SelectEntryKind EntryKind
    | InputDescription String
    | InputAmount String
    | InputNotes String
    | TogglePayer Member.Id
    | InputPayerAmount Member.Id String
    | ToggleBeneficiary Member.Id
    | IncrementShares Member.Id
    | DecrementShares Member.Id
    | InputSplitMode SplitMode
    | InputExactAmount Member.Id String
    | CycleTransferRole Member.Id
    | SelectReceiver Member.Id
    | InputCategory (Maybe Entry.Category)
    | InputCurrency Currency
    | InputDefaultCurrencyAmount String
    | FetchRate { base : Currency, quote : Currency }
    | RateFetched Currency Float
    | RateFetchFailed
    | InputDate String
    | Submit



-- UTILITY FUNCTIONS


parseAmountCents : Currency -> String -> Maybe Int
parseAmountCents currency s =
    String.toFloat (NewEntry.normalizeAmountInput s)
        |> Maybe.map (\f -> round (f * toFloat (10 ^ Currency.precision currency)))
        |> Maybe.andThen
            (\cents ->
                if cents >= 0 then
                    Just cents

                else
                    Nothing
            )



-- FORM HELPERS


formField : { label : String, required : Bool } -> List (Ui.Element msg) -> Ui.Element msg
formField config children =
    Ui.column [ Ui.width Ui.fill, Ui.spacing Theme.spacing.xs ]
        (fieldTitle config.label config.required :: children)


fieldTitle : String -> Bool -> Ui.Element msg
fieldTitle label required =
    Ui.row [ Ui.spacing Theme.spacing.xs, Ui.width Ui.shrink ]
        [ Ui.el
            [ Ui.Font.size Theme.font.sm
            , Ui.Font.weight Theme.fontWeight.semibold
            , Ui.Font.color Theme.base.textSubtle
            ]
            (Ui.text label)
        , if required then
            Ui.el [ Ui.Font.color Theme.primary.solid, Ui.Font.size Theme.font.sm ] (Ui.text "*")

          else
            Ui.none
        ]


formHint : String -> Ui.Element msg
formHint text =
    Ui.el [ Ui.Font.size Theme.font.sm, Ui.Font.color Theme.base.textSubtle ]
        (Ui.text text)


fieldError : I18n -> Bool -> Field.Field a -> Ui.Element msg
fieldError i18n submitted field =
    if Field.isInvalid field && (submitted || Field.isDirty field) then
        let
            message : String
            message =
                case Field.firstError field of
                    Just err ->
                        Field.errorToString
                            { onBlank = T.fieldRequired i18n
                            , onSyntaxError = \_ -> T.fieldInvalidFormat i18n
                            , onValidationError = \_ -> T.fieldInvalidFormat i18n
                            }
                            err

                    Nothing ->
                        T.fieldRequired i18n
        in
        Ui.el [ Ui.Font.size Theme.font.sm, Ui.Font.color Theme.danger.text ]
            (Ui.text message)

    else
        Ui.none


errorWhen : Bool -> String -> Ui.Element msg
errorWhen condition message =
    if condition then
        Ui.el [ Ui.Font.size Theme.font.sm, Ui.Font.color Theme.danger.text ]
            (Ui.text message)

    else
        Ui.none



-- SHARED FIELD VIEWS


{-| Triggers the mobile decimal keypad and hints that the field accepts decimals.
Use on every monetary amount input.
-}
decimalInputAttr : Ui.Attribute msg
decimalInputAttr =
    Ui.htmlAttribute (Html.Attributes.attribute "inputmode" "decimal")


{-| Switches the underlying input to `type="date"` so the browser shows a native
calendar picker and locale-formatted display. The input's value stays in
`YYYY-MM-DD` regardless of locale, which is what `dateFromString` parses.
-}
dateInputAttr : Ui.Attribute msg
dateInputAttr =
    Ui.htmlAttribute (Html.Attributes.type_ "date")


{-| Locale- and currency-aware placeholder for an empty amount input
(e.g. "0,00" in French for EUR, "0" for a 0-decimal currency like JPY).
-}
zeroAmountPlaceholder : I18n -> Currency -> String
zeroAmountPlaceholder i18n currency =
    Format.formatCentsForInput (T.currentLanguage i18n) 0 currency


amountCurrencyField : I18n -> ModelData -> Ui.Element Msg
amountCurrencyField i18n data =
    let
        field : Field.Field Int
        field =
            Form.get .amount data.form
    in
    formField { label = T.newEntryAmountLabel i18n, required = True }
        [ Ui.row [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill, Ui.contentCenterY ]
            [ Ui.Input.text [ Ui.width Ui.fill, decimalInputAttr ]
                { onChange = InputAmount
                , text = Field.toRawString field
                , placeholder = Just (T.newEntryAmountPlaceholder i18n)
                , label = Ui.Input.labelHidden (T.newEntryAmountLabel i18n)
                }
            , currencySelect data.currency
            ]
        , formHint (T.newEntryAmountHint i18n)
        , fieldError i18n data.submitted field
        ]


currencySelect : Currency -> Ui.Element Msg
currencySelect selected =
    Ui.html
        (Html.select
            [ Html.Events.onInput
                (\code ->
                    case Currency.currencyFromCode code of
                        Just c ->
                            InputCurrency c

                        Nothing ->
                            InputCurrency selected
                )
            , Html.Attributes.style "border" "none"
            , Html.Attributes.style "background" "transparent"
            , Html.Attributes.style "font" "inherit"
            , Html.Attributes.style "color" "inherit"
            ]
            (List.map
                (\c ->
                    Html.option
                        [ Html.Attributes.value (Currency.currencyCode c)
                        , Html.Attributes.selected (c == selected)
                        ]
                        [ Html.text (Currency.currencyCode c) ]
                )
                Currency.allCurrencies
            )
        )


defaultCurrencyAmountField : I18n -> ModelData -> Ui.Element Msg
defaultCurrencyAmountField i18n data =
    if data.currency == data.groupDefaultCurrency then
        Ui.none

    else
        let
            isEmpty : Bool
            isEmpty =
                String.isEmpty (String.trim data.defaultCurrencyAmount)

            isInvalid : Bool
            isInvalid =
                not isEmpty && parseAmountCents data.groupDefaultCurrency (String.trim data.defaultCurrencyAmount) == Nothing

            amountCents : Int
            amountCents =
                Form.get .amount data.form |> Field.toMaybe |> Maybe.withDefault 0
        in
        formField { label = T.newEntryDefaultCurrencyAmountLabel (Currency.currencyCode data.groupDefaultCurrency) i18n, required = True }
            [ Ui.row [ Ui.width Ui.fill, Ui.spacing Theme.spacing.sm, Ui.contentCenterY ]
                [ Ui.Input.text [ Ui.width Ui.fill, decimalInputAttr ]
                    { onChange = InputDefaultCurrencyAmount
                    , text = data.defaultCurrencyAmount
                    , placeholder = Just (T.newEntryAmountPlaceholder i18n)
                    , label = Ui.Input.labelHidden (T.newEntryDefaultCurrencyAmountLabel (Currency.currencyCode data.groupDefaultCurrency) i18n)
                    }
                , fetchRateControl i18n amountCents data
                ]
            , formHint (T.newEntryDefaultCurrencyAmountHint (Currency.currencyCode data.groupDefaultCurrency) i18n)
            , xeComLink i18n { base = data.currency, quote = data.groupDefaultCurrency, amountCents = amountCents }
            , errorWhen (data.rateStatus == RateFailed) (T.newEntryRateError i18n)
            , errorWhen (data.submitted && isEmpty) (T.fieldRequired i18n)
            , errorWhen (data.submitted && isInvalid) (T.fieldInvalidFormat i18n)
            ]


{-| Auto-fetch control shown beside the default-currency amount input. Renders a
"Fetch rate" button when both currencies are supported and an amount is entered,
a "Fetching…" hint while in flight, and nothing otherwise. The manual xe.com link
below is always available as a fallback.
-}
fetchRateControl : I18n -> Int -> ModelData -> Ui.Element Msg
fetchRateControl i18n amountCents data =
    let
        canAutoFetch : Bool
        canAutoFetch =
            ExchangeRate.supports data.currency
                && ExchangeRate.supports data.groupDefaultCurrency
                && (amountCents > 0)
    in
    if not canAutoFetch then
        Ui.none

    else
        case data.rateStatus of
            RateLoading ->
                formHint (T.newEntryFetchingRate i18n)

            _ ->
                UI.Components.btnOutline [ Ui.width Ui.shrink ]
                    { label = T.newEntryFetchRate i18n
                    , icon = Just (UI.Components.featherIcon 14 FeatherIcons.refreshCw)
                    , onPress = FetchRate { base = data.currency, quote = data.groupDefaultCurrency }
                    }


xeComLink : I18n -> { base : Currency, quote : Currency, amountCents : Int } -> Ui.Element msg
xeComLink i18n params =
    Ui.row
        [ Ui.linkNewTab (ExchangeRate.xeComUrl params)
        , Ui.spacing Theme.spacing.xs
        , Ui.contentCenterY
        , Ui.pointer
        , Ui.width Ui.shrink
        , Ui.Font.size Theme.font.sm
        , Ui.Font.color Theme.primary.text
        ]
        [ UI.Components.featherIcon 14 FeatherIcons.externalLink
        , Ui.el [ Ui.Font.underline ] (Ui.text (T.newEntryRateCheckXe i18n))
        ]


dateField : I18n -> ModelData -> Ui.Element Msg
dateField i18n data =
    let
        field : Field.Field Date
        field =
            Form.get .date data.form
    in
    formField { label = T.newEntryDateLabel i18n, required = True }
        [ Ui.Input.text [ Ui.width Ui.fill, dateInputAttr ]
            { onChange = InputDate
            , text = Field.toRawString field
            , placeholder = Nothing
            , label = Ui.Input.labelHidden (T.newEntryDateLabel i18n)
            }
        , fieldError i18n data.submitted field
        ]


notesField : I18n -> ModelData -> Ui.Element Msg
notesField i18n data =
    formField { label = T.newEntryNotesLabel i18n, required = False }
        [ Ui.Input.text [ Ui.width Ui.fill ]
            { onChange = InputNotes
            , text = data.notes
            , placeholder = Just (T.newEntryNotesPlaceholder i18n)
            , label = Ui.Input.labelHidden (T.newEntryNotesLabel i18n)
            }
        ]
