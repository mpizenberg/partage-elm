module Page.ErrorLog exposing (ViewConfig, view)

{-| Error log page — displays in-memory error entries and a debug report copy button.
-}

import Domain.Currency as Currency
import Domain.Group as Group
import ErrorLog
import FeatherIcons
import Html
import Html.Attributes
import Json.Encode as Encode
import Time
import Translations as T exposing (I18n)
import UI.Components
import UI.Theme as Theme
import Ui
import Ui.Font


type alias ViewConfig =
    { i18n : I18n
    , errorLog : ErrorLog.Model
    , groups : List Group.Summary
    , currentTime : Time.Posix
    , appState : String
    }


view : ViewConfig -> Ui.Element msg
view config =
    Ui.column [ Ui.spacing Theme.spacing.xl, Ui.width Ui.fill, Ui.paddingXY 0 Theme.spacing.md ]
        [ debugReportSection config
        , entriesSection config
        ]



-- DEBUG REPORT


debugReportSection : ViewConfig -> Ui.Element msg
debugReportSection config =
    let
        reportJson : String
        reportJson =
            Encode.encode 2 (encodeDebugReport config)
    in
    Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
        [ copyReportButton reportJson (T.errorLogCopyReport config.i18n)
        , Ui.el
            [ Ui.Font.size Theme.font.xs
            , Ui.Font.color Theme.base.textSubtle
            ]
            (Ui.text (T.errorLogPrivacyNotice config.i18n))
        ]


copyReportButton : String -> String -> Ui.Element msg
copyReportButton copyText label =
    Ui.row
        (Ui.width Ui.fill
            :: Ui.inFront
                (Ui.el [ Ui.width Ui.fill, Ui.height Ui.fill ]
                    (Ui.html
                        (Html.node "copy-button"
                            [ Html.Attributes.attribute "data-copy" copyText
                            , Html.Attributes.style "display" "block"
                            , Html.Attributes.style "width" "100%"
                            , Html.Attributes.style "height" "100%"
                            , Html.Attributes.style "cursor" "pointer"
                            ]
                            []
                        )
                    )
                )
            :: UI.Components.btnOutlineAttrs
        )
        [ UI.Components.featherIcon 16 FeatherIcons.copy
        , Ui.text label
        ]


encodeDebugReport : ViewConfig -> Encode.Value
encodeDebugReport config =
    Encode.object
        [ ( "exportedAt", Encode.int (Time.posixToMillis config.currentTime) )
        , ( "errors", ErrorLog.toJsonValue config.errorLog )
        , ( "groups", Encode.list encodeGroupSummary config.groups )
        , ( "language", Encode.string (T.languageToString (T.currentLanguage config.i18n)) )
        , ( "appState", Encode.string config.appState )
        ]


encodeGroupSummary : Group.Summary -> Encode.Value
encodeGroupSummary summary =
    Encode.object
        [ ( "id", Encode.string summary.id )
        , ( "name", Encode.string summary.name )
        , ( "memberCount", Encode.int summary.memberCount )
        , ( "currency", Encode.string (Currency.currencyCode summary.defaultCurrency) )
        ]



-- ERROR ENTRIES


entriesSection : ViewConfig -> Ui.Element msg
entriesSection config =
    if List.isEmpty config.errorLog.entries then
        Ui.el
            [ Ui.Font.size Theme.font.sm
            , Ui.Font.color Theme.base.textSubtle
            , Ui.centerX
            , Ui.padding Theme.spacing.xl
            ]
            (Ui.text (T.errorLogEmpty config.i18n))

    else
        Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
            (List.map viewEntry config.errorLog.entries)


viewEntry : ErrorLog.Entry -> Ui.Element msg
viewEntry entry =
    UI.Components.card [ Ui.padding Theme.spacing.md ]
        [ Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
            [ Ui.row [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill, Ui.contentCenterY ]
                [ severityDot entry.severity
                , sourceBadge entry.source
                , Ui.el
                    [ Ui.Font.size Theme.font.xs
                    , Ui.Font.color Theme.base.textSubtle
                    , Ui.alignRight
                    ]
                    (Ui.text (formatTimestamp entry.timestamp))
                ]
            , Ui.row [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
                [ Ui.el
                    [ Ui.Font.size Theme.font.sm
                    , Ui.Font.color Theme.base.text
                    , Ui.width Ui.fill
                    ]
                    (Ui.text entry.message)
                , if entry.count > 1 then
                    Ui.el
                        [ Ui.Font.size Theme.font.xs
                        , Ui.Font.color Theme.base.textSubtle
                        , Ui.alignRight
                        , Ui.width Ui.shrink
                        ]
                        (Ui.text ("×" ++ String.fromInt entry.count))

                  else
                    Ui.none
                ]
            ]
        ]


severityDot : ErrorLog.Severity -> Ui.Element msg
severityDot severity =
    let
        color : Ui.Color
        color =
            case severity of
                ErrorLog.Err ->
                    Theme.danger.solid
    in
    Ui.el
        [ Ui.width (Ui.px 8)
        , Ui.height (Ui.px 8)
        , Ui.rounded 4
        , Ui.background color
        , Ui.width Ui.shrink
        ]
        Ui.none


sourceBadge : ErrorLog.Source -> Ui.Element msg
sourceBadge source =
    Ui.el
        [ Ui.Font.size Theme.font.xs
        , Ui.Font.color Theme.primary.text
        , Ui.Font.weight Theme.fontWeight.semibold
        ]
        (Ui.text (ErrorLog.sourceToString source))


formatTimestamp : Time.Posix -> String
formatTimestamp posix =
    let
        ms : Int
        ms =
            Time.posixToMillis posix

        -- Simple HH:MM:SS format in UTC
        totalSeconds : Int
        totalSeconds =
            ms // 1000

        hours : Int
        hours =
            modBy 24 (totalSeconds // 3600)

        minutes : Int
        minutes =
            modBy 60 (totalSeconds // 60)

        seconds : Int
        seconds =
            modBy 60 totalSeconds

        pad : Int -> String
        pad n =
            if n < 10 then
                "0" ++ String.fromInt n

            else
                String.fromInt n
    in
    pad hours ++ ":" ++ pad minutes ++ ":" ++ pad seconds
