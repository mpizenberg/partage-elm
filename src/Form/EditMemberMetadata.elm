module Form.EditMemberMetadata exposing
    ( Accessors
    , Form
    , Output
    , State
    , form
    , initFromMetadata
    )

import Domain.Member as Member
import Field exposing (Field)
import Form exposing (Accessor)


type alias Form =
    Form.Form State Accessors Field.Error Output


type alias State =
    { phone : Field (Maybe String)
    , email : Field (Maybe String)
    , notes : Field (Maybe String)
    , iban : Field (Maybe String)
    , wero : Field (Maybe String)
    , lydia : Field (Maybe String)
    , revolut : Field (Maybe String)
    , paypal : Field (Maybe String)
    , venmo : Field (Maybe String)
    , btcAddress : Field (Maybe String)
    , adaAddress : Field (Maybe String)
    }


type alias Accessors =
    { phone : Accessor State (Field (Maybe String))
    , email : Accessor State (Field (Maybe String))
    , notes : Accessor State (Field (Maybe String))
    , iban : Accessor State (Field (Maybe String))
    , wero : Accessor State (Field (Maybe String))
    , lydia : Accessor State (Field (Maybe String))
    , revolut : Accessor State (Field (Maybe String))
    , paypal : Accessor State (Field (Maybe String))
    , venmo : Accessor State (Field (Maybe String))
    , btcAddress : Accessor State (Field (Maybe String))
    , adaAddress : Accessor State (Field (Maybe String))
    }


type alias Output =
    { phone : Maybe String
    , email : Maybe String
    , notes : Maybe String
    , iban : Maybe String
    , wero : Maybe String
    , lydia : Maybe String
    , revolut : Maybe String
    , paypal : Maybe String
    , venmo : Maybe String
    , btcAddress : Maybe String
    , adaAddress : Maybe String
    }


optionalString : Field.Type (Maybe String)
optionalString =
    Field.optional Field.nonBlankString


optionalEmail : Field.Type (Maybe String)
optionalEmail =
    Field.optional
        (Field.customType
            { fromString =
                Field.trim
                    (\s ->
                        case String.split "@" s of
                            [ local, domain ] ->
                                if not (String.isEmpty local) && String.contains "." domain then
                                    Ok s

                                else
                                    Err (Field.validationError s)

                            _ ->
                                Err (Field.validationError s)
                    )
            , toString = identity
            }
        )



-- Form


form : Form
form =
    Form.new
        { init = init
        , accessors = accessors
        , validate = validate
        }


initFromMetadata : Member.Metadata -> Form -> Form
initFromMetadata meta =
    let
        setField accessor maybeValue f =
            case maybeValue of
                Just v ->
                    Form.modify accessor (Field.setFromString v) f

                Nothing ->
                    f

        payment =
            Maybe.withDefault Member.emptyPaymentInfo meta.payment
    in
    setField .phone meta.phone
        >> setField .email meta.email
        >> setField .notes meta.notes
        >> setField .iban payment.iban
        >> setField .wero payment.wero
        >> setField .lydia payment.lydia
        >> setField .revolut payment.revolut
        >> setField .paypal payment.paypal
        >> setField .venmo payment.venmo
        >> setField .btcAddress payment.btcAddress
        >> setField .adaAddress payment.adaAddress


init : State
init =
    { phone = Field.empty optionalString
    , email = Field.empty optionalEmail
    , notes = Field.empty optionalString
    , iban = Field.empty optionalString
    , wero = Field.empty optionalString
    , lydia = Field.empty optionalString
    , revolut = Field.empty optionalString
    , paypal = Field.empty optionalString
    , venmo = Field.empty optionalString
    , btcAddress = Field.empty optionalString
    , adaAddress = Field.empty optionalString
    }



-- Accessors


accessors : Accessors
accessors =
    { phone =
        { get = .phone
        , modify = \f state -> { state | phone = f state.phone }
        }
    , email =
        { get = .email
        , modify = \f state -> { state | email = f state.email }
        }
    , notes =
        { get = .notes
        , modify = \f state -> { state | notes = f state.notes }
        }
    , iban =
        { get = .iban
        , modify = \f state -> { state | iban = f state.iban }
        }
    , wero =
        { get = .wero
        , modify = \f state -> { state | wero = f state.wero }
        }
    , lydia =
        { get = .lydia
        , modify = \f state -> { state | lydia = f state.lydia }
        }
    , revolut =
        { get = .revolut
        , modify = \f state -> { state | revolut = f state.revolut }
        }
    , paypal =
        { get = .paypal
        , modify = \f state -> { state | paypal = f state.paypal }
        }
    , venmo =
        { get = .venmo
        , modify = \f state -> { state | venmo = f state.venmo }
        }
    , btcAddress =
        { get = .btcAddress
        , modify = \f state -> { state | btcAddress = f state.btcAddress }
        }
    , adaAddress =
        { get = .adaAddress
        , modify = \f state -> { state | adaAddress = f state.adaAddress }
        }
    }



-- Validate


validate : State -> Field.Validation Field.Error Output
validate state =
    Field.succeed Output
        |> Field.applyValidation state.phone
        |> Field.applyValidation state.email
        |> Field.applyValidation state.notes
        |> Field.applyValidation state.iban
        |> Field.applyValidation state.wero
        |> Field.applyValidation state.lydia
        |> Field.applyValidation state.revolut
        |> Field.applyValidation state.paypal
        |> Field.applyValidation state.venmo
        |> Field.applyValidation state.btcAddress
        |> Field.applyValidation state.adaAddress
