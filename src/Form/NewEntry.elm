module Form.NewEntry exposing
    ( Accessors
    , Error(..)
    , Form
    , Output
    , State
    , form
    , initDate
    )

import Domain.Date as Date exposing (Date)
import Field exposing (Field, Validation)
import Form exposing (Accessor)


type alias Form =
    Form.Form State Accessors Error Output


type alias State =
    { description : Field String
    , amount : Field Int
    , date : Field Date
    }


type alias Accessors =
    { description : Accessor State (Field String)
    , amount : Accessor State (Field Int)
    , date : Accessor State (Field Date)
    }


type Error
    = DescriptionError Field.Error
    | AmountError Field.Error
    | DateError Field.Error


type alias Output =
    { description : String
    , amountCents : Int
    , date : Date
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



-- Date field type: parses "YYYY-MM-DD" -> Date


dateType : Field.Type Date
dateType =
    Field.customType
        { fromString = dateFromString
        , toString = dateToString
        }


dateFromString : String -> Result Field.Error Date
dateFromString =
    Field.trim
        (\s ->
            case String.split "-" s of
                [ yearStr, monthStr, dayStr ] ->
                    case ( String.toInt yearStr, String.toInt monthStr, String.toInt dayStr ) of
                        ( Just year, Just month, Just day ) ->
                            Ok { year = year, month = month, day = day }

                        _ ->
                            Err (Field.syntaxError s)

                _ ->
                    Err (Field.syntaxError s)
        )


dateToString : Date -> String
dateToString date =
    String.fromInt date.year
        ++ "-"
        ++ String.padLeft 2 '0' (String.fromInt date.month)
        ++ "-"
        ++ String.padLeft 2 '0' (String.fromInt date.day)



-- Form


form : Form
form =
    Form.new
        { init = init
        , accessors = accessors
        , validate = validate
        }


{-| Initialize the date field from a Date value.
-}
initDate : Date -> Form -> Form
initDate date =
    Form.modify .date (Field.setFromString (dateToString date))


init : State
init =
    { description = Field.empty Field.nonBlankString
    , amount = Field.empty amountType
    , date = Field.empty dateType
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
    , date =
        { get = .date
        , modify = \f state -> { state | date = f state.date }
        }
    }



-- Validate


validate : State -> Validation Error Output
validate state =
    Field.succeed Output
        |> Field.applyValidation (state.description |> Field.mapError DescriptionError)
        |> Field.applyValidation (state.amount |> Field.mapError AmountError)
        |> Field.applyValidation (state.date |> Field.mapError DateError)
