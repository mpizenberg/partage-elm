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

import Domain.Member as Member
import FeatherIcons
import Field
import Form
import Form.EditMemberMetadata as MetadataForm
import Translations as T exposing (I18n)
import UI.Components
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
    }


{-| Inline panel state for "Fill from saved profile" and "Save to saved profile".
-}
type Panel
    = NoPanel
    | FillPanel FieldSelections
    | SavePanel FieldSelections


type alias FieldSelections =
    { phone : Bool
    , email : Bool
    , notes : Bool
    , iban : Bool
    , wero : Bool
    , lydia : Bool
    , revolut : Bool
    , paypal : Bool
    , venmo : Bool
    , btcAddress : Bool
    , adaAddress : Bool
    }


type ProfileField
    = PhoneField
    | EmailField
    | NotesField
    | IbanField
    | WeroField
    | LydiaField
    | RevolutField
    | PaypalField
    | VenmoField
    | BtcField
    | AdaField


allFields : List ProfileField
allFields =
    [ PhoneField, EmailField, NotesField, IbanField, WeroField, LydiaField, RevolutField, PaypalField, VenmoField, BtcField, AdaField ]


{-| Messages produced by user interaction on the metadata form.
-}
type Msg
    = InputName String
    | InputPhone String
    | InputEmail String
    | InputNotes String
    | InputIban String
    | InputWero String
    | InputLydia String
    | InputRevolut String
    | InputPaypal String
    | InputVenmo String
    | InputBtc String
    | InputAda String
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

        InputIban s ->
            ( Model { data | form = Form.modify .iban (Field.setFromString s) data.form }, Nothing )

        InputWero s ->
            ( Model { data | form = Form.modify .wero (Field.setFromString s) data.form }, Nothing )

        InputLydia s ->
            ( Model { data | form = Form.modify .lydia (Field.setFromString s) data.form }, Nothing )

        InputRevolut s ->
            ( Model { data | form = Form.modify .revolut (Field.setFromString s) data.form }, Nothing )

        InputPaypal s ->
            ( Model { data | form = Form.modify .paypal (Field.setFromString s) data.form }, Nothing )

        InputVenmo s ->
            ( Model { data | form = Form.modify .venmo (Field.setFromString s) data.form }, Nothing )

        InputBtc s ->
            ( Model { data | form = Form.modify .btcAddress (Field.setFromString s) data.form }, Nothing )

        InputAda s ->
            ( Model { data | form = Form.modify .adaAddress (Field.setFromString s) data.form }, Nothing )

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
                                , metadata = metadataFromOutput output
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
    case field of
        PhoneField ->
            { sel | phone = not sel.phone }

        EmailField ->
            { sel | email = not sel.email }

        NotesField ->
            { sel | notes = not sel.notes }

        IbanField ->
            { sel | iban = not sel.iban }

        WeroField ->
            { sel | wero = not sel.wero }

        LydiaField ->
            { sel | lydia = not sel.lydia }

        RevolutField ->
            { sel | revolut = not sel.revolut }

        PaypalField ->
            { sel | paypal = not sel.paypal }

        VenmoField ->
            { sel | venmo = not sel.venmo }

        BtcField ->
            { sel | btcAddress = not sel.btcAddress }

        AdaField ->
            { sel | adaAddress = not sel.adaAddress }


getSelection : ProfileField -> FieldSelections -> Bool
getSelection field sel =
    case field of
        PhoneField ->
            sel.phone

        EmailField ->
            sel.email

        NotesField ->
            sel.notes

        IbanField ->
            sel.iban

        WeroField ->
            sel.wero

        LydiaField ->
            sel.lydia

        RevolutField ->
            sel.revolut

        PaypalField ->
            sel.paypal

        VenmoField ->
            sel.venmo

        BtcField ->
            sel.btcAddress

        AdaField ->
            sel.adaAddress


{-| For Fill: default-check fields where the form is currently empty (safe pre-fill).
Fields the user has already filled stay unchecked to avoid surprise overwrites.
-}
defaultFillSelections : MetadataForm.Form -> FieldSelections
defaultFillSelections form =
    let
        isEmpty : (MetadataForm.Accessors -> Form.Accessor MetadataForm.State (Field.Field (Maybe String))) -> Bool
        isEmpty accessor =
            Form.get accessor form |> Field.toRawString |> String.trim |> String.isEmpty
    in
    { phone = isEmpty .phone
    , email = isEmpty .email
    , notes = isEmpty .notes
    , iban = isEmpty .iban
    , wero = isEmpty .wero
    , lydia = isEmpty .lydia
    , revolut = isEmpty .revolut
    , paypal = isEmpty .paypal
    , venmo = isEmpty .venmo
    , btcAddress = isEmpty .btcAddress
    , adaAddress = isEmpty .adaAddress
    }


