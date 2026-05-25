module Form.NewEntry exposing
    ( Accessors
    , Error
    , Form
    , Output
    , State
    , form
    , initAmount
    , initDate
    , initDescription
    , normalizeAmountInput
    )

import Domain.Date exposing (Date)
import Field exposing (Field, Validation)
import Form exposing (Accessor)
import Format
import Translations exposing (Language)


{-| The new entry form type combining state, accessors, errors, and output.
-}
type alias Form =
    Form.Form State Accessors Error Output


{-| Form state holding the description, amount, and date fields.
-}
type alias State =
    { description : Field String
    , amount : Field Int
    , date : Field Date
    }


{-| Accessors for reading and modifying each form field.
-}
type alias Accessors =
    { description : Accessor State (Field String)
    , amount : Accessor State (Field Int)
    , date : Accessor State (Field Date)
    }


{-| Validation errors for the new entry form.
-}
type Error
    = DescriptionError
    | AmountError
    | DateError


{-| Validated output of the new entry form.
-}
type alias Output =
    { description : String
    , amountCents : Int
    , date : Date
    }



-- Amount field type: parses "12.50" or "12,50" -> 1250 (cents).
-- Accepts both decimal separators and ignores spaces (regular, NBSP, NNBSP)
-- so French-formatted input like "1 234,56" round-trips. The active Language
-- is baked into the type so `setFromValue` / `toString` produce the right
-- separator without any caller having to remember to pass it.


amountType : Language -> Field.Type Int
amountType lang =
    Field.customType
        { fromString = amountFromString
        , toString = Format.formatCentsForInput lang
        }


amountFromString : String -> Result Field.Error Int
amountFromString =
    Field.trim
        (\s ->
            case String.toFloat (normalizeAmountInput s) of
                Just f ->
                    let
                        cents : Int
                        cents =
                            round (f * 100)
                    in
                    if cents > 0 then
                        Ok cents

                    else
                        Err (Field.validationError s)

                Nothing ->
                    Err (Field.syntaxError s)
        )


{-| Strip locale-specific decimations so `String.toFloat` can parse the result.
Accepts comma as decimal separator and removes spaces / NBSP / NNBSP that French
grouping uses as thousands separators.
-}
normalizeAmountInput : String -> String
normalizeAmountInput str =
    String.replace "," "." str
        |> String.replace " " ""
        |> String.replace "\u{00A0}" ""
        |> String.replace "\u{202F}" ""



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


{-| The new entry form definition. Carries the active language so the amount
field formats values with the locale's decimal separator.
-}
form : Language -> Form
form lang =
    Form.new
        { init = init lang
        , accessors = accessors
        , validate = validate
        }


{-| Initialize the date field from a Date value.
-}
initDate : Date -> Form -> Form
initDate date =
    Form.modify .date (Field.setFromString (dateToString date))


{-| Initialize the description field.
-}
initDescription : String -> Form -> Form
initDescription desc =
    Form.modify .description (Field.setFromString desc)


{-| Initialize the amount field from cents. The raw string is produced by the
field type's `toString`, so the locale is whatever was passed to `form`.
-}
initAmount : Int -> Form -> Form
initAmount cents =
    Form.modify .amount (Field.setFromValue cents)


init : Language -> State
init lang =
    { description = Field.empty Field.nonBlankString
    , amount = Field.empty (amountType lang)
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
        |> Field.applyValidation (state.description |> Field.mapError (\_ -> DescriptionError))
        |> Field.applyValidation (state.amount |> Field.mapError (\_ -> AmountError))
        |> Field.applyValidation (state.date |> Field.mapError (\_ -> DateError))
