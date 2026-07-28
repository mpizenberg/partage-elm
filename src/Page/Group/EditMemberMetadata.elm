module Page.Group.EditMemberMetadata exposing
    ( Model
    , Msg
    , Output(..)
    , SubmittedData
    , UpdateConfig
    , ViewConfig
    , init
    , update
    , view
    )

{-| Page for editing a member's contact info and payment methods.
-}

import Dict
import Domain.Member as Member
import Domain.PaymentMethod as PaymentMethod
import FeatherIcons
import Field
import Form
import Form.EditMemberMetadata as MetadataForm
import Translations as T exposing (I18n)
import UI.Components
import UI.PaymentMethods as PaymentMethods
import UI.Theme as Theme
import Ui
import Ui.Font
import Ui.Input


{-| The validated output containing the member ID, new name, and updated metadata.
-}
type alias SubmittedData =
    { memberId : Member.Id
    , oldName : String
    , newName : String
    , metadata : Member.Metadata
    }


type Output
    = Submitted SubmittedData
    | SaveProfile Member.Metadata


{-| Page model holding form state for editing member metadata.
-}
type Model
    = Model ModelData


type alias ModelData =
    { memberId : Member.Id
    , originalName : String
    , form : MetadataForm.Form
    , submitted : Bool
    , panel : Panel

    -- Kept whole so handles this version has no field for are written back
    -- untouched instead of being dropped on save.
    , basePayment : PaymentMethod.PaymentInfo
    }


{-| Inline panel state for "Fill from saved profile" and "Save to saved profile".
-}
type Panel
    = NoPanel
    | FillPanel FieldSelections
    | SavePanel FieldSelections


type alias FieldSelections =
    List ProfileField


type ProfileField
    = PhoneField
    | EmailField
    | NotesField
    | PaymentField PaymentMethod.Method


allFields : List ProfileField
allFields =
    [ PhoneField, EmailField, NotesField ] ++ List.map PaymentField PaymentMethods.all


{-| Messages produced by user interaction on the metadata form.
-}
type Msg
    = InputName String
    | InputPhone String
    | InputEmail String
    | InputNotes String
    | InputPayment PaymentMethod.Method String
    | Submit
    | OpenFillPanel
    | OpenSavePanel
    | ClosePanel
    | ToggleField ProfileField
    | ApplyFill
    | ApplySave


{-| Initialize the model from an existing member's ID, name, and metadata.
-}
init : Member.Id -> String -> Member.Metadata -> Model
init memberId name meta =
    Model
        { memberId = memberId
        , originalName = name
        , form = MetadataForm.form |> MetadataForm.initFromMember name meta
        , submitted = False
        , panel = NoPanel
        , basePayment = meta.payment
        }


type alias UpdateConfig =
    { existingNames : List String
    , savedProfile : Member.Metadata
    }


