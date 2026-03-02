module Page.AddMember exposing (Model, Msg, Output, init, update, view)

{-| Simple page for adding a virtual member to a group.
-}

import Translations as T exposing (I18n)
import UI.Theme as Theme
import Ui
import Ui.Font
import Ui.Input


{-| The validated output returned on successful submission.
-}
type alias Output =
    { name : String }


{-| Page model holding the form state.
-}
type Model
    = Model { name : String, submitted : Bool }


{-| Messages produced by user interaction on this page.
-}
type Msg
    = InputName String
    | Submit


{-| Initial model with an empty name field.
-}
init : Model
init =
    Model { name = "", submitted = False }


{-| Handle form input and submission, returning a validated Output on success.
-}
update : Msg -> Model -> ( Model, Maybe Output )
update msg (Model data) =
    case msg of
        InputName s ->
            ( Model { data | name = s }, Nothing )

        Submit ->
            let
                trimmed : String
                trimmed =
                    String.trim data.name
            in
            if String.isEmpty trimmed then
                ( Model { data | submitted = True }, Nothing )

            else
                ( Model { data | submitted = False }
                , Just { name = trimmed }
                )


{-| Render the add member form with a name input and submit button.
-}
view : I18n -> (Msg -> msg) -> Model -> Ui.Element msg
view i18n toMsg (Model data) =
    Ui.column [ Ui.spacing Theme.spacing.lg, Ui.width Ui.fill ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.xl, Ui.Font.bold ] (Ui.text (T.memberAddTitle i18n))
        , Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
            [ Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.bold ]
                (Ui.text (T.memberAddNameLabel i18n))
            , Ui.Input.text [ Ui.width Ui.fill ]
                { onChange = InputName
                , text = data.name
                , placeholder = Just (T.memberAddNamePlaceholder i18n)
                , label = Ui.Input.labelHidden (T.memberAddNameLabel i18n)
                }
            , if data.submitted && String.isEmpty (String.trim data.name) then
                Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.danger ]
                    (Ui.text (T.fieldRequired i18n))

              else
                Ui.none
            ]
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
            (Ui.text (T.memberAddSubmit i18n))
        ]
        |> Ui.map toMsg
