module Form.NewGroup exposing
    ( Accessors
    , Error(..)
    , Form
    , Output
    , State
    , VMAccessors
    , VMState
    , VirtualMemberError(..)
    , VirtualMemberForm
    , form
    )

import Domain.Currency as Currency exposing (Currency(..))
import Field exposing (Field, Validation)
import Form exposing (Accessor)
import Form.List exposing (Forms, Id)
import Validation as V


{-| The new group form type combining state, accessors, errors, and output.
-}
type alias Form =
    Form.Form State Accessors Error Output


{-| Form state for creating a new group (name, creator, currency, virtual members).
-}
type alias State =
    { name : Field String
    , creatorName : Field String
    , currency : Field Currency
    , virtualMembers : Forms VirtualMemberForm
    }


{-| Accessors for reading and modifying each new group form field.
-}
type alias Accessors =
    { name : Accessor State (Field String)
    , creatorName : Accessor State (Field String)
    , currency : Accessor State (Field Currency)
    , virtualMembers : Accessor State (Forms VirtualMemberForm)
    , virtualMemberName : Id -> Accessor State (Field String)
    , addVirtualMember : State -> State
    , removeVirtualMember : Id -> State -> State
    }


{-| Validation errors for the new group form.
-}
type Error
    = NameError Field.Error
    | CreatorNameError Field.Error
    | CurrencyError Field.Error
    | VirtualMemberError Id VirtualMemberError


{-| Validated output of the new group form.
-}
type alias Output =
    { name : String
    , creatorName : String
    , currency : Currency
    , virtualMembers : List String
    }



-- Virtual member sub-form


type alias VirtualMemberForm =
    Form.Form VMState VMAccessors VirtualMemberError String


type alias VMState =
    { name : Field String }


type alias VMAccessors =
    { name : Accessor VMState (Field String) }


{-| Validation errors for a virtual member sub-form.
-}
type VirtualMemberError
    = VMNameError Field.Error


virtualMemberForm : VirtualMemberForm
virtualMemberForm =
    Form.new
        { init = { name = Field.empty Field.nonBlankString }
        , accessors =
            { name =
                { get = .name
                , modify = \f state -> { state | name = f state.name }
                }
            }
        , validate =
            \state ->
                Field.validate identity (Field.mapError VMNameError state.name)
        }



-- Currency field type


currencyFromString : String -> Result Field.Error Currency
currencyFromString =
    Field.trim
        (\s ->
            case List.filter (\c -> String.toLower (Currency.currencyCode c) == s) Currency.allCurrencies of
                c :: _ ->
                    Ok c

                [] ->
                    Err (Field.validationError s)
        )


currencyToString : Currency -> String
currencyToString c =
    String.toLower (Currency.currencyCode c)


currencyType : Field.Type Currency
currencyType =
    Field.customType
        { fromString = currencyFromString
        , toString = currencyToString
        }



-- Form


{-| The new group form definition.
-}
form : Form
form =
    Form.new
        { init = init
        , accessors = accessors
        , validate = validate
        }


init : State
init =
    { name = Field.empty Field.nonBlankString
    , creatorName = Field.empty Field.nonBlankString
    , currency = Field.fromString currencyType "eur"
    , virtualMembers = Form.List.empty
    }



-- Accessors


emptyVMName : Field String
emptyVMName =
    Field.empty Field.nonBlankString


accessors : Accessors
accessors =
    { name =
        { get = .name
        , modify = \f state -> { state | name = f state.name }
        }
    , creatorName =
        { get = .creatorName
        , modify = \f state -> { state | creatorName = f state.creatorName }
        }
    , currency =
        { get = .currency
        , modify = \f state -> { state | currency = f state.currency }
        }
    , virtualMembers =
        { get = .virtualMembers
        , modify = \f state -> { state | virtualMembers = f state.virtualMembers }
        }
    , virtualMemberName =
        \id ->
            { get = .virtualMembers >> Form.List.get id .name >> Maybe.withDefault emptyVMName
            , modify = \f state -> { state | virtualMembers = Form.List.modify id .name f state.virtualMembers }
            }
    , addVirtualMember =
        \state -> { state | virtualMembers = Form.List.append virtualMemberForm state.virtualMembers }
    , removeVirtualMember =
        \id state -> { state | virtualMembers = Form.List.remove id state.virtualMembers }
    }



-- Validate


validate : State -> Validation Error Output
validate state =
    V.map4
        Output
        (Field.validate identity (Field.mapError NameError state.name))
        (Field.validate identity (Field.mapError CreatorNameError state.creatorName))
        (Field.validate identity (Field.mapError CurrencyError state.currency))
        (Form.List.validate VirtualMemberError state.virtualMembers)