{-| Handle form input and submission, returning a validated Output on success.
-}
update : UpdateConfig -> Msg -> Model -> ( Model, Maybe Output )
update config msg (Model data) =
    case msg of
        InputName s ->
            ( Model { data | form = Form.modify .name (Field.setFromString s) data.form }, Nothing )

        InputPhone s ->
            ( Model { data | form = Form.modify .phone (Field.setFromString s) data.form }, Nothing )

        InputEmail s ->
            ( Model { data | form = Form.modify .email (Field.setFromString s) data.form }, Nothing )

        InputNotes s ->
            ( Model { data | form = Form.modify .notes (Field.setFromString s) data.form }, Nothing )

        InputPayment method s ->
            ( Model { data | form = Form.modify (MetadataForm.payment method) (Field.setFromString s) data.form }, Nothing )

        Submit ->
            case Form.validateAsMaybe data.form of
                Just output ->
                    if
                        (String.toLower output.name /= String.toLower data.originalName)
                            && List.any (\n -> String.toLower n == String.toLower output.name) config.existingNames
                    then
                        ( Model { data | submitted = True }, Nothing )

                    else
                        ( Model data
                        , Just
                            (Submitted
                                { memberId = data.memberId
                                , oldName = data.originalName
                                , newName = output.name
                                , metadata = metadataFromOutput data.basePayment output
                                }
                            )
                        )

                Nothing ->
                    ( Model { data | submitted = True }, Nothing )

        OpenFillPanel ->
            ( Model { data | panel = FillPanel (defaultFillSelections data.form) }, Nothing )

        OpenSavePanel ->
            ( Model { data | panel = SavePanel (defaultSaveSelections data.form) }, Nothing )

        ClosePanel ->
            ( Model { data | panel = NoPanel }, Nothing )

        ToggleField field ->
            case data.panel of
                FillPanel sel ->
                    ( Model { data | panel = FillPanel (toggleField field sel) }, Nothing )

                SavePanel sel ->
                    ( Model { data | panel = SavePanel (toggleField field sel) }, Nothing )

                NoPanel ->
                    ( Model data, Nothing )

        ApplyFill ->
            case data.panel of
                FillPanel sel ->
                    ( Model
                        { data
                            | panel = NoPanel
                            , form = applyFillToForm sel config.savedProfile data.form
                        }
                    , Nothing
                    )

                _ ->
                    ( Model data, Nothing )

        ApplySave ->
            case data.panel of
                SavePanel sel ->
                    let
                        delta : Member.Metadata
                        delta =
                            selectedMetadataFromRawForm sel data.form

                        merged : Member.Metadata
                        merged =
                            mergeMetadata delta config.savedProfile
                    in
                    ( Model { data | panel = NoPanel }, Just (SaveProfile merged) )

                _ ->
                    ( Model data, Nothing )



-- Helpers


toggleField : ProfileField -> FieldSelections -> FieldSelections
toggleField field sel =
    if List.member field sel then
        List.filter ((/=) field) sel

    else
        field :: sel


{-| For Fill: default-check fields where the form is currently empty (safe pre-fill).
Fields the user has already filled stay unchecked to avoid surprise overwrites.
-}
defaultFillSelections : MetadataForm.Form -> FieldSelections
defaultFillSelections form =
    List.filter (\field -> String.isEmpty (String.trim (formValue field form))) allFields


{-| For Save: default-check fields where the form has a non-empty value.
-}
defaultSaveSelections : MetadataForm.Form -> FieldSelections
defaultSaveSelections form =
    List.filter (\field -> not (String.isEmpty (String.trim (formValue field form)))) allFields


{-| Fold the form's handles into the payment info the member already had, so
keys this version does not know survive the edit.
-}
metadataFromOutput : PaymentMethod.PaymentInfo -> MetadataForm.Output -> Member.Metadata
metadataFromOutput basePayment output =
    { phone = output.phone
    , email = output.email
    , notes = output.notes
    , payment = List.foldl (\( method, value ) -> PaymentMethod.set method value) basePayment output.payment
    }


{-| Build a Metadata delta containing only the selected fields from the form's
raw values (not the validated output, so we can save even if an unrelated field
is invalid).
-}
selectedMetadataFromRawForm : FieldSelections -> MetadataForm.Form -> Member.Metadata
selectedMetadataFromRawForm sel form =
    let
        pick : ProfileField -> Maybe String
        pick field =
            if List.member field sel then
                case String.trim (formValue field form) of
                    "" ->
                        Nothing

                    raw ->
                        Just raw

            else
                Nothing
    in
    { phone = pick PhoneField
    , email = pick EmailField
    , notes = pick NotesField
    , payment =
        List.foldl (\method -> PaymentMethod.set method (pick (PaymentField method)))
            PaymentMethod.empty
            PaymentMethods.all
    }


{-| Merge a delta into a base profile: for each field, the delta's value wins;
otherwise the base's is preserved. Payment is merged handle by handle.
-}
mergeMetadata : Member.Metadata -> Member.Metadata -> Member.Metadata
mergeMetadata delta base =
    let
        pickFirst : Maybe a -> Maybe a -> Maybe a
        pickFirst d b =
            case d of
                Just _ ->
                    d

                Nothing ->
                    b
    in
    { phone = pickFirst delta.phone base.phone
    , email = pickFirst delta.email base.email
    , notes = pickFirst delta.notes base.notes
    , payment = Dict.union delta.payment base.payment
    }


