module Page.NewEntry exposing (Model, Msg, init, update, view)

import Field
import Form
import Form.NewEntry as NewEntry exposing (Output)
import Translations as T exposing (I18n)
import UI.Theme as Theme
import Ui
import Ui.Font
import Ui.Input
import Validation as V


type Model
    = Model NewEntry.Form Bool


type Msg
    = InputDescription String
    | InputAmount String
    | Submit


init : Model
init =
    Model NewEntry.form False


update : Msg -> Model -> ( Model, Maybe Output )
update msg (Model form submitted) =
    case msg of
        InputDescription s ->
            ( Model (Form.modify .description (Field.setFromString s) form) submitted
            , Nothing
            )

        InputAmount s ->
            ( Model (Form.modify .amount (Field.setFromString s) form) submitted
            , Nothing
            )

        Submit ->
            case Form.validate form |> V.toResult of
                Ok output ->
                    ( init, Just output )

                Err _ ->
                    ( Model form True, Nothing )


view : I18n -> (Msg -> msg) -> Model -> Ui.Element msg
view i18n toMsg (Model form submitted) =
    Ui.column [ Ui.spacing Theme.spacing.lg, Ui.width Ui.fill ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.xl, Ui.Font.bold ] (Ui.text (T.newEntryTitle i18n))
        , descriptionField i18n submitted form
        , amountField i18n submitted form
        , Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ]
            (Ui.text (T.newEntrySplitNote i18n))
        , submitButton i18n
        ]
        |> Ui.map toMsg


descriptionField : I18n -> Bool -> NewEntry.Form -> Ui.Element Msg
descriptionField i18n submitted form =
    let
        field =
            Form.get .description form
    in
    Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.bold ]
            (Ui.text (T.newEntryDescriptionLabel i18n))
        , Ui.Input.text [ Ui.width Ui.fill ]
            { onChange = InputDescription
            , text = Field.toRawString field
            , placeholder = Just (T.newEntryDescriptionPlaceholder i18n)
            , label = Ui.Input.labelHidden (T.newEntryDescriptionLabel i18n)
            }
        , Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ]
            (Ui.text (T.newEntryDescriptionHint i18n))
        , fieldError i18n submitted field
        ]


amountField : I18n -> Bool -> NewEntry.Form -> Ui.Element Msg
amountField i18n submitted form =
    let
        field =
            Form.get .amount form
    in
    Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.bold ]
            (Ui.text (T.newEntryAmountLabel i18n))
        , Ui.Input.text [ Ui.width Ui.fill ]
            { onChange = InputAmount
            , text = Field.toRawString field
            , placeholder = Just (T.newEntryAmountPlaceholder i18n)
            , label = Ui.Input.labelHidden (T.newEntryAmountLabel i18n)
            }
        , Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ]
            (Ui.text (T.newEntryAmountHint i18n))
        , fieldError i18n submitted field
        ]


submitButton : I18n -> Ui.Element Msg
submitButton i18n =
    Ui.el
        [ Ui.Input.button Submit
        , Ui.width Ui.fill
        , Ui.padding Theme.spacing.md
        , Ui.rounded Theme.rounding.md
        , Ui.background Theme.primary
        , Ui.Font.color Theme.white
        , Ui.Font.center
        , Ui.Font.bold
        , Ui.pointer
        ]
        (Ui.text (T.newEntrySubmit i18n))


fieldError : I18n -> Bool -> Field.Field a -> Ui.Element msg
fieldError i18n submitted field =
    if Field.isInvalid field && (submitted || Field.isDirty field) then
        Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.danger ]
            (Ui.text (T.fieldRequired i18n))

    else
        Ui.none
