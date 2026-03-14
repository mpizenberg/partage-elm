module Page.NewGroup exposing (Model, Msg, init, update, view)

import Browser.Dom
import Domain.Currency as Currency exposing (Currency)
import FeatherIcons
import Field
import Form
import Form.List
import Form.NewGroup as NewGroup exposing (Output)
import Html.Attributes
import List.Extra
import Task
import Translations as T exposing (I18n)
import UI.Components
import UI.Theme as Theme
import Ui
import Ui.Events
import Ui.Font
import Ui.Input
import Validation as V


{-| Page model holding the new group form and submission state.
-}
type Model
    = Model NewGroup.Form Bool


{-| Messages produced by user interaction on the new group form.
-}
type Msg
    = InputName String
    | InputCreatorName String
    | InputCurrency String
    | InputVirtualMemberName Form.List.Id String
    | AddVirtualMember
    | RemoveVirtualMember Form.List.Id
    | Submit
    | NoOp


{-| Initial model with an empty form.
-}
init : Model
init =
    Model NewGroup.form False


{-| Handle form input and submission, returning validated Output on success.
-}
update : Msg -> Model -> ( Model, Cmd Msg, Maybe Output )
update msg (Model form submitted) =
    case msg of
        InputName s ->
            ( Model (Form.modify .name (Field.setFromString s) form) submitted
            , Cmd.none
            , Nothing
            )

        InputCreatorName s ->
            ( Model (Form.modify .creatorName (Field.setFromString s) form) submitted
            , Cmd.none
            , Nothing
            )

        InputCurrency s ->
            ( Model (Form.modify .currency (Field.setFromString s) form) submitted
            , Cmd.none
            , Nothing
            )

        InputVirtualMemberName id s ->
            ( Model (Form.modify (\a -> a.virtualMemberName id) (Field.setFromString s) form) submitted
            , Cmd.none
            , Nothing
            )

        AddVirtualMember ->
            let
                updatedForm : NewGroup.Form
                updatedForm =
                    Form.update .addVirtualMember form

                lastMemberId : Maybe Form.List.Id
                lastMemberId =
                    Form.toState updatedForm
                        |> .virtualMembers
                        |> Form.List.toList
                        |> List.Extra.last
                        |> Maybe.map Tuple.first

                focusCmd : Cmd Msg
                focusCmd =
                    case lastMemberId of
                        Just id ->
                            Browser.Dom.focus (virtualMemberInputId id)
                                |> Task.attempt (\_ -> NoOp)

                        Nothing ->
                            Cmd.none
            in
            ( Model updatedForm submitted
            , focusCmd
            , Nothing
            )

        RemoveVirtualMember id ->
            ( Model (Form.update (\a -> a.removeVirtualMember id) form) submitted
            , Cmd.none
            , Nothing
            )

        Submit ->
            case Form.validate form |> V.toResult of
                Ok output ->
                    ( init, Cmd.none, Just output )

                Err _ ->
                    ( Model form True, Cmd.none, Nothing )

        NoOp ->
            ( Model form submitted, Cmd.none, Nothing )


virtualMemberInputId : Form.List.Id -> String
virtualMemberInputId id =
    "virtual-member-" ++ String.fromInt id


{-| Render the new group creation form.
-}
view : I18n -> (Msg -> msg) -> Model -> Ui.Element msg
view i18n toMsg (Model form submitted) =
    Ui.column [ Ui.spacing Theme.spacing.lg, Ui.width Ui.fill ]
        [ nameField i18n submitted form
        , creatorNameField i18n submitted form
        , virtualMembersSection i18n form
        , currencyField i18n form
        , UI.Components.btnPrimary []
            { label = T.newGroupSubmit i18n
            , onPress = Submit
            }
        ]
        |> Ui.map toMsg


formHint : String -> Ui.Element msg
formHint hint =
    Ui.el
        [ Ui.Font.size Theme.font.sm
        , Ui.Font.color Theme.base.textSubtle
        ]
        (Ui.text hint)


nameField : I18n -> Bool -> NewGroup.Form -> Ui.Element Msg
nameField i18n submitted form =
    let
        field : Field.Field String
        field =
            Form.get .name form
    in
    Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
        [ UI.Components.formLabel (T.newGroupNameLabel i18n) True
        , Ui.Input.text
            [ Ui.width Ui.fill
            , Ui.padding Theme.spacing.sm
            , Ui.rounded Theme.radius.sm
            , Ui.border Theme.border
            , Ui.borderColor Theme.base.accent
            ]
            { onChange = InputName
            , text = Field.toRawString field
            , placeholder = Just (T.newGroupNamePlaceholder i18n)
            , label = Ui.Input.labelHidden (T.newGroupNameLabel i18n)
            }
        , fieldError i18n submitted field
        ]


