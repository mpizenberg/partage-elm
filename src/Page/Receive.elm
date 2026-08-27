module Page.Receive exposing
    ( Applied
    , Effect(..)
    , Model
    , Msg
    , applied
    , applyFailed
    , init
    , payloadArrived
    , update
    , view
    )

{-| The destination side of a domain migration: take delivery of the profile
handoff, over `postMessage` or as a pasted code, and apply it. An installed
iOS app shares storage with no browser tab, so there the code is the only way in.
-}

import Infra.Handoff as Handoff
import Translations as T exposing (I18n)
import UI.Components
import UI.Theme as Theme
import Ui
import Ui.Font
import Ui.Input


type Model
    = Model Data


type alias Data =
    { pasted : String
    , applying : Bool
    , error : Maybe ReceiveError
    , result : Maybe Applied
    }


type ReceiveError
    = InvalidCode
    | ApplyFailed String


{-| What a successful application did, for the closing screen.
-}
type alias Applied =
    { adopted : Bool
    , added : Int
    , skipped : Int
    }


type Msg
    = InputCode String
    | SubmitCode


{-| `Apply` hands a decoded payload to the host, which owns the merge and the
persistence; the outcome comes back through `applied` / `applyFailed`.
-}
type Effect
    = NoEffect
    | Apply Handoff.Payload


init : Model
init =
    Model
        { pasted = ""
        , applying = False
        , error = Nothing
        , result = Nothing
        }


update : Msg -> Model -> ( Model, Effect )
update msg (Model data) =
    case msg of
        InputCode text ->
            ( Model { data | pasted = text, error = Nothing }, NoEffect )

        SubmitCode ->
            if canApply data then
                case Handoff.fromString data.pasted of
                    Ok payload ->
                        ( Model { data | applying = True, error = Nothing }, Apply payload )

                    Err _ ->
                        ( Model
                            { data
                                | error =
                                    if String.isEmpty (String.trim data.pasted) then
                                        Nothing

                                    else
                                        Just InvalidCode
                            }
                        , NoEffect
                        )

            else
                ( Model data, NoEffect )


{-| A payload arrived over `postMessage` (already origin-checked by the JS
side against the configured source). A malformed one is ignored: the paste
box remains and nothing was promised.
-}
payloadArrived : String -> Model -> ( Model, Effect )
payloadArrived raw ((Model data) as model) =
    if canApply data then
        case Handoff.fromString raw of
            Ok payload ->
                ( Model { data | applying = True, error = Nothing }, Apply payload )

            Err _ ->
                ( model, NoEffect )

    else
        ( model, NoEffect )


canApply : Data -> Bool
canApply data =
    not data.applying && data.result == Nothing


applied : Applied -> Model -> Model
applied result (Model data) =
    Model { data | applying = False, result = Just result, error = Nothing }


applyFailed : String -> Model -> Model
applyFailed reason (Model data) =
    Model { data | applying = False, error = Just (ApplyFailed reason) }



-- VIEW


view :
    I18n
    ->
        { sourceName : Maybe String
        , requiresInstall : Bool
        , inHostAppWindow : Bool
        , destinationName : String
        , onGoHome : msg
        }
    -> (Msg -> msg)
    -> Model
    -> Ui.Element msg
view i18n ctx toMsg (Model data) =
    case ctx.sourceName of
        Nothing ->
            hint (T.receiveNotExpecting i18n)

        Just sourceName ->
            case data.result of
                Just result ->
                    viewApplied i18n ctx result

                Nothing ->
                    viewReceiving i18n sourceName ctx.requiresInstall data
                        |> Ui.map toMsg


viewReceiving : I18n -> String -> Bool -> Data -> Ui.Element Msg
viewReceiving i18n sourceName requiresInstall data =
    Ui.column [ Ui.spacing Theme.spacing.lg, Ui.width Ui.fill ]
        (hint (T.receiveIntro sourceName i18n)
            :: (if requiresInstall then
                    -- An iOS browser tab is the wrong destination: whatever it
                    -- stores never reaches the installed app's isolated storage.
                    [ UI.Components.card [ Ui.padding Theme.spacing.lg ]
                        [ Ui.el [ Ui.Font.size Theme.font.sm ] (Ui.text (T.receiveIosInstallFirst i18n)) ]
                    ]

                else
                    [ -- One line, not a box: the code is a single unbroken 2 KB
                      -- word, which a text area would size itself to and spill
                      -- across the layout.
                      Ui.Input.text
                        [ Ui.width Ui.fill
                        , Ui.padding Theme.spacing.sm
                        , Ui.rounded Theme.radius.sm
                        , Ui.border Theme.border
                        , Ui.borderColor Theme.base.accent

                        -- Below 16px, iOS Safari zooms into a focused field.
                        , Ui.Font.size Theme.font.md
                        , Ui.Font.family [ Ui.Font.monospace ]
                        ]
                        { onChange = InputCode
                        , text = data.pasted
                        , placeholder = Just (T.receiveCodePlaceholder i18n)
                        , label = Ui.Input.labelHidden (T.receiveCodePlaceholder i18n)
                        }
                    , case data.error of
                        Just InvalidCode ->
                            errorText (T.receiveCodeInvalid i18n)

                        Just (ApplyFailed reason) ->
                            errorText reason

                        Nothing ->
                            Ui.none
                    , UI.Components.btnPrimary [ Ui.width Ui.shrink ]
                        { label =
                            if data.applying then
                                T.receiveApplying i18n

                            else
                                T.receiveSubmit i18n
                        , onPress = SubmitCode
                        }
                    ]
               )
        )


viewApplied :
    I18n
    -> { c | inHostAppWindow : Bool, destinationName : String, onGoHome : msg }
    -> Applied
    -> Ui.Element msg
viewApplied i18n ctx result =
    Ui.column [ Ui.spacing Theme.spacing.lg, Ui.width Ui.fill ]
        [ UI.Components.card [ Ui.padding Theme.spacing.lg ]
            [ Ui.el [ Ui.Font.size Theme.font.md ]
                (Ui.text (T.receiveDone (String.fromInt result.added) i18n))
            , if result.skipped > 0 then
                Ui.el [ Ui.Font.size Theme.font.sm, Ui.Font.color Theme.base.textSubtle, Ui.paddingTop Theme.spacing.xs ]
                    (Ui.text (T.receiveSkipped (String.fromInt result.skipped) i18n))

              else
                Ui.none
            , if result.adopted then
                Ui.none

              else
                Ui.el [ Ui.Font.size Theme.font.sm, Ui.Font.color Theme.base.textSubtle, Ui.paddingTop Theme.spacing.xs ]
                    (Ui.text (T.receiveKeptIdentity i18n))
            ]
        , if ctx.inHostAppWindow then
            -- The move landed, but in a window belonging to the app being left
            -- behind: nothing here can install the destination.
            hint (T.receiveInstallHere ctx.destinationName i18n)

          else
            Ui.none
        , hint (T.receiveNextSteps i18n)
        , UI.Components.btnPrimary [ Ui.width Ui.shrink ]
            { label = T.receiveOpenGroups i18n
            , onPress = ctx.onGoHome
            }
        ]


errorText : String -> Ui.Element msg
errorText text =
    Ui.el [ Ui.Font.size Theme.font.sm, Ui.Font.color Theme.danger.text ] (Ui.text text)


hint : String -> Ui.Element msg
hint text =
    Ui.el
        [ Ui.Font.size Theme.font.sm
        , Ui.Font.color Theme.base.textSubtle
        , Ui.width Ui.fill
        ]
        (Ui.text text)
