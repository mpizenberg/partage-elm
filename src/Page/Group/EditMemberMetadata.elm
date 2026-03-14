module Page.Group.EditMemberMetadata exposing (Model, Msg, Output, init, update, view)

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
type alias Output =
    { memberId : Member.Id
    , oldName : String
    , newName : String
    , metadata : Member.Metadata
    }


{-| Page model holding form state for editing member metadata.
-}
type Model
    = Model ModelData


type alias ModelData =
    { memberId : Member.Id
    , originalName : String
    , form : MetadataForm.Form
    , submitted : Bool
    }


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


{-| Initialize the model from an existing member's ID, name, and metadata.
-}
init : Member.Id -> String -> Member.Metadata -> Model
init memberId name meta =
    Model
        { memberId = memberId
        , originalName = name
        , form = MetadataForm.form |> MetadataForm.initFromMember name meta
        , submitted = False
        }


{-| Handle form input and submission, returning validated Output on success.
-}
update : Msg -> Model -> ( Model, Maybe Output )
update msg (Model data) =
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

                        hasPayment : Bool
                        hasPayment =
                            paymentInfo /= Member.emptyPaymentInfo

                        metadata : Member.Metadata
                        metadata =
                            { phone = output.phone
                            , email = output.email
                            , notes = output.notes
                            , payment =
                                if hasPayment then
                                    Just paymentInfo

                                else
                                    Nothing
                            }
                    in
                    ( Model data
                    , Just
                        { memberId = data.memberId
                        , oldName = data.originalName
                        , newName = output.name
                        , metadata = metadata
                        }
                    )

                Nothing ->
                    ( Model { data | submitted = True }, Nothing )


{-| Render the member metadata editing form.
-}
view : I18n -> (Msg -> msg) -> Model -> Ui.Element msg
view i18n toMsg (Model data) =
    Ui.column [ Ui.spacing Theme.spacing.xl ]
        [ Ui.column [ Ui.spacing Theme.spacing.lg ]
            [ nameField i18n data
            , textField FeatherIcons.phone (T.memberMetadataPhone i18n) (Just "+33 6 12 34 56 78") InputPhone .phone data.form
            , emailField i18n data
            , textField FeatherIcons.fileText (T.memberMetadataNotes i18n) (Just (T.memberMetadataNotesPlaceholder i18n)) InputNotes .notes data.form
            ]
        , Ui.column []
            [ UI.Components.sectionLabel (T.memberMetadataPayment i18n)
            , Ui.column [ Ui.spacing Theme.spacing.lg ]
                [ textField FeatherIcons.creditCard (T.memberMetadataIban i18n) (Just "FR76 1234 5678 9012 3456 7890 123") InputIban .iban data.form
                , textField FeatherIcons.smartphone (T.memberMetadataWero i18n) (Just "+33 6 12 34 56 78") InputWero .wero data.form
                , textField FeatherIcons.dollarSign (T.memberMetadataLydia i18n) (Just "antoniop6hcr") InputLydia .lydia data.form
                , textField FeatherIcons.dollarSign (T.memberMetadataRevolut i18n) (Just "@username") InputRevolut .revolut data.form
                , textField FeatherIcons.dollarSign (T.memberMetadataPaypal i18n) (Just "rogerfed") InputPaypal .paypal data.form
                , textField FeatherIcons.dollarSign (T.memberMetadataVenmo i18n) (Just "@username") InputVenmo .venmo data.form
                , textField FeatherIcons.key (T.memberMetadataBtc i18n) (Just "bc1q...") InputBtc .btcAddress data.form
                , textField FeatherIcons.key (T.memberMetadataAda i18n) (Just "addr1...") InputAda .adaAddress data.form
                ]
            ]
        , UI.Components.btnPrimary []
            { label = T.memberMetadataSave i18n
            , onPress = Submit
            }
        ]
        |> Ui.map toMsg


textField : FeatherIcons.Icon -> String -> Maybe String -> (String -> Msg) -> (MetadataForm.Accessors -> Form.Accessor MetadataForm.State (Field.Field (Maybe String))) -> MetadataForm.Form -> Ui.Element Msg
textField icon label placeholder onChange accessor formData =
    Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
        [ Ui.row [ Ui.spacing Theme.spacing.sm, Ui.contentCenterY, Ui.width Ui.shrink ]
            [ Ui.el [ Ui.Font.color Theme.base.textSubtle ] (UI.Components.featherIcon 16 icon)
            , UI.Components.formLabel label False
            ]
        , Ui.Input.text
            [ Ui.width Ui.fill
            , Ui.padding Theme.spacing.sm
            , Ui.rounded Theme.radius.sm
            , Ui.border Theme.border
            , Ui.borderColor Theme.base.accent
            ]
            { onChange = onChange
            , text = Form.get accessor formData |> Field.toRawString
            , placeholder = placeholder
            , label = Ui.Input.labelHidden label
            }
        ]


nameField : I18n -> ModelData -> Ui.Element Msg
nameField i18n data =
    let
        field : Field.Field String
        field =
            Form.get .name data.form
    in
    Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
        [ Ui.row [ Ui.spacing Theme.spacing.sm, Ui.contentCenterY, Ui.width Ui.shrink ]
            [ Ui.el [ Ui.Font.color Theme.base.textSubtle ] (UI.Components.featherIcon 16 FeatherIcons.user)
            , UI.Components.formLabel (T.memberRenameLabel i18n) True
            ]
        , Ui.Input.text
            [ Ui.width Ui.fill
            , Ui.padding Theme.spacing.sm
            , Ui.rounded Theme.radius.sm
            , Ui.border Theme.border
            , Ui.borderColor Theme.base.accent
            ]
            { onChange = InputName
            , text = Field.toRawString field
            , placeholder = Nothing
            , label = Ui.Input.labelHidden (T.memberRenameLabel i18n)
            }
        , if Field.isInvalid field && (data.submitted || Field.isDirty field) then
            Ui.el [ Ui.Font.size Theme.font.sm, Ui.Font.color Theme.danger.text ]
                (Ui.text (T.fieldRequired i18n))

          else
            Ui.none
        ]


emailField : I18n -> ModelData -> Ui.Element Msg
emailField i18n data =
    let
        field : Field.Field (Maybe String)
        field =
            Form.get .email data.form
    in
    Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
        [ Ui.row [ Ui.spacing Theme.spacing.sm, Ui.contentCenterY, Ui.width Ui.shrink ]
            [ Ui.el [ Ui.Font.color Theme.base.textSubtle ] (UI.Components.featherIcon 16 FeatherIcons.atSign)
            , UI.Components.formLabel (T.memberMetadataEmail i18n) False
            ]
        , Ui.Input.text
            [ Ui.width Ui.fill
            , Ui.padding Theme.spacing.sm
            , Ui.rounded Theme.radius.sm
            , Ui.border Theme.border
            , Ui.borderColor Theme.base.accent
            ]
            { onChange = InputEmail
            , text = Field.toRawString field
            , placeholder = Nothing
            , label = Ui.Input.labelHidden (T.memberMetadataEmail i18n)
            }
        , if Field.isInvalid field && (data.submitted || Field.isDirty field) then
            Ui.el [ Ui.Font.size Theme.font.sm, Ui.Font.color Theme.danger.text ]
                (Ui.text (T.fieldInvalidEmail i18n))

          else
            Ui.none
        ]
