module Form.EditMemberMetadata exposing
    ( Accessors
    , Form
    , Output
    , State
    , form
    , initFromMember
    , payment
    )

import Domain.Member as Member
import Domain.PaymentMethod as PaymentMethod exposing (Method)
import Field exposing (Field)
import Form exposing (Accessor)
import List.Extra
import UI.PaymentMethods as PaymentMethods
import Validation as V


{-| The member metadata editing form type.
-}
type alias Form =
    Form.Form State Accessors Field.Error Output


{-| Form state for all member metadata fields (contact info and payment methods).
Payment handles are keyed by method rather than named, so a new method needs no
field here; only the ones the form has touched are present.
-}
type alias State =
    { name : Field String
    , phone : Field (Maybe String)
    , email : Field (Maybe String)
    , notes : Field (Maybe String)
    , payment : List ( Method, Field (Maybe String) )
    }


{-| Accessors for reading and modifying each contact field. Payment handles have
no fixed field to name, so they are reached through `payment` instead.
-}
type alias Accessors =
    { name : Accessor State (Field String)
    , phone : Accessor State (Field (Maybe String))
    , email : Accessor State (Field (Maybe String))
    , notes : Accessor State (Field (Maybe String))
    }


{-| Validated output of the member metadata form.
-}
type alias Output =
    { name : String
    , phone : Maybe String
    , email : Maybe String
    , notes : Maybe String
    , payment : List ( Method, Maybe String )
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


{-| The member metadata editing form definition.
-}
form : Form
form =
    Form.new
        { init = init
        , accessors = accessors
        , validate = validate
        }


{-| Initialize the form fields from an existing member's name and metadata.
-}
initFromMember : String -> Member.Metadata -> Form -> Form
initFromMember name meta =
    let
        setField : (Accessors -> Accessor State (Field (Maybe String))) -> Maybe String -> Form -> Form
        setField accessor maybeValue f =
            case maybeValue of
                Just v ->
                    Form.modify accessor (Field.setFromString v) f

                Nothing ->
                    f

        setHandle : Method -> Form -> Form
        setHandle method =
            setField (payment method) (PaymentMethod.get method meta.payment)
    in
    Form.modify .name (Field.setFromString name)
        >> setField .phone meta.phone
        >> setField .email meta.email
        >> setField .notes meta.notes
        >> (\f -> List.foldl setHandle f PaymentMethods.all)


init : State
init =
    { name = Field.empty Field.nonBlankString
    , phone = Field.empty optionalString
    , email = Field.empty optionalEmail
    , notes = Field.empty optionalString
    , payment = []
    }



-- Accessors


accessors : Accessors
accessors =
    { name =
        { get = .name
        , modify = \f state -> { state | name = f state.name }
        }
    , phone =
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
    }


{-| The accessor for one payment handle. Shaped like the fields of `Accessors`
so it can be passed to `Form.get`/`Form.modify` the same way, but built from the
method instead of read out of the record.
-}
payment : Method -> Accessors -> Accessor State (Field (Maybe String))
payment method _ =
    { get = \state -> handleField method state.payment
    , modify = \f state -> { state | payment = updateHandle method f state.payment }
    }


handleField : Method -> List ( Method, Field (Maybe String) ) -> Field (Maybe String)
handleField method handles =
    List.Extra.find (\( m, _ ) -> m == method) handles
        |> Maybe.map Tuple.second
        |> Maybe.withDefault (Field.empty optionalString)


updateHandle :
    Method
    -> (Field (Maybe String) -> Field (Maybe String))
    -> List ( Method, Field (Maybe String) )
    -> List ( Method, Field (Maybe String) )
updateHandle method f handles =
    if List.any (\( m, _ ) -> m == method) handles then
        List.map
            (\(( m, field ) as entry) ->
                if m == method then
                    ( m, f field )

                else
                    entry
            )
            handles

    else
        ( method, f (Field.empty optionalString) ) :: handles



-- Validate


validate : State -> Field.Validation Field.Error Output
validate state =
    Field.succeed Output
        |> Field.applyValidation state.name
        |> Field.applyValidation state.phone
        |> Field.applyValidation state.email
        |> Field.applyValidation state.notes
        |> V.apply (validateHandles state.payment)


validateHandles : List ( Method, Field (Maybe String) ) -> Field.Validation Field.Error (List ( Method, Maybe String ))
validateHandles =
    List.foldr
        (\( method, field ) acc -> V.map2 (\value rest -> ( method, value ) :: rest) (Field.toValidation field) acc)
        (Field.succeed [])
