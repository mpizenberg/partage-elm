module Page.NewGroup exposing (Model, Msg, init, update, view)

import Domain.Currency exposing (Currency(..))
import Field
import Form
import Form.List
import Form.NewGroup as NewGroup exposing (Output)
import Translations as T exposing (I18n)
import UI.Theme as Theme
import Ui
import Ui.Font
import Ui.Input
import Validation as V


type Model
    = Model NewGroup.Form Bool


type Msg
    = InputName String
    | InputCreatorName String
    | InputCurrency String
    | InputVirtualMemberName Form.List.Id String
    | AddVirtualMember
    | RemoveVirtualMember Form.List.Id
    | Submit


init : Model
init =
    Model NewGroup.form False


update : Msg -> Model -> ( Model, Maybe Output )
update msg (Model form submitted) =
    case msg of
        InputName s ->
            ( Model (Form.modify .name (Field.setFromString s) form) submitted
            , Nothing
            )

        InputCreatorName s ->
            ( Model (Form.modify .creatorName (Field.setFromString s) form) submitted
            , Nothing
            )

        InputCurrency s ->
            ( Model (Form.modify .currency (Field.setFromString s) form) submitted
            , Nothing
            )

        InputVirtualMemberName id s ->
            ( Model (Form.modify (\a -> a.virtualMemberName id) (Field.setFromString s) form) submitted
            , Nothing
            )

        AddVirtualMember ->
            ( Model (Form.update .addVirtualMember form) submitted
            , Nothing
            )

        RemoveVirtualMember id ->
            ( Model (Form.update (\a -> a.removeVirtualMember id) form) submitted
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
        [ Ui.el [ Ui.Font.size Theme.fontSize.xl, Ui.Font.bold ] (Ui.text (T.newGroupTitle i18n))
        , nameField i18n submitted form
        , creatorNameField i18n submitted form
        , currencyField i18n form
        , virtualMembersSection i18n form
        , submitButton i18n
        ]
        |> Ui.map toMsg


nameField : I18n -> Bool -> NewGroup.Form -> Ui.Element Msg
nameField i18n submitted form =
    let
        field =
            Form.get .name form
    in
    Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.bold ]
            (Ui.text (T.newGroupNameLabel i18n))
        , Ui.Input.text [ Ui.width Ui.fill ]
            { onChange = InputName
            , text = Field.toRawString field
            , placeholder = Just (T.newGroupNamePlaceholder i18n)
            , label = Ui.Input.labelHidden (T.newGroupNameLabel i18n)
            }
        , Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ]
            (Ui.text (T.newGroupNameHint i18n))
        , fieldError i18n submitted field
        ]


creatorNameField : I18n -> Bool -> NewGroup.Form -> Ui.Element Msg
creatorNameField i18n submitted form =
    let
        field =
            Form.get .creatorName form
    in
    Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.bold ]
            (Ui.text (T.newGroupCreatorNameLabel i18n))
        , Ui.Input.text [ Ui.width Ui.fill ]
            { onChange = InputCreatorName
            , text = Field.toRawString field
            , placeholder = Just (T.newGroupCreatorNamePlaceholder i18n)
            , label = Ui.Input.labelHidden (T.newGroupCreatorNameLabel i18n)
            }
        , Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ]
            (Ui.text (T.newGroupCreatorNameHint i18n))
        , fieldError i18n submitted field
        ]


currencyField : I18n -> NewGroup.Form -> Ui.Element Msg
currencyField i18n form =
    let
        field =
            Form.get .currency form

        selected =
            Field.toMaybe field
    in
    Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.bold ]
            (Ui.text (T.newGroupCurrencyLabel i18n))
        , Ui.Input.chooseOne Ui.row
            [ Ui.spacing Theme.spacing.sm ]
            { onChange = InputCurrency << currencyToString
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


virtualMembersSection : I18n -> NewGroup.Form -> Ui.Element Msg
virtualMembersSection i18n form =
    let
        members =
            Form.toState form |> .virtualMembers |> Form.List.toList
    in
    Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
        ([ Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.bold ]
            (Ui.text (T.newGroupVirtualMembersLabel i18n))
         , Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ]
            (Ui.text (T.newGroupVirtualMembersHint i18n))
         ]
            ++ List.map
                (\( id, _ ) ->
                    virtualMemberRow i18n id form
                )
                members
            ++ [ addMemberButton i18n ]
        )


virtualMemberRow : I18n -> Form.List.Id -> NewGroup.Form -> Ui.Element Msg
virtualMemberRow i18n id form =
    let
        field =
            Form.get (\a -> a.virtualMemberName id) form
    in
    Ui.row [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
        [ Ui.Input.text [ Ui.width Ui.fill ]
            { onChange = InputVirtualMemberName id
            , text = Field.toRawString field
            , placeholder = Just (T.newGroupVirtualMemberPlaceholder i18n)
            , label = Ui.Input.labelHidden (T.newGroupVirtualMembersLabel i18n)
            }
        , Ui.el
            [ Ui.Input.button (RemoveVirtualMember id)
            , Ui.pointer
            , Ui.Font.color Theme.danger
            , Ui.Font.size Theme.fontSize.sm
            ]
            (Ui.text (T.newGroupRemoveMember i18n))
        ]


addMemberButton : I18n -> Ui.Element Msg
addMemberButton i18n =
    Ui.el
        [ Ui.Input.button AddVirtualMember
        , Ui.pointer
        , Ui.Font.color Theme.primary
        , Ui.Font.size Theme.fontSize.sm
        , Ui.Font.bold
        ]
        (Ui.text (T.newGroupAddMember i18n))


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
        (Ui.text (T.newGroupSubmit i18n))


fieldError : I18n -> Bool -> Field.Field a -> Ui.Element msg
fieldError i18n submitted field =
    if Field.isInvalid field && (submitted || Field.isDirty field) then
        Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.danger ]
            (Ui.text (T.fieldRequired i18n))

    else
        Ui.none
