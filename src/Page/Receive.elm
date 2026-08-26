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
handoff — over `postMessage` from the source app's window, or as a pasted
code — and apply it. The paste path is the primary one on iOS: an installed
Home Screen app has storage isolated from every browser tab, so the handoff
must be brought _inside_ the installed app by hand.
-}

import Html.Attributes
import Infra.Handoff as Handoff
import Pwa
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
    , invalid : Bool
    , applying : Bool
    , error : Maybe String
    , result : Maybe Applied
    }


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
        , invalid = False
        , applying = False
        , error = Nothing
        , result = Nothing
        }


update : Msg -> Model -> ( Model, Effect )
update msg (Model data) =
    case msg of
        InputCode text ->
            ( Model { data | pasted = text, invalid = False }, NoEffect )

        SubmitCode ->
            case Handoff.fromString data.pasted of
                Ok payload ->
                    ( Model { data | invalid = False, applying = True }, Apply payload )

                Err _ ->
                    ( Model { data | invalid = not (String.isEmpty (String.trim data.pasted)) }, NoEffect )


{-| A payload arrived over `postMessage` (already origin-checked by the JS
side against the configured source). A malformed one is ignored: the paste
box remains and nothing was promised.
-}
payloadArrived : String -> Model -> ( Model, Effect )
payloadArrived raw ((Model data) as model) =
    case ( data.result, Handoff.fromString raw ) of
        ( Nothing, Ok payload ) ->
            ( Model { data | applying = True }, Apply payload )

        _ ->
            ( model, NoEffect )


applied : Applied -> Model -> Model
applied result (Model data) =
    Model { data | applying = False, result = Just result, error = Nothing }


applyFailed : String -> Model -> Model
applyFailed reason (Model data) =
    Model { data | applying = False, error = Just reason }



-- VIEW


view :
    I18n
    ->
        { sourceName : Maybe String
        , installHint : Pwa.InstallHint
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
                    viewApplied i18n ctx.onGoHome result

                Nothing ->
                    viewReceiving i18n sourceName ctx.installHint data
                        |> Ui.map toMsg


viewReceiving : I18n -> String -> Pwa.InstallHint -> Data -> Ui.Element Msg
viewReceiving i18n sourceName installHint data =
    Ui.column [ Ui.spacing Theme.spacing.lg, Ui.width Ui.fill ]
        [ hint (T.receiveIntro sourceName i18n)
        , case installHint of
            -- An iOS Safari tab is the wrong destination: whatever it
            -- receives never reaches the installed app's isolated storage.
            Pwa.ManualIosSafari ->
                UI.Components.card [ Ui.padding Theme.spacing.lg ]
                    [ Ui.el [ Ui.Font.size Theme.font.sm ] (Ui.text (T.receiveIosInstallFirst i18n)) ]

            _ ->
                Ui.none
        , Ui.Input.multiline
            [ Ui.width Ui.fill
            , Ui.height (Ui.px 120)
            , Ui.padding Theme.spacing.sm
            , Ui.rounded Theme.radius.sm
            , Ui.border Theme.border
            , Ui.borderColor Theme.base.accent
            , Ui.Font.size Theme.font.sm
            , Ui.Font.family [ Ui.Font.monospace ]

            -- The code is one unbroken 2 KB word: without a break opportunity
            -- the box sizes itself to the whole string and drags the page
            -- sideways with it. `anywhere` is the value that also shrinks the
            -- intrinsic width the grid measures.
            , Ui.htmlAttribute (Html.Attributes.style "overflow-wrap" "anywhere")
            , Ui.htmlAttribute (Html.Attributes.style "overflow-y" "auto")
            ]
            { onChange = InputCode
            , text = data.pasted
            , placeholder = Just (T.receiveCodePlaceholder i18n)
            , label = Ui.Input.labelHidden (T.receiveCodePlaceholder i18n)
            , spellcheck = False
            }
        , if data.invalid then
            errorText (T.receiveCodeInvalid i18n)

          else
            Ui.none
        , case data.error of
            Just reason ->
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


viewApplied : I18n -> msg -> Applied -> Ui.Element msg
viewApplied i18n onGoHome result =
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
        , hint (T.receiveNextSteps i18n)
        , UI.Components.btnPrimary [ Ui.width Ui.shrink ]
            { label = T.receiveOpenGroups i18n
            , onPress = onGoHome
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
