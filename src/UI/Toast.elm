module UI.Toast exposing (Model, Toast, ToastId, ToastLevel(..), dismiss, entryActionMessage, init, push, view)

{-| Toast notification system.

Toasts are ephemeral messages displayed as a fixed overlay at the top of the viewport.
They auto-dismiss after a configurable duration using `Process.sleep`.

Animation is fully stateless — CSS `@keyframes` slide-in, no subscriptions needed.

-}

import Domain.Event as Event
import Html
import Html.Attributes
import Process
import Task
import Translations as T exposing (I18n)
import UI.Theme as Theme
import Ui
import Ui.Font


type alias ToastId =
    Int


type ToastLevel
    = Success
    | Error


type alias Toast =
    { id : ToastId
    , message : String
    , level : ToastLevel
    }


type alias Model =
    { toasts : List Toast
    , nextId : ToastId
    }


init : Model
init =
    { toasts = []
    , nextId = 0
    }


{-| Push a new toast and get back the updated model plus a dismiss command.

    ( toastModel, cmd ) =
        Toast.push DismissToast Toast.Success "Saved!" model.toastModel

-}
push : (ToastId -> msg) -> ToastLevel -> String -> Model -> ( Model, Cmd msg )
push dismissMsg level message model =
    let
        durationMs : Float
        durationMs =
            case level of
                Error ->
                    6000

                _ ->
                    4000

        toast : Toast
        toast =
            { id = model.nextId, message = message, level = level }

        cmd : Cmd msg
        cmd =
            Process.sleep durationMs
                |> Task.perform (\() -> dismissMsg model.nextId)
    in
    ( { toasts = model.toasts ++ [ toast ]
      , nextId = model.nextId + 1
      }
    , cmd
    )


{-| Return a success toast message for entry delete/restore actions, if applicable.
-}
entryActionMessage : I18n -> Event.Payload -> Maybe String
entryActionMessage i18n payload =
    case payload of
        Event.EntryDeleted _ ->
            Just (T.toastEntryDeleted i18n)

        Event.EntryUndeleted _ ->
            Just (T.toastEntryRestored i18n)

        _ ->
            Nothing


{-| Remove a toast by id (called when the auto-dismiss fires).
-}
dismiss : ToastId -> Model -> Model
dismiss toastId model =
    { model | toasts = List.filter (\t -> t.id /= toastId) model.toasts }


{-| Render the toast overlay. Returns `Ui.none` when there are no toasts.
-}
view : Model -> Ui.Element msg
view model =
    if List.isEmpty model.toasts then
        Ui.none

    else
        Ui.column
            [ Ui.centerX
            , Ui.paddingXY Theme.spacing.md Theme.spacing.sm
            , Ui.spacing Theme.spacing.sm
            , Ui.width Ui.fill
            , Ui.widthMax 400
            , Ui.htmlAttribute (Html.Attributes.style "pointer-events" "none")
            , Ui.htmlAttribute (Html.Attributes.style "z-index" "9999")
            ]
            (keyframesStyle :: List.map viewToast model.toasts)


keyframesStyle : Ui.Element msg
keyframesStyle =
    Ui.html
        (Html.node "style"
            []
            [ Html.text "@keyframes toast-slide-in { from { opacity: 0; transform: translateY(-20px); } to { opacity: 1; transform: translateY(0); } }" ]
        )


viewToast : Toast -> Ui.Element msg
viewToast toast =
    let
        ( bgColor, fgColor ) =
            case toast.level of
                Success ->
                    ( Theme.success.tint, Theme.success.text )

                Error ->
                    ( Theme.danger.tint, Theme.danger.text )
    in
    Ui.el
        [ Ui.width Ui.fill
        , Ui.padding Theme.spacing.md
        , Ui.rounded Theme.radius.md
        , Ui.background bgColor
        , Ui.Font.color fgColor
        , Ui.Font.size Theme.font.sm
        , Ui.htmlAttribute (Html.Attributes.style "animation" "toast-slide-in 0.3s ease-out")
        , Ui.htmlAttribute (Html.Attributes.style "box-shadow" "0 2px 8px rgba(0,0,0,0.15)")
        , Ui.htmlAttribute (Html.Attributes.style "pointer-events" "auto")
        ]
        (Ui.text toast.message)
