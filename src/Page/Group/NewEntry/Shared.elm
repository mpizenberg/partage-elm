module Page.Group.NewEntry.Shared exposing
    ( Config
    , EntryKind(..)
    , ModelData
    , Msg(..)
    , Output(..)
    , SplitData(..)
    , SplitMode(..)
    , amountCurrencyField
    , centsToDecimalString
    , dateField
    , defaultCurrencyAmountField
    , errorWhen
    , fieldError
    , fieldTitle
    , formField
    , formHint
    , notesField
    , parseAmountCents
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
import Field
import Form
import Form.NewEntry as NewEntry
import Html
import Html.Attributes
import Html.Events
import Translations as T exposing (I18n)
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
        { amountCents : Int
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
    }


{-| Configuration needed to initialize the new entry form.
-}
type alias Config =
    { currentUserRootId : Member.Id
    , activeMembersRootIds : List Member.Id
    , today : Date
    , defaultCurrency : Currency
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
    | InputDate String
    | Submit



-- UTILITY FUNCTIONS


parseAmountCents : String -> Maybe Int
parseAmountCents s =
    String.toFloat (String.trim s)
        |> Maybe.map (\f -> round (f * 100))
        |> Maybe.andThen
            (\cents ->
                if cents >= 0 then
                    Just cents

                else
                    Nothing
            )


centsToDecimalString : Int -> String
centsToDecimalString cents =
    let
        whole : Int
        whole =
            cents // 100

        frac : Int
        frac =
            remainderBy 100 cents
    in
    String.fromInt whole ++ "." ++ String.padLeft 2 '0' (String.fromInt frac)



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


amountCurrencyField : I18n -> ModelData -> Ui.Element Msg
amountCurrencyField i18n data =
    let
        field : Field.Field Int
        field =
            Form.get .amount data.form
    in
    formField { label = T.newEntryAmountLabel i18n, required = True }
        [ Ui.row [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill, Ui.contentCenterY ]
            [ Ui.Input.text [ Ui.width Ui.fill ]
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
                not isEmpty && parseAmountCents (String.trim data.defaultCurrencyAmount) == Nothing
        in
        formField { label = T.newEntryDefaultCurrencyAmountLabel (Currency.currencyCode data.groupDefaultCurrency) i18n, required = True }
            [ Ui.Input.text [ Ui.width Ui.fill ]
                { onChange = InputDefaultCurrencyAmount
                , text = data.defaultCurrencyAmount
                , placeholder = Just (T.newEntryAmountPlaceholder i18n)
                , label = Ui.Input.labelHidden (T.newEntryDefaultCurrencyAmountLabel (Currency.currencyCode data.groupDefaultCurrency) i18n)
                }
            , formHint (T.newEntryDefaultCurrencyAmountHint (Currency.currencyCode data.groupDefaultCurrency) i18n)
            , errorWhen (data.submitted && isEmpty) (T.fieldRequired i18n)
            , errorWhen (data.submitted && isInvalid) (T.fieldInvalidFormat i18n)
            ]


dateField : I18n -> ModelData -> Ui.Element Msg
dateField i18n data =
    let
        field : Field.Field Date
        field =
            Form.get .date data.form
    in
    formField { label = T.newEntryDateLabel i18n, required = True }
        [ Ui.Input.text [ Ui.width Ui.fill ]
            { onChange = InputDate
            , text = Field.toRawString field
            , placeholder = Just "YYYY-MM-DD"
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