{-| For Save: default-check fields where the form has a non-empty value.
-}
defaultSaveSelections : MetadataForm.Form -> FieldSelections
defaultSaveSelections form =
    let
        nonEmpty : (MetadataForm.Accessors -> Form.Accessor MetadataForm.State (Field.Field (Maybe String))) -> Bool
        nonEmpty accessor =
            Form.get accessor form |> Field.toRawString |> String.trim |> String.isEmpty |> not
    in
    { phone = nonEmpty .phone
    , email = nonEmpty .email
    , notes = nonEmpty .notes
    , iban = nonEmpty .iban
    , wero = nonEmpty .wero
    , lydia = nonEmpty .lydia
    , revolut = nonEmpty .revolut
    , paypal = nonEmpty .paypal
    , venmo = nonEmpty .venmo
    , btcAddress = nonEmpty .btcAddress
    , adaAddress = nonEmpty .adaAddress
    }


metadataFromOutput : MetadataForm.Output -> Member.Metadata
metadataFromOutput output =
    let
        paymentInfo : Member.PaymentInfo
        paymentInfo =
            { iban = output.iban
            , wero = output.wero
            , lydia = output.lydia
            , revolut = output.revolut
            , paypal = output.paypal
            , venmo = output.venmo
            , btcAddress = output.btcAddress
            , adaAddress = output.adaAddress
            }
    in
    { phone = output.phone
    , email = output.email
    , notes = output.notes
    , payment =
        if paymentInfo == Member.emptyPaymentInfo then
            Nothing

        else
            Just paymentInfo
    }


{-| Build a Metadata delta containing only the selected fields from the form's
raw values (not the validated output, so we can save even if an unrelated field
is invalid).
-}
selectedMetadataFromRawForm : FieldSelections -> MetadataForm.Form -> Member.Metadata
selectedMetadataFromRawForm sel form =
    let
        pick : Bool -> ProfileField -> Maybe String
        pick flag field =
            if flag then
                let
                    raw : String
                    raw =
                        formValue field form |> String.trim
                in
                if String.isEmpty raw then
                    Nothing

                else
                    Just raw

            else
                Nothing

        paymentInfo : Member.PaymentInfo
        paymentInfo =
            { iban = pick sel.iban IbanField
            , wero = pick sel.wero WeroField
            , lydia = pick sel.lydia LydiaField
            , revolut = pick sel.revolut RevolutField
            , paypal = pick sel.paypal PaypalField
            , venmo = pick sel.venmo VenmoField
            , btcAddress = pick sel.btcAddress BtcField
            , adaAddress = pick sel.adaAddress AdaField
            }
    in
    { phone = pick sel.phone PhoneField
    , email = pick sel.email EmailField
    , notes = pick sel.notes NotesField
    , payment =
        if paymentInfo == Member.emptyPaymentInfo then
            Nothing

        else
            Just paymentInfo
    }


