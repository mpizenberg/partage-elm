module Page.NewGroup exposing (Callbacks, view)

import Domain.Currency exposing (Currency(..))
import Field
import Form
import Form.List
import Form.NewGroup exposing (Form)
import Translations as T exposing (I18n)
import UI.Theme as Theme
import Ui
import Ui.Font
import Ui.Input


type alias Callbacks msg =
    { onInputName : String -> msg
    , onInputCreatorName : String -> msg
    , onInputCurrency : String -> msg
    , onInputVirtualMemberName : Form.List.Id -> String -> msg
    , onAddVirtualMember : msg
    , onRemoveVirtualMember : Form.List.Id -> msg
    , onSubmit : msg
    }


view : I18n -> Callbacks msg -> Form -> Ui.Element msg
view i18n callbacks formData =
    Ui.column [ Ui.spacing Theme.spacing.lg, Ui.width Ui.fill ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.xl, Ui.Font.bold ] (Ui.text (T.newGroupTitle i18n))
        , nameField i18n callbacks.onInputName formData
        , creatorNameField i18n callbacks.onInputCreatorName formData
        , currencyField i18n callbacks.onInputCurrency formData
        , virtualMembersSection i18n callbacks formData
        , submitButton i18n callbacks.onSubmit
        ]


nameField : I18n -> (String -> msg) -> Form -> Ui.Element msg
nameField i18n onChange formData =
    let
        field =
            Form.get .name formData
    in
    Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.bold ]
            (Ui.text (T.newGroupNameLabel i18n))
        , Ui.Input.text [ Ui.width Ui.fill ]
            { onChange = onChange
            , text = Field.toRawString field
            , placeholder = Just (T.newGroupNamePlaceholder i18n)
            , label = Ui.Input.labelHidden (T.newGroupNameLabel i18n)
            }
        , Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ]
            (Ui.text (T.newGroupNameHint i18n))
        , fieldError i18n field
        ]


creatorNameField : I18n -> (String -> msg) -> Form -> Ui.Element msg
creatorNameField i18n onChange formData =
    let
        field =
            Form.get .creatorName formData
    in
    Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.bold ]
            (Ui.text (T.newGroupCreatorNameLabel i18n))
        , Ui.Input.text [ Ui.width Ui.fill ]
            { onChange = onChange
            , text = Field.toRawString field
            , placeholder = Just (T.newGroupCreatorNamePlaceholder i18n)
            , label = Ui.Input.labelHidden (T.newGroupCreatorNameLabel i18n)
            }
        , Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ]
            (Ui.text (T.newGroupCreatorNameHint i18n))
        , fieldError i18n field
        ]


currencyField : I18n -> (String -> msg) -> Form -> Ui.Element msg
currencyField i18n onChange formData =
    let
        field =
            Form.get .currency formData

        selected =
            Field.toMaybe field
    in
    Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.bold ]
            (Ui.text (T.newGroupCurrencyLabel i18n))
        , Ui.Input.chooseOne Ui.row
            [ Ui.spacing Theme.spacing.sm ]
            { onChange = onChange << currencyToString
            , options =
                [ Ui.Input.option EUR (Ui.text "EUR")
                , Ui.Input.option USD (Ui.text "USD")
                , Ui.Input.option GBP (Ui.text "GBP")
                , Ui.Input.option CHF (Ui.text "CHF")
                ]
            , selected = selected
            , label = Ui.Input.labelHidden (T.newGroupCurrencyLabel i18n)
            }
        , Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ]
            (Ui.text (T.newGroupCurrencyHint i18n))
        ]


currencyToString : Currency -> String
currencyToString c =
    case c of
        USD ->
            "usd"

        EUR ->
            "eur"

        GBP ->
            "gbp"

        CHF ->
            "chf"


virtualMembersSection : I18n -> Callbacks msg -> Form -> Ui.Element msg
virtualMembersSection i18n callbacks formData =
    let
        members =
            Form.toState formData |> .virtualMembers |> Form.List.toList
    in
    Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
        ([ Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.bold ]
            (Ui.text (T.newGroupVirtualMembersLabel i18n))
         , Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ]
            (Ui.text (T.newGroupVirtualMembersHint i18n))
         ]
            ++ List.map
                (\( id, _ ) ->
                    virtualMemberRow i18n callbacks id formData
                )
                members
            ++ [ addMemberButton i18n callbacks.onAddVirtualMember ]
        )


virtualMemberRow : I18n -> Callbacks msg -> Form.List.Id -> Form -> Ui.Element msg
virtualMemberRow i18n callbacks id formData =
    let
        field =
            Form.get (\a -> a.virtualMemberName id) formData
    in
    Ui.row [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
        [ Ui.Input.text [ Ui.width Ui.fill ]
            { onChange = callbacks.onInputVirtualMemberName id
            , text = Field.toRawString field
            , placeholder = Just (T.newGroupVirtualMemberPlaceholder i18n)
            , label = Ui.Input.labelHidden (T.newGroupVirtualMembersLabel i18n)
            }
        , Ui.el
            [ Ui.Input.button (callbacks.onRemoveVirtualMember id)
            , Ui.pointer
            , Ui.Font.color Theme.danger
            , Ui.Font.size Theme.fontSize.sm
            ]
            (Ui.text (T.newGroupRemoveMember i18n))
        ]


addMemberButton : I18n -> msg -> Ui.Element msg
addMemberButton i18n onAdd =
    Ui.el
        [ Ui.Input.button onAdd
        , Ui.pointer
        , Ui.Font.color Theme.primary
        , Ui.Font.size Theme.fontSize.sm
        , Ui.Font.bold
        ]
        (Ui.text (T.newGroupAddMember i18n))


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
        (Ui.text (T.newGroupSubmit i18n))


fieldError : I18n -> Field.Field a -> Ui.Element msg
fieldError i18n field =
    if Field.isDirty field && Field.isInvalid field then
        Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.danger ]
            (Ui.text (T.fieldRequired i18n))

    else
        Ui.none
