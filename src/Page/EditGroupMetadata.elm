module Page.EditGroupMetadata exposing (Model, Msg, init, update, view)

import Domain.Event as Event
import Domain.Group as Group
import Domain.GroupState as GroupState
import Field
import Form
import Form.EditGroupMetadata as MetaForm
import Form.List
import Translations as T exposing (I18n)
import UI.Theme as Theme
import Ui
import Ui.Font
import Ui.Input


type alias Output =
    Event.GroupMetadataChange


type Model
    = Model ModelData


type alias ModelData =
    { originalMeta : GroupState.GroupMetadata
    , form : MetaForm.Form
    , submitted : Bool
    , confirmingDelete : Bool
    }


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


view : I18n -> (Msg -> msg) -> Model -> Ui.Element msg
view i18n toMsg (Model data) =
    Ui.column [ Ui.spacing Theme.spacing.lg, Ui.width Ui.fill ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.xl, Ui.Font.bold ] (Ui.text (T.groupSettingsTitle i18n))
        , nameField i18n data
        , textField (T.groupSettingsSubtitle i18n) (Just (T.groupSettingsSubtitlePlaceholder i18n)) InputSubtitle .subtitle data.form
        , textField (T.groupSettingsDescription i18n) (Just (T.groupSettingsDescriptionPlaceholder i18n)) InputDescription .description data.form
        , linksSection i18n data.submitted data.form
        , saveButton i18n
        , deleteSection i18n data.confirmingDelete
        ]
        |> Ui.map toMsg


nameField : I18n -> ModelData -> Ui.Element Msg
nameField i18n data =
    let
        field =
            Form.get .name data.form
    in
    Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.bold ] (Ui.text (T.groupSettingsName i18n))
        , Ui.Input.text [ Ui.width Ui.fill ]
            { onChange = InputName
            , text = Field.toRawString field
            , placeholder = Nothing
            , label = Ui.Input.labelHidden (T.groupSettingsName i18n)
            }
        , if Field.isInvalid field && (data.submitted || Field.isDirty field) then
            Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.danger ]
                (Ui.text (T.fieldRequired i18n))

          else
            Ui.none
        ]


textField : String -> Maybe String -> (String -> Msg) -> (MetaForm.Accessors -> Form.Accessor MetaForm.State (Field.Field (Maybe String))) -> MetaForm.Form -> Ui.Element Msg
textField label placeholder onChange accessor formData =
    Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.bold ] (Ui.text label)
        , Ui.Input.text [ Ui.width Ui.fill ]
            { onChange = onChange
            , text = Form.get accessor formData |> Field.toRawString
            , placeholder = placeholder
            , label = Ui.Input.labelHidden label
            }
        ]


linksSection : I18n -> Bool -> MetaForm.Form -> Ui.Element Msg
linksSection i18n submitted formData =
    let
        linkEntries =
            Form.List.toList (Form.get .links formData)
    in
    Ui.column [ Ui.spacing Theme.spacing.md, Ui.width Ui.fill ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.lg, Ui.Font.bold ] (Ui.text (T.groupSettingsLinks i18n))
        , Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
            (List.map (\( id, _ ) -> linkRow i18n submitted id formData) linkEntries)
        , Ui.el
            [ Ui.Input.button AddLink
            , Ui.Font.color Theme.primary
            , Ui.Font.bold
            , Ui.pointer
            ]
            (Ui.text (T.groupSettingsAddLink i18n))
        ]


linkRow : I18n -> Bool -> Form.List.Id -> MetaForm.Form -> Ui.Element Msg
linkRow i18n submitted id formData =
    let
        labelField =
            Form.get (\a -> a.linkLabel id) formData

        urlField =
            Form.get (\a -> a.linkUrl id) formData

        showError field =
            Field.isInvalid field && (submitted || Field.isDirty field)
    in
    Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
        [ Ui.row [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
            [ Ui.Input.text [ Ui.width Ui.fill ]
                { onChange = InputLinkLabel id
                , text = Field.toRawString labelField
                , placeholder = Just (T.groupSettingsLinkLabelPlaceholder i18n)
                , label = Ui.Input.labelHidden (T.groupSettingsLinkLabelPlaceholder i18n)
                }
            , Ui.Input.text [ Ui.width Ui.fill ]
                { onChange = InputLinkUrl id
                , text = Field.toRawString urlField
                , placeholder = Just (T.groupSettingsLinkUrlPlaceholder i18n)
                , label = Ui.Input.labelHidden (T.groupSettingsLinkUrlPlaceholder i18n)
                }
            , Ui.el
                [ Ui.Input.button (RemoveLink id)
                , Ui.Font.color Theme.danger
                , Ui.Font.size Theme.fontSize.sm
                , Ui.pointer
                ]
                (Ui.text (T.groupSettingsRemoveLink i18n))
            ]
        , if showError labelField then
            Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.danger ]
                (Ui.text (T.fieldRequired i18n))

          else if showError urlField then
            Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.danger ]
                (Ui.text (T.fieldInvalidUrl i18n))

          else
            Ui.none
        ]


saveButton : I18n -> Ui.Element Msg
saveButton i18n =
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
        (Ui.text (T.groupSettingsSave i18n))


deleteSection : I18n -> Bool -> Ui.Element Msg
deleteSection i18n confirmingDelete =
    Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
        [ Ui.el
            [ Ui.height (Ui.px 1)
            , Ui.width Ui.fill
            , Ui.background Theme.neutral300
            ]
            Ui.none
        , if confirmingDelete then
            Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
                [ Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.danger ]
                    (Ui.text (T.groupRemoveWarning i18n))
                , Ui.el
                    [ Ui.Input.button ConfirmDelete
                    , Ui.width Ui.fill
                    , Ui.padding Theme.spacing.md
                    , Ui.rounded Theme.rounding.md
                    , Ui.background Theme.danger
                    , Ui.Font.color Theme.white
                    , Ui.Font.center
                    , Ui.Font.bold
                    , Ui.pointer
                    ]
                    (Ui.text (T.groupRemoveConfirm i18n))
                ]

          else
            Ui.el
                [ Ui.Input.button ToggleDeleteConfirm
                , Ui.width Ui.fill
                , Ui.padding Theme.spacing.md
                , Ui.rounded Theme.rounding.md
                , Ui.border Theme.borderWidth.md
                , Ui.borderColor Theme.danger
                , Ui.Font.color Theme.danger
                , Ui.Font.center
                , Ui.Font.bold
                , Ui.pointer
                ]
                (Ui.text (T.groupRemoveButton i18n))
        ]