{-| Apply selected fields from the saved profile into the form.
-}
applyFillToForm : FieldSelections -> Member.Metadata -> MetadataForm.Form -> MetadataForm.Form
applyFillToForm sel profile form =
    let
        fill : ProfileField -> MetadataForm.Form -> MetadataForm.Form
        fill field f =
            case profileValue field profile of
                Just value ->
                    Form.modify (accessorFor field) (Field.setFromString value) f

                Nothing ->
                    f
    in
    List.foldl fill form sel



-- VIEW


type alias ViewConfig msg =
    { i18n : I18n
    , toMsg : Msg -> msg
    , existingNames : List String
    , isSelf : Bool
    , savedProfile : Member.Metadata
    }


{-| Render the member metadata editing form.
-}
view : ViewConfig msg -> Model -> Ui.Element msg
view config (Model data) =
    let
        i18n : I18n
        i18n =
            config.i18n

        optionalField : FeatherIcons.Icon -> String -> Maybe String -> (String -> Msg) -> (MetadataForm.Accessors -> Form.Accessor MetadataForm.State (Field.Field (Maybe String))) -> Ui.Element Msg
        optionalField icon label placeholder onChange accessor =
            UI.Components.formTextField
                { icon = Just icon
                , label = label
                , required = False
                , placeholder = placeholder
                , value = Form.get accessor data.form |> Field.toRawString
                , onChange = onChange
                , error = Nothing
                }

        nameError : Maybe String
        nameError =
            let
                field : Field.Field String
                field =
                    Form.get .name data.form
            in
            if Field.isInvalid field && (data.submitted || Field.isDirty field) then
                Just (T.fieldRequired i18n)

            else if
                let
                    currentName : String
                    currentName =
                        Field.toRawString field
                in
                (data.submitted || Field.isDirty field)
                    && (String.toLower currentName /= String.toLower data.originalName)
                    && List.any (\n -> String.toLower n == String.toLower currentName) config.existingNames
            then
                Just (T.memberAddNameTaken i18n)

            else
                Nothing

        emailError : Maybe String
        emailError =
            let
                field : Field.Field (Maybe String)
                field =
                    Form.get .email data.form
            in
            if Field.isInvalid field && (data.submitted || Field.isDirty field) then
                Just (T.fieldInvalidEmail i18n)

            else
                Nothing

        profileSection : Ui.Element Msg
        profileSection =
            if config.isSelf then
                viewProfileSection i18n config.savedProfile data

            else
                Ui.none
    in
    Ui.column [ Ui.spacing Theme.spacing.xl ]
        [ profileSection
        , Ui.column [ Ui.spacing Theme.spacing.lg ]
            [ UI.Components.formTextField
                { icon = Just FeatherIcons.user
                , label = T.memberRenameLabel i18n
                , required = True
                , placeholder = Nothing
                , value = Form.get .name data.form |> Field.toRawString
                , onChange = InputName
                , error = nameError
                }
            , optionalField FeatherIcons.phone (T.memberMetadataPhone i18n) (Just "+33 6 12 34 56 78") InputPhone .phone
            , UI.Components.formTextField
                { icon = Just FeatherIcons.atSign
                , label = T.memberMetadataEmail i18n
                , required = False
                , placeholder = Nothing
                , value = Form.get .email data.form |> Field.toRawString
                , onChange = InputEmail
                , error = emailError
                }
            , optionalField FeatherIcons.fileText (T.memberMetadataNotes i18n) (Just (T.memberMetadataNotesPlaceholder i18n)) InputNotes .notes
            ]
        , Ui.column []
            [ UI.Components.sectionLabel (T.memberMetadataPayment i18n)
            , Ui.column [ Ui.spacing Theme.spacing.lg ]
                (List.map
                    (\method ->
                        let
                            shown : PaymentMethods.Presentation
                            shown =
                                PaymentMethods.presentation method
                        in
                        optionalField shown.icon
                            (shown.label i18n)
                            (Just shown.placeholder)
                            (InputPayment method)
                            (MetadataForm.payment method)
                    )
                    PaymentMethods.all
                )
            ]
        , UI.Components.btnPrimary []
            { label = T.memberMetadataSave i18n
            , onPress = Submit
            }
        ]
        |> Ui.map config.toMsg



