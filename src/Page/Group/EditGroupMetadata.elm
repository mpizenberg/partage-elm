module Page.Group.EditGroupMetadata exposing (Model, Msg, Output, UpdateResult, init, update, view)

import Domain.Event as Event
import Domain.GroupState as GroupState
import FeatherIcons
import Field
import Form
import Form.EditGroupMetadata as MetaForm
import Form.List
import Translations as T exposing (I18n)
import UI.Components
import UI.Theme as Theme
import Ui
import Ui.Font
import Ui.Input


type alias Output =
    Event.GroupMetadataChange


{-| Page model holding form state for editing group metadata.
-}
type Model
    = Model ModelData


type alias ModelData =
    { originalMeta : GroupState.GroupMetadata
    , form : MetaForm.Form
    , submitted : Bool
    , confirmingDelete : Bool
    }


{-| Messages produced by user interaction on the group metadata form.
-}
type Msg
    = InputName String
    | InputSubtitle String
    | InputDescription String
    | InputLinkLabel Form.List.Id String
    | InputLinkUrl Form.List.Id String
    | AddLink
    | RemoveLink Form.List.Id
    | Submit
    | ToggleDeleteConfirm
    | ConfirmDelete


{-| Initialize the model from existing group metadata.
-}
init : GroupState.GroupMetadata -> Model
init meta =
    Model
        { originalMeta = meta
        , form = MetaForm.form |> MetaForm.initFromMetadata meta
        , submitted = False
        , confirmingDelete = False
        }


type alias UpdateResult =
    { model : Model
    , metadataOutput : Maybe Output
    , deleteRequested : Bool
    }


noOutput : Model -> UpdateResult
noOutput model =
    { model = model, metadataOutput = Nothing, deleteRequested = False }


{-| Handle form input, submission, and delete confirmation.
-}
update : Msg -> Model -> UpdateResult
update msg (Model data) =
    case msg of
        InputName s ->
            noOutput (Model { data | form = Form.modify .name (Field.setFromString s) data.form })

        InputSubtitle s ->
            noOutput (Model { data | form = Form.modify .subtitle (Field.setFromString s) data.form })

        InputDescription s ->
            noOutput (Model { data | form = Form.modify .description (Field.setFromString s) data.form })

        InputLinkLabel id s ->
            noOutput (Model { data | form = Form.modify (\a -> a.linkLabel id) (Field.setFromString s) data.form })

        InputLinkUrl id s ->
            noOutput (Model { data | form = Form.modify (\a -> a.linkUrl id) (Field.setFromString s) data.form })

        AddLink ->
            noOutput (Model { data | form = Form.update .addLink data.form })

        RemoveLink id ->
            noOutput (Model { data | form = Form.update (\a -> a.removeLink id) data.form })

        Submit ->
            case Form.validateAsMaybe data.form of
                Just output ->
                    { model = Model data
                    , metadataOutput = Just (buildChange data.originalMeta output)
                    , deleteRequested = False
                    }

                Nothing ->
                    noOutput (Model { data | submitted = True })

        ToggleDeleteConfirm ->
            noOutput (Model { data | confirmingDelete = not data.confirmingDelete })

        ConfirmDelete ->
            { model = Model data, metadataOutput = Nothing, deleteRequested = True }


buildChange : GroupState.GroupMetadata -> MetaForm.Output -> Event.GroupMetadataChange
buildChange original output =
    { name =
        if output.name /= original.name then
            Just output.name

        else
            Nothing
    , subtitle =
        if output.subtitle /= original.subtitle then
            Just output.subtitle

        else
            Nothing
    , description =
        if output.description /= original.description then
            Just output.description

        else
            Nothing
    , links =
        if output.links /= original.links then
            Just output.links

        else
            Nothing
    }


{-| Render the group metadata editing form with save and delete options.
-}
view : I18n -> (Msg -> msg) -> Model -> Ui.Element msg
view i18n toMsg (Model data) =
    let
        nameError : Maybe String
        nameError =
            let
                field : Field.Field String
                field =
                    Form.get .name data.form
            in
            if Field.isInvalid field && (data.submitted || Field.isDirty field) then
                Just (T.fieldRequired i18n)

            else
                Nothing
    in
    Ui.column [ Ui.spacing Theme.spacing.lg, Ui.width Ui.fill ]
        [ UI.Components.formTextField
            { icon = Nothing
            , label = T.groupSettingsName i18n
            , required = True
            , placeholder = Nothing
            , value = Form.get .name data.form |> Field.toRawString
            , onChange = InputName
            , error = nameError
            }
        , UI.Components.formTextField
            { icon = Nothing
            , label = T.groupSettingsSubtitle i18n
            , required = False
            , placeholder = Just (T.groupSettingsSubtitlePlaceholder i18n)
            , value = Form.get .subtitle data.form |> Field.toRawString
            , onChange = InputSubtitle
            , error = Nothing
            }
        , UI.Components.formTextField
            { icon = Nothing
            , label = T.groupSettingsDescription i18n
            , required = False
            , placeholder = Just (T.groupSettingsDescriptionPlaceholder i18n)
            , value = Form.get .description data.form |> Field.toRawString
            , onChange = InputDescription
            , error = Nothing
            }
        , linksSection i18n data.submitted data.form
        , UI.Components.btnPrimary []
            { label = T.groupSettingsSave i18n
            , onPress = Submit
            }
        , deleteSection i18n data.confirmingDelete
        ]
        |> Ui.map toMsg


