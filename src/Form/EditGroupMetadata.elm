module Form.EditGroupMetadata exposing
    ( Accessors
    , Form
    , Output
    , State
    , form
    , initFromMetadata
    )

import Domain.Group as Group
import Field exposing (Field)
import Form exposing (Accessor)
import Form.List exposing (Forms, Id)
import Validation as V


type alias Form =
    Form.Form State Accessors Field.Error Output


type alias State =
    { name : Field String
    , subtitle : Field (Maybe String)
    , description : Field (Maybe String)
    , links : Forms LinkForm
    }


type alias Accessors =
    { name : Accessor State (Field String)
    , subtitle : Accessor State (Field (Maybe String))
    , description : Accessor State (Field (Maybe String))
    , links : Accessor State (Forms LinkForm)
    , linkLabel : Id -> Accessor State (Field String)
    , linkUrl : Id -> Accessor State (Field String)
    , addLink : State -> State
    , removeLink : Id -> State -> State
    }


type alias Output =
    { name : String
    , subtitle : Maybe String
    , description : Maybe String
    , links : List Group.Link
    }


type alias LinkForm =
    Form.Form LinkState LinkAccessors Field.Error Group.Link


type alias LinkState =
    { label : Field String
    , url : Field String
    }


type alias LinkAccessors =
    { label : Accessor LinkState (Field String)
    , url : Accessor LinkState (Field String)
    }



-- Field types


optionalString : Field.Type (Maybe String)
optionalString =
    Field.optional Field.nonBlankString


urlString : Field.Type String
urlString =
    Field.customType
        { fromString =
            Field.trim
                (\s ->
                    if String.startsWith "http://" s || String.startsWith "https://" s then
                        Ok s

                    else
                        Err (Field.validationError s)
                )
        , toString = identity
        }



-- Link sub-form


linkForm : LinkForm
linkForm =
    Form.new
        { init = { label = Field.empty Field.nonBlankString, url = Field.empty urlString }
        , accessors =
            { label =
                { get = .label
                , modify = \f state -> { state | label = f state.label }
                }
            , url =
                { get = .url
                , modify = \f state -> { state | url = f state.url }
                }
            }
        , validate =
            \state ->
                Field.succeed (\label url -> { label = label, url = url })
                    |> Field.applyValidation state.label
                    |> Field.applyValidation state.url
        }


initLinkForm : Group.Link -> LinkForm
initLinkForm link =
    linkForm
        |> Form.modify .label (Field.setFromString link.label)
        |> Form.modify .url (Field.setFromString link.url)



-- Form


form : Form
form =
    Form.new
        { init = init
        , accessors = accessors
        , validate = validate
        }


initFromMetadata : { name : String, subtitle : Maybe String, description : Maybe String, links : List Group.Link } -> Form -> Form
initFromMetadata meta =
    Form.modify .name (Field.setFromString meta.name)
        >> (case meta.subtitle of
                Just s ->
                    Form.modify .subtitle (Field.setFromString s)

                Nothing ->
                    identity
           )
        >> (case meta.description of
                Just s ->
                    Form.modify .description (Field.setFromString s)

                Nothing ->
                    identity
           )
        >> Form.update
            (\_ state ->
                { state | links = Form.List.fromList (List.map initLinkForm meta.links) }
            )


init : State
init =
    { name = Field.empty Field.nonBlankString
    , subtitle = Field.empty optionalString
    , description = Field.empty optionalString
    , links = Form.List.empty
    }



-- Accessors


emptyLabelField : Field String
emptyLabelField =
    Field.empty Field.nonBlankString


emptyUrlField : Field String
emptyUrlField =
    Field.empty urlString


accessors : Accessors
accessors =
    { name =
        { get = .name
        , modify = \f state -> { state | name = f state.name }
        }
    , subtitle =
        { get = .subtitle
        , modify = \f state -> { state | subtitle = f state.subtitle }
        }
    , description =
        { get = .description
        , modify = \f state -> { state | description = f state.description }
        }
    , links =
        { get = .links
        , modify = \f state -> { state | links = f state.links }
        }
    , linkLabel =
        \id ->
            { get = .links >> Form.List.get id .label >> Maybe.withDefault emptyLabelField
            , modify = \f state -> { state | links = Form.List.modify id .label f state.links }
            }
    , linkUrl =
        \id ->
            { get = .links >> Form.List.get id .url >> Maybe.withDefault emptyUrlField
            , modify = \f state -> { state | links = Form.List.modify id .url f state.links }
            }
    , addLink =
        \state -> { state | links = Form.List.append linkForm state.links }
    , removeLink =
        \id state -> { state | links = Form.List.remove id state.links }
    }



-- Validate


validate : State -> Field.Validation Field.Error Output
validate state =
    Field.succeed Output
        |> Field.applyValidation state.name
        |> Field.applyValidation state.subtitle
        |> Field.applyValidation state.description
        |> V.apply (Form.List.validate (\_ e -> e) state.links)