-- Profile section (Fill / Save panels)


viewProfileSection : I18n -> Member.Metadata -> ModelData -> Ui.Element Msg
viewProfileSection i18n profile data =
    case data.panel of
        NoPanel ->
            viewProfileButtons i18n profile

        FillPanel sel ->
            viewFillPanel i18n profile sel

        SavePanel sel ->
            viewSavePanel i18n data.form sel


viewProfileButtons : I18n -> Member.Metadata -> Ui.Element Msg
viewProfileButtons i18n profile =
    let
        profileEmpty : Bool
        profileEmpty =
            profile == Member.emptyMetadata

        fillBtn : Ui.Element Msg
        fillBtn =
            if profileEmpty then
                Ui.none

            else
                UI.Components.btnOutline []
                    { label = T.editMetadataProfileFillBtn i18n
                    , icon = Just (FeatherIcons.upload |> FeatherIcons.withSize 16 |> FeatherIcons.toHtml [] |> Ui.html)
                    , onPress = OpenFillPanel
                    }
    in
    Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
        [ fillBtn
        , UI.Components.btnOutline []
            { label = T.editMetadataProfileSaveBtn i18n
            , icon = Just (FeatherIcons.download |> FeatherIcons.withSize 16 |> FeatherIcons.toHtml [] |> Ui.html)
            , onPress = OpenSavePanel
            }
        ]


viewFillPanel : I18n -> Member.Metadata -> FieldSelections -> Ui.Element Msg
viewFillPanel i18n profile sel =
    let
        rows : List (Ui.Element Msg)
        rows =
            allFields
                |> List.filterMap
                    (\field ->
                        case profileValue field profile of
                            Just value ->
                                Just (fieldRow i18n field value (List.member field sel))

                            Nothing ->
                                Nothing
                    )

        body : Ui.Element Msg
        body =
            if List.isEmpty rows then
                Ui.el [ Ui.Font.color Theme.base.textSubtle, Ui.Font.size Theme.font.sm ]
                    (Ui.text (T.editMetadataProfileFillEmpty i18n))

            else
                Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ] rows
    in
    panelShell i18n
        { title = T.editMetadataProfileFillTitle i18n
        , description = T.editMetadataProfileFillDescription i18n
        , body = body
        , applyLabel = T.editMetadataProfileFillApply i18n
        , applyEnabled = not (List.isEmpty rows) && not (List.isEmpty sel)
        , onApply = ApplyFill
        }


viewSavePanel : I18n -> MetadataForm.Form -> FieldSelections -> Ui.Element Msg
viewSavePanel i18n form sel =
    let
        rows : List (Ui.Element Msg)
        rows =
            allFields
                |> List.filterMap
                    (\field ->
                        let
                            value : String
                            value =
                                formValue field form |> String.trim
                        in
                        if String.isEmpty value then
                            Nothing

                        else
                            Just (fieldRow i18n field value (List.member field sel))
                    )

        body : Ui.Element Msg
        body =
            if List.isEmpty rows then
                Ui.el [ Ui.Font.color Theme.base.textSubtle, Ui.Font.size Theme.font.sm ]
                    (Ui.text (T.editMetadataProfileSaveEmpty i18n))

            else
                Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ] rows
    in
    panelShell i18n
        { title = T.editMetadataProfileSaveTitle i18n
        , description = T.editMetadataProfileSaveDescription i18n
        , body = body
        , applyLabel = T.editMetadataProfileSaveApply i18n
        , applyEnabled = not (List.isEmpty rows) && not (List.isEmpty sel)
        , onApply = ApplySave
        }


panelShell :
    I18n
    ->
        { title : String
        , description : String
        , body : Ui.Element Msg
        , applyLabel : String
        , applyEnabled : Bool
        , onApply : Msg
        }
    -> Ui.Element Msg