{-| Merge a delta into a base profile: for each field, the delta's Just wins;
otherwise the base's value is preserved. Payment is merged field-by-field.
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

        basePayment : Member.PaymentInfo
        basePayment =
            Maybe.withDefault Member.emptyPaymentInfo base.payment

        deltaPayment : Member.PaymentInfo
        deltaPayment =
            Maybe.withDefault Member.emptyPaymentInfo delta.payment

        mergedPayment : Member.PaymentInfo
        mergedPayment =
            { iban = pickFirst deltaPayment.iban basePayment.iban
            , wero = pickFirst deltaPayment.wero basePayment.wero
            , lydia = pickFirst deltaPayment.lydia basePayment.lydia
            , revolut = pickFirst deltaPayment.revolut basePayment.revolut
            , paypal = pickFirst deltaPayment.paypal basePayment.paypal
            , venmo = pickFirst deltaPayment.venmo basePayment.venmo
            , btcAddress = pickFirst deltaPayment.btcAddress basePayment.btcAddress
            , adaAddress = pickFirst deltaPayment.adaAddress basePayment.adaAddress
            }
    in
    { phone = pickFirst delta.phone base.phone
    , email = pickFirst delta.email base.email
    , notes = pickFirst delta.notes base.notes
    , payment =
        if mergedPayment == Member.emptyPaymentInfo then
            Nothing

        else
            Just mergedPayment
    }


{-| Apply selected fields from the saved profile into the form.
-}
applyFillToForm : FieldSelections -> Member.Metadata -> MetadataForm.Form -> MetadataForm.Form
applyFillToForm sel profile form =
    let
        maybeFill :
            Bool
            -> Maybe String
            -> (MetadataForm.Accessors -> Form.Accessor MetadataForm.State (Field.Field (Maybe String)))
            -> MetadataForm.Form
            -> MetadataForm.Form
        maybeFill flag maybeValue accessor f =
            case ( flag, maybeValue ) of
                ( True, Just v ) ->
                    Form.modify accessor (Field.setFromString v) f

                _ ->
                    f

        payment : Member.PaymentInfo
        payment =
            Maybe.withDefault Member.emptyPaymentInfo profile.payment
    in
    form
        |> maybeFill sel.phone profile.phone .phone
        |> maybeFill sel.email profile.email .email
        |> maybeFill sel.notes profile.notes .notes
        |> maybeFill sel.iban payment.iban .iban
        |> maybeFill sel.wero payment.wero .wero
        |> maybeFill sel.lydia payment.lydia .lydia
        |> maybeFill sel.revolut payment.revolut .revolut
        |> maybeFill sel.paypal payment.paypal .paypal
        |> maybeFill sel.venmo payment.venmo .venmo
        |> maybeFill sel.btcAddress payment.btcAddress .btcAddress
        |> maybeFill sel.adaAddress payment.adaAddress .adaAddress



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
                [ optionalField FeatherIcons.creditCard (T.memberMetadataIban i18n) (Just "FR76 1234 5678 9012 3456 7890 123") InputIban .iban
                , optionalField FeatherIcons.smartphone (T.memberMetadataWero i18n) (Just "+33 6 12 34 56 78") InputWero .wero
                , optionalField FeatherIcons.dollarSign (T.memberMetadataLydia i18n) (Just "antoniop6hcr") InputLydia .lydia
                , optionalField FeatherIcons.dollarSign (T.memberMetadataRevolut i18n) (Just "@username") InputRevolut .revolut
                , optionalField FeatherIcons.dollarSign (T.memberMetadataPaypal i18n) (Just "rogerfed") InputPaypal .paypal
                , optionalField FeatherIcons.dollarSign (T.memberMetadataVenmo i18n) (Just "@username") InputVenmo .venmo
                , optionalField FeatherIcons.key (T.memberMetadataBtc i18n) (Just "bc1q...") InputBtc .btcAddress
                , optionalField FeatherIcons.key (T.memberMetadataAda i18n) (Just "addr1...") InputAda .adaAddress
                ]
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
                                Just (fieldRow i18n field value (getSelection field sel))

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
        , applyEnabled = not (List.isEmpty rows) && anySelected sel
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
                            Just (fieldRow i18n field value (getSelection field sel))
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
        , applyEnabled = not (List.isEmpty rows) && anySelected sel
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

        IbanField ->
            "iban"

        WeroField ->
            "wero"

        LydiaField ->
            "lydia"

        RevolutField ->
            "revolut"

        PaypalField ->
            "paypal"

        VenmoField ->
            "venmo"

        BtcField ->
            "btc"

        AdaField ->
            "ada"


fieldLabel : I18n -> ProfileField -> String
fieldLabel i18n field =
    case field of
        PhoneField ->
            T.memberMetadataPhone i18n

        EmailField ->
            T.memberMetadataEmail i18n

        NotesField ->
            T.memberMetadataNotes i18n

        IbanField ->
            T.memberMetadataIban i18n

        WeroField ->
            T.memberMetadataWero i18n

        LydiaField ->
            T.memberMetadataLydia i18n

        RevolutField ->
            T.memberMetadataRevolut i18n

        PaypalField ->
            T.memberMetadataPaypal i18n

        VenmoField ->
            T.memberMetadataVenmo i18n

        BtcField ->
            T.memberMetadataBtc i18n

        AdaField ->
            T.memberMetadataAda i18n


profileValue : ProfileField -> Member.Metadata -> Maybe String
profileValue field meta =
    let
        payment : Member.PaymentInfo
        payment =
            Maybe.withDefault Member.emptyPaymentInfo meta.payment
    in
    case field of
        PhoneField ->
            meta.phone

        EmailField ->
            meta.email

        NotesField ->
            meta.notes

        IbanField ->
            payment.iban

        WeroField ->
            payment.wero

        LydiaField ->
            payment.lydia

        RevolutField ->
            payment.revolut

        PaypalField ->
            payment.paypal

        VenmoField ->
            payment.venmo

        BtcField ->
            payment.btcAddress

        AdaField ->
            payment.adaAddress


formValue : ProfileField -> MetadataForm.Form -> String
formValue field form =
    let
        get : (MetadataForm.Accessors -> Form.Accessor MetadataForm.State (Field.Field (Maybe String))) -> String
        get accessor =
            Form.get accessor form |> Field.toRawString
    in
    case field of
        PhoneField ->
            get .phone

        EmailField ->
            get .email

        NotesField ->
            get .notes

        IbanField ->
            get .iban

        WeroField ->
            get .wero

        LydiaField ->
            get .lydia

        RevolutField ->
            get .revolut

        PaypalField ->
            get .paypal

        VenmoField ->
            get .venmo

        BtcField ->
            get .btcAddress

        AdaField ->
            get .adaAddress


anySelected : FieldSelections -> Bool
anySelected sel =
    sel.phone
        || sel.email
        || sel.notes
        || sel.iban
        || sel.wero
        || sel.lydia
        || sel.revolut
        || sel.paypal
        || sel.venmo
        || sel.btcAddress
        || sel.adaAddress
