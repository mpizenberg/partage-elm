module Form.NewEntry exposing
    ( Accessors
    , Error(..)
    , Form
    , Output
    , State
    , form
    )

import Field exposing (Field, Validation)
import Form exposing (Accessor)


type alias Form =
    Form.Form State Accessors Error Output


type alias State =
    { description : Field String
    , amount : Field Int
    }


type alias Accessors =
    { description : Accessor State (Field String)
    , amount : Accessor State (Field Int)
    }


type Error
    = DescriptionError Field.Error
    | AmountError Field.Error


type alias Output =
    { description : String
    , amountCents : Int
    }



-- Amount field type: parses "12.50" -> 1250 (cents)


amountType : Field.Type Int
amountType =
    Field.customType
        { fromString = amountFromString
        , toString = amountToString
        }


amountFromString : String -> Result Field.Error Int
amountFromString =
    Field.trim
        (\s ->
            case String.toFloat s of
                Just f ->
                    let
                        cents =
                            round (f * 100)
                    in
                    if cents > 0 then
                        Ok cents

                    else
                        Err (Field.customError "Amount must be positive.")

                Nothing ->
                    Err (Field.syntaxError s)
        )


amountToString : Int -> String
amountToString cents =
    let
        whole =
            cents // 100

        remainder =
            modBy 100 (abs cents)
    in
    String.fromInt whole ++ "." ++ String.padLeft 2 '0' (String.fromInt remainder)



-- Form


form : Form
form =
    Form.new
        { init = init
        , accessors = accessors
        , validate = validate
        }


init : State
init =
    { description = Field.empty Field.nonBlankString
    , amount = Field.empty amountType
    }



-- Accessors


accessors : Accessors
accessors =
    { description =
        { get = .description
        , modify = \f state -> { state | description = f state.description }
        }
    , amount =
        { get = .amount
        , modify = \f state -> { state | amount = f state.amount }
        }
    }



-- Validate


validate : State -> Validation Error Output
validate state =
    Field.succeed Output
        |> Field.applyValidation (state.description |> Field.mapError DescriptionError)
        |> Field.applyValidation (state.amount |> Field.mapError AmountError)
