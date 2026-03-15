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
    let
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
    in
    Ui.column [ Ui.spacing Theme.spacing.xl ]
        [ Ui.column [ Ui.spacing Theme.spacing.lg ]
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
        |> Ui.map toMsg