linksSection : I18n -> Bool -> MetaForm.Form -> Ui.Element Msg
linksSection i18n submitted formData =
    let
        linkEntries : List ( Form.List.Id, MetaForm.LinkForm )
        linkEntries =
            Form.List.toList (Form.get .links formData)
    in
    Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
        [ UI.Components.formLabel (T.groupSettingsLinks i18n) False
        , Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
            (List.map (\( id, _ ) -> linkRow i18n submitted id formData) linkEntries)
        , UI.Components.btnOutline [ Ui.width Ui.shrink, Ui.paddingXY Theme.spacing.md Theme.spacing.sm ]
            { label = T.groupSettingsAddLink i18n
            , icon = Just (UI.Components.featherIcon 16 FeatherIcons.plus)
            , onPress = AddLink
            }
        ]


linkRow : I18n -> Bool -> Form.List.Id -> MetaForm.Form -> Ui.Element Msg
linkRow i18n submitted id formData =
    let
        labelField : Field.Field String
        labelField =
            Form.get (\a -> a.linkLabel id) formData

        urlField : Field.Field String
        urlField =
            Form.get (\a -> a.linkUrl id) formData

        showError : Field.Field a -> Bool
        showError field =
            Field.isInvalid field && (submitted || Field.isDirty field)
    in
    Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
        [ Ui.row [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill, Ui.contentCenterY ]
            [ Ui.Input.text
                [ Ui.width Ui.fill
                , Ui.padding Theme.spacing.sm
                , Ui.rounded Theme.radius.sm
                , Ui.border Theme.border
                , Ui.borderColor Theme.base.accent
                ]
                { onChange = InputLinkLabel id
                , text = Field.toRawString labelField
                , placeholder = Just (T.groupSettingsLinkLabelPlaceholder i18n)
                , label = Ui.Input.labelHidden (T.groupSettingsLinkLabelPlaceholder i18n)
                }
            , UI.Components.btnOutline [ Ui.width Ui.shrink, Ui.paddingXY Theme.spacing.md Theme.spacing.sm ]
                { label = T.groupSettingsRemoveLink i18n
                , icon = Just (UI.Components.featherIcon 14 FeatherIcons.trash2)
                , onPress = RemoveLink id
                }
            ]
        , Ui.Input.text
            [ Ui.width Ui.fill
            , Ui.padding Theme.spacing.sm
            , Ui.rounded Theme.radius.sm
            , Ui.border Theme.border
            , Ui.borderColor Theme.base.accent
            ]
            { onChange = InputLinkUrl id
            , text = Field.toRawString urlField
            , placeholder = Just (T.groupSettingsLinkUrlPlaceholder i18n)
            , label = Ui.Input.labelHidden (T.groupSettingsLinkUrlPlaceholder i18n)
            }
        , if showError labelField then
            Ui.el [ Ui.Font.size Theme.font.sm, Ui.Font.color Theme.danger.text ]
                (Ui.text (T.fieldRequired i18n))

          else if showError urlField then
            Ui.el [ Ui.Font.size Theme.font.sm, Ui.Font.color Theme.danger.text ]
                (Ui.text (T.fieldInvalidUrl i18n))

          else
            Ui.none
        ]


deleteSection : I18n -> Bool -> Ui.Element Msg
deleteSection i18n confirmingDelete =
    Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
        [ UI.Components.horizontalSeparator
        , if confirmingDelete then
            Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
                [ Ui.el
                    [ Ui.width Ui.fill
                    , Ui.padding Theme.spacing.md
                    , Ui.rounded Theme.radius.md
                    , Ui.background Theme.danger.tint
                    , Ui.Font.size Theme.font.sm
                    , Ui.Font.color Theme.danger.text
                    ]
                    (Ui.text (T.groupRemoveWarning i18n))
                , UI.Components.btnDanger []
                    { label = T.groupRemoveConfirm i18n
                    , icon = FeatherIcons.trash2
                    , onPress = ConfirmDelete
                    }
                ]

          else
            UI.Components.btnOutline []
                { label = T.groupRemoveButton i18n
                , icon = Nothing
                , onPress = ToggleDeleteConfirm
                }
        ]
