module Page.NewEntry exposing (Callbacks, view)

import Field
import Form
import Form.NewEntry exposing (Form)
import Translations as T exposing (I18n)
import UI.Theme as Theme
import Ui
import Ui.Font
import Ui.Input


type alias Callbacks msg =
    { onInputDescription : String -> msg
    , onInputAmount : String -> msg
    , onSubmit : msg
    }


view : I18n -> Callbacks msg -> Form -> Ui.Element msg
view i18n callbacks formData =
    Ui.column [ Ui.spacing Theme.spacing.lg, Ui.width Ui.fill ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.xl, Ui.Font.bold ] (Ui.text (T.newEntryTitle i18n))
        , descriptionField i18n formData callbacks.onInputDescription
        , amountField i18n formData callbacks.onInputAmount
        , Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ]
            (Ui.text (T.newEntrySplitNote i18n))
        , submitButton i18n callbacks.onSubmit
        ]


descriptionField : I18n -> Form -> (String -> msg) -> Ui.Element msg
descriptionField i18n formData onChange =
    let
        field =
            Form.get .description formData
    in
    Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.bold ]
            (Ui.text (T.newEntryDescriptionLabel i18n))
        , Ui.Input.text [ Ui.width Ui.fill ]
            { onChange = onChange
            , text = Field.toRawString field
            , placeholder = Just (T.newEntryDescriptionPlaceholder i18n)
            , label = Ui.Input.labelHidden (T.newEntryDescriptionLabel i18n)
            }
        , Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ]
            (Ui.text (T.newEntryDescriptionHint i18n))
        , fieldError i18n field
        ]


amountField : I18n -> Form -> (String -> msg) -> Ui.Element msg
amountField i18n formData onChange =
    let
        field =
            Form.get .amount formData
    in
    Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.bold ]
            (Ui.text (T.newEntryAmountLabel i18n))
        , Ui.Input.text [ Ui.width Ui.fill ]
            { onChange = onChange
            , text = Field.toRawString field
            , placeholder = Just (T.newEntryAmountPlaceholder i18n)
            , label = Ui.Input.labelHidden (T.newEntryAmountLabel i18n)
            }
        , Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ]
            (Ui.text (T.newEntryAmountHint i18n))
        , fieldError i18n field
        ]


submitButton : I18n -> msg -> Ui.Element msg
submitButton i18n onSubmit =
    Ui.el
        [ Ui.Input.button onSubmit
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


fieldError : I18n -> Field.Field a -> Ui.Element msg
fieldError i18n field =
    if Field.isDirty field && Field.isInvalid field then
        Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.danger ]
            (Ui.text (T.fieldRequired i18n))

    else
        Ui.none
