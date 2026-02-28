module Page.EditMemberMetadata exposing (Model, Msg, Output, init, update, view)

{-| Page for editing a member's contact info and payment methods.
-}

import Domain.Member as Member
import Field
import Form
import Form.EditMemberMetadata as MetadataForm
import Translations as T exposing (I18n)
import UI.Theme as Theme
import Ui
import Ui.Font
import Ui.Input


type alias Output =
    { memberId : Member.Id
    , metadata : Member.Metadata
    }


type Model
    = Model ModelData


type alias ModelData =
    { memberId : Member.Id
    , form : MetadataForm.Form
    , submitted : Bool
    }


type Msg
    = InputPhone String
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


init : Member.Id -> Member.Metadata -> Model
init memberId meta =
    Model
        { memberId = memberId
        , form = MetadataForm.form |> MetadataForm.initFromMetadata meta
        , submitted = False
        }


update : Msg -> Model -> ( Model, Maybe Output )
update msg (Model data) =
    case msg of
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

                        hasPayment =
                            paymentInfo /= Member.emptyPaymentInfo

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
                    , Just { memberId = data.memberId, metadata = metadata }
                    )

                Nothing ->
                    ( Model { data | submitted = True }, Nothing )


view : I18n -> (Msg -> msg) -> Model -> Ui.Element msg
view i18n toMsg (Model data) =
    Ui.column [ Ui.spacing Theme.spacing.lg, Ui.width Ui.fill ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.xl, Ui.Font.bold ] (Ui.text (T.memberMetadataTitle i18n))
        , textField (T.memberMetadataPhone i18n) InputPhone .phone data.form
        , emailField i18n data
        , textField (T.memberMetadataNotes i18n) InputNotes .notes data.form
        , Ui.el [ Ui.Font.size Theme.fontSize.lg, Ui.Font.bold ] (Ui.text (T.memberMetadataPayment i18n))
        , textField (T.memberMetadataIban i18n) InputIban .iban data.form
        , textField (T.memberMetadataWero i18n) InputWero .wero data.form
        , textField (T.memberMetadataLydia i18n) InputLydia .lydia data.form
        , textField (T.memberMetadataRevolut i18n) InputRevolut .revolut data.form
        , textField (T.memberMetadataPaypal i18n) InputPaypal .paypal data.form
        , textField (T.memberMetadataVenmo i18n) InputVenmo .venmo data.form
        , textField (T.memberMetadataBtc i18n) InputBtc .btcAddress data.form
        , textField (T.memberMetadataAda i18n) InputAda .adaAddress data.form
        , Ui.el
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
            (Ui.text (T.memberMetadataSave i18n))
        ]
        |> Ui.map toMsg


emailField : I18n -> ModelData -> Ui.Element Msg
emailField i18n data =
    let
        label =
            T.memberMetadataEmail i18n

        field =
            Form.get .email data.form
    in
    Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.bold ] (Ui.text label)
        , Ui.Input.text [ Ui.width Ui.fill ]
            { onChange = InputEmail
            , text = Field.toRawString field
            , placeholder = Nothing
            , label = Ui.Input.labelHidden label
            }
        , if Field.isInvalid field && (data.submitted || Field.isDirty field) then
            Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.danger ]
                (Ui.text (T.fieldInvalidEmail i18n))

          else
            Ui.none
        ]


textField : String -> (String -> Msg) -> (MetadataForm.Accessors -> Form.Accessor MetadataForm.State (Field.Field (Maybe String))) -> MetadataForm.Form -> Ui.Element Msg
textField label onChange accessor formData =
    Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.bold ] (Ui.text label)
        , Ui.Input.text [ Ui.width Ui.fill ]
            { onChange = onChange
            , text = Form.get accessor formData |> Field.toRawString
            , placeholder = Nothing
            , label = Ui.Input.labelHidden label
            }
        ]