creatorNameField : I18n -> Bool -> NewGroup.Form -> Ui.Element Msg
creatorNameField i18n submitted form =
    let
        field : Field.Field String
        field =
            Form.get .creatorName form
    in
    Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
        [ UI.Components.formLabel (T.newGroupCreatorNameLabel i18n) True
        , Ui.Input.text
            [ Ui.width Ui.fill
            , Ui.padding Theme.spacing.sm
            , Ui.rounded Theme.radius.sm
            , Ui.border Theme.border
            , Ui.borderColor Theme.base.accent
            ]
            { onChange = InputCreatorName
            , text = Field.toRawString field
            , placeholder = Just (T.newGroupCreatorNamePlaceholder i18n)
            , label = Ui.Input.labelHidden (T.newGroupCreatorNameLabel i18n)
            }
        , fieldError i18n submitted field
        ]


currencyField : I18n -> NewGroup.Form -> Ui.Element Msg
currencyField i18n form =
    let
        selected : Maybe Currency
        selected =
            Form.get .currency form |> Field.toMaybe
    in
    Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
        [ UI.Components.formLabel (T.newGroupCurrencyLabel i18n) True
        , formHint (T.newGroupCurrencyHint i18n)
        , Ui.row [ Ui.wrap, Ui.spacing Theme.spacing.xs ]
            (List.map
                (\c ->
                    UI.Components.chip
                        -- TODO later: add currency symbol if known
                        { label = Currency.currencyCode c
                        , selected = selected == Just c
                        , onPress = InputCurrency (currencyToString c)
                        }
                )
                Currency.allCurrencies
            )
        ]


currencyToString : Currency -> String
currencyToString c =
    String.toLower (Currency.currencyCode c)


virtualMembersSection : I18n -> NewGroup.Form -> Ui.Element Msg
virtualMembersSection i18n form =
    let
        members : List ( Form.List.Id, NewGroup.VirtualMemberForm )
        members =
            Form.toState form |> .virtualMembers |> Form.List.toList
    in
    Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
        [ UI.Components.formLabel (T.newGroupVirtualMembersLabel i18n) False
        , Ui.row [ Ui.width Ui.fill, Ui.spacing Theme.spacing.md, Ui.contentCenterY ]
            [ Ui.el
                [ Ui.Font.size Theme.font.sm
                , Ui.Font.color Theme.base.textSubtle
                , Ui.width Ui.fill
                ]
                (Ui.text "Add the names of other members of this group.")
            ]
        , Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
            (List.map
                (\( id, _ ) ->
                    virtualMemberRow i18n id form
                )
                members
            )
        , UI.Components.btnOutline [ Ui.width Ui.shrink, Ui.paddingXY Theme.spacing.md Theme.spacing.sm ]
            { label = "Add member"
            , icon = Just (UI.Components.featherIcon 16 FeatherIcons.plus)
            , onPress = AddVirtualMember
            }
        ]


virtualMemberRow : I18n -> Form.List.Id -> NewGroup.Form -> Ui.Element Msg
virtualMemberRow i18n id form =
    let
        field : Field.Field String
        field =
            Form.get (\a -> a.virtualMemberName id) form
    in
    Ui.row [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill, Ui.contentCenterY ]
        [ Ui.Input.text
            [ Ui.width Ui.fill
            , Ui.padding Theme.spacing.sm
            , Ui.rounded Theme.radius.sm
            , Ui.border Theme.border
            , Ui.borderColor Theme.base.accent
            , Ui.Events.onKey Ui.Events.enter AddVirtualMember
            , Ui.htmlAttribute (Html.Attributes.id (virtualMemberInputId id))
            ]
            { onChange = InputVirtualMemberName id
            , text = Field.toRawString field
            , placeholder = Just (T.newGroupVirtualMemberPlaceholder i18n)
            , label = Ui.Input.labelHidden (T.newGroupVirtualMembersLabel i18n)
            }
        , UI.Components.btnOutline [ Ui.width Ui.shrink, Ui.paddingXY Theme.spacing.md Theme.spacing.sm ]
            { label = T.newGroupRemoveMember i18n
            , icon = Just (UI.Components.featherIcon 14 FeatherIcons.trash2)
            , onPress = RemoveVirtualMember id
            }
        ]


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