panelShell i18n cfg =
    Ui.column
        [ Ui.spacing Theme.spacing.md
        , Ui.width Ui.fill
        , Ui.padding Theme.spacing.lg
        , Ui.background Theme.base.accent
        , Ui.rounded Theme.radius.md
        ]
        [ Ui.el [ Ui.Font.size Theme.font.md, Ui.Font.weight Theme.fontWeight.bold ]
            (Ui.text cfg.title)
        , Ui.el [ Ui.Font.size Theme.font.sm, Ui.Font.color Theme.base.textSubtle ]
            (Ui.text cfg.description)
        , cfg.body
        , Ui.row [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
            [ UI.Components.btnOutline []
                { label = T.editMetadataProfileCancel i18n
                , icon = Nothing
                , onPress = ClosePanel
                }
            , if cfg.applyEnabled then
                UI.Components.btnPrimary []
                    { label = cfg.applyLabel
                    , onPress = cfg.onApply
                    }

              else
                Ui.none
            ]
        ]


fieldRow : I18n -> ProfileField -> String -> Bool -> Ui.Element Msg
fieldRow i18n field value selected =
    let
        label : { element : Ui.Element Msg, id : Ui.Input.Label }
        label =
            Ui.Input.label ("edit-meta-profile-" ++ fieldDomId field)
                [ Ui.width Ui.fill ]
                (Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
                    [ Ui.el [ Ui.Font.size Theme.font.sm, Ui.Font.weight Theme.fontWeight.bold ]
                        (Ui.text (fieldLabel i18n field))
                    , Ui.el [ Ui.Font.size Theme.font.sm, Ui.Font.color Theme.base.textSubtle ]
                        (Ui.text value)
                    ]
                )
    in
    Ui.row [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
        [ Ui.Input.checkbox []
            { onChange = \_ -> ToggleField field
            , icon = Just checkboxBox
            , checked = selected
            , label = label.id
            }
        , label.element
        ]


checkboxBox : Bool -> Ui.Element Msg
checkboxBox selected =
    let
        ( bg, content ) =
            if selected then
                ( Theme.primary.solid
                , Ui.el [ Ui.centerX, Ui.centerY, Ui.Font.color Theme.base.solidText, Ui.Font.size Theme.font.sm ]
                    (Ui.text "✓")
                )

            else
                ( Theme.base.solid, Ui.none )
    in
    Ui.el
        [ Ui.width (Ui.px 22)
        , Ui.height (Ui.px 22)
        , Ui.rounded Theme.radius.sm
        , Ui.background bg
        , Ui.border 1
        , Ui.borderColor Theme.base.accentStrong
        ]
        content


fieldDomId : ProfileField -> String
fieldDomId field =
    case field of
        PhoneField ->
            "phone"

        EmailField ->
            "email"

        NotesField ->
            "notes"

        PaymentField method ->
            (PaymentMethods.presentation method).domId


fieldLabel : I18n -> ProfileField -> String
fieldLabel i18n field =
    case field of
        PhoneField ->
            T.memberMetadataPhone i18n

        EmailField ->
            T.memberMetadataEmail i18n

        NotesField ->
            T.memberMetadataNotes i18n

        PaymentField method ->
            (PaymentMethods.presentation method).label i18n


profileValue : ProfileField -> Member.Metadata -> Maybe String
profileValue field meta =
    case field of
        PhoneField ->
            meta.phone

        EmailField ->
            meta.email

        NotesField ->
            meta.notes

        PaymentField method ->
            PaymentMethod.get method meta.payment


accessorFor : ProfileField -> (MetadataForm.Accessors -> Form.Accessor MetadataForm.State (Field.Field (Maybe String)))
accessorFor field =
    case field of
        PhoneField ->
            .phone

        EmailField ->
            .email

        NotesField ->
            .notes

        PaymentField method ->
            MetadataForm.payment method


formValue : ProfileField -> MetadataForm.Form -> String
formValue field form =
    Form.get (accessorFor field) form |> Field.toRawString
