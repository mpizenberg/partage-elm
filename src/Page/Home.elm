module Page.Home exposing (Context, Model, Msg, Output(..), init, update, view)

import Domain.Currency as Currency
import Domain.Group as Group
import FeatherIcons
import File
import File.Select
import Format
import GroupExport
import Json.Decode
import Pwa
import Route exposing (Route)
import Set exposing (Set)
import Task
import Time
import Translations as T exposing (I18n)
import UI.Components
import UI.Theme as Theme
import Ui
import Ui.Events
import Ui.Font
import Ui.Input


type alias Context msg =
    { onNavigate : Route -> msg
    , onExport : Group.Id -> msg
    , notificationPermission : Maybe Pwa.NotificationPermission
    , pushActive : Bool
    , onEnableNotifications : msg
    }


type Output
    = ImportReady GroupExport.ExportData
    | JoinLink String


type Model
    = Model { importError : Maybe String, showJoinInput : Bool, joinLink : String }


type Msg
    = StartImport
    | FileSelected File.File
    | FileLoaded String
    | ShowJoinInput
    | JoinLinkChanged String
    | SubmitJoinLink


init : Model
init =
    Model { importError = Nothing, showJoinInput = False, joinLink = "" }


update : I18n -> Set Group.Id -> Msg -> Model -> ( Model, Cmd Msg, Maybe Output )
update i18n existingGroupIds msg (Model data) =
    case msg of
        StartImport ->
            ( Model { data | importError = Nothing }
            , File.Select.file [ "application/json" ] FileSelected
            , Nothing
            )

        FileSelected file ->
            ( Model data
            , Task.perform FileLoaded (File.toString file)
            , Nothing
            )

        FileLoaded jsonString ->
            case GroupExport.validateImport existingGroupIds jsonString of
                Err GroupExport.InvalidFile ->
                    ( Model { data | importError = Just (T.importErrorInvalidFile i18n) }
                    , Cmd.none
                    , Nothing
                    )

                Err GroupExport.AlreadyExists ->
                    ( Model { data | importError = Just (T.importErrorAlreadyExists i18n) }
                    , Cmd.none
                    , Nothing
                    )

                Ok exportData ->
                    ( Model { data | importError = Nothing }
                    , Cmd.none
                    , Just (ImportReady exportData)
                    )

        ShowJoinInput ->
            ( Model { data | showJoinInput = not data.showJoinInput, joinLink = "" }
            , Cmd.none
            , Nothing
            )

        JoinLinkChanged link ->
            ( Model { data | joinLink = link }
            , Cmd.none
            , Nothing
            )

        SubmitJoinLink ->
            if String.isEmpty (String.trim data.joinLink) then
                ( Model data, Cmd.none, Nothing )

            else
                ( Model { data | showJoinInput = False, joinLink = "" }
                , Cmd.none
                , Just (JoinLink (String.trim data.joinLink))
                )


view : I18n -> Context msg -> (Msg -> msg) -> Model -> List Group.Summary -> Ui.Element msg
view i18n ctx toMsg (Model data) groups =
    let
        groupActions : List (Ui.Attribute msg) -> Ui.Element msg
        groupActions attrs =
            Ui.column (Ui.spacing Theme.spacing.lg :: attrs)
                [ Ui.row [ Ui.spacing Theme.spacing.md ]
                    [ UI.Components.btnOutline []
                        { label = T.homeImportGroup i18n
                        , icon = Just (UI.Components.featherIcon 16 FeatherIcons.download)
                        , onPress = toMsg StartImport
                        }
                    , UI.Components.btnOutline []
                        { label = T.shellJoinGroup i18n
                        , icon = Just (UI.Components.featherIcon 16 FeatherIcons.userPlus)
                        , onPress = toMsg ShowJoinInput
                        }
                    ]
                , joinInput i18n toMsg data
                , UI.Components.btnPrimary []
                    { label = T.homeNewGroup i18n
                    , onPress = ctx.onNavigate Route.NewGroup
                    }
                ]
    in
    Ui.column
        [ Ui.spacing Theme.spacing.lg
        , Ui.width Ui.fill
        , Ui.height Ui.fill
        ]
        [ homeHeader i18n

        -- Notifications
        , notifSection i18n ctx

        -- Import error
        , case data.importError of
            Just error ->
                importError error

            Nothing ->
                Ui.none

        -- Groups
        , if List.isEmpty groups then
            Ui.column [ Ui.spacing Theme.spacing.lg ]
                [ Ui.el
                    [ Ui.Font.size Theme.font.md
                    , Ui.Font.color Theme.base.text
                    , Ui.centerX
                    ]
                    (Ui.text (T.homeNoGroups i18n))
                , groupActions []
                ]

          else
            Ui.column []
                [ UI.Components.sectionLabel (T.homeYourGroups i18n ++ " (" ++ String.fromInt (List.length groups) ++ ")")
                , Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
                    (List.map (groupCard i18n ctx) groups)
                , groupActions [ Ui.paddingTop Theme.spacing.lg ]
                ]

        -- Footer
        , footer i18n ctx.onNavigate
        ]



-- HOME HEADER


homeHeader : I18n -> Ui.Element msg
homeHeader i18n =
    Ui.el
        [ Ui.paddingWith { top = Theme.spacing.xl, bottom = Theme.spacing.md, left = 0, right = 0 }
        , Ui.Font.size Theme.font.xxxl
        , Ui.Font.weight Theme.fontWeight.bold
        , Ui.Font.letterSpacing Theme.letterSpacing.tight
        ]
        (Ui.text (T.shellPartage i18n))



-- NOTIFICATION SECTION


notifSection : I18n -> Context msg -> Ui.Element msg
notifSection i18n ctx =
    case ctx.notificationPermission of
        Just Pwa.Granted ->
            Ui.none

        Just Pwa.Denied ->
            Ui.none

        Just Pwa.Unsupported ->
            Ui.none

        _ ->
            Ui.column []
                [ UI.Components.sectionLabel (T.homeNotificationsTitle i18n)
                , Ui.row [ Ui.spacing Theme.spacing.md ]
                    [ Ui.el
                        [ Ui.Font.size Theme.font.sm
                        , Ui.Font.color Theme.base.textSubtle
                        , Ui.width Ui.fill
                        ]
                        (Ui.text (T.homeNotificationsHint i18n))
                    , Ui.el
                        [ Ui.Input.button ctx.onEnableNotifications
                        , Ui.width (Ui.px Theme.sizing.lg)
                        , Ui.height (Ui.px Theme.sizing.lg)
                        , Ui.rounded Theme.radius.md
                        , Ui.background Theme.primary.tint
                        , Ui.contentCenterX
                        , Ui.contentCenterY
                        , Ui.pointer
                        ]
                        (UI.Components.featherIcon (toFloat Theme.sizing.sm) FeatherIcons.bell)
                    ]
                ]



-- GROUP CARD


groupCard : I18n -> Context msg -> Group.Summary -> Ui.Element msg
groupCard i18n ctx summary =
    let
        groupRoute : Route
        groupRoute =
            Route.GroupRoute summary.id (Route.Tab Route.BalanceTab)

        metaLine : String
        metaLine =
            String.join " · "
                [ String.fromInt summary.memberCount ++ " " ++ T.homeMembers i18n
                , T.homeCreated i18n ++ " " ++ formatYear summary.createdAt
                , Currency.currencyCode summary.defaultCurrency
                ]

        balanceView : Ui.Element msg
        balanceView =
            let
                cents : Int
                cents =
                    summary.myBalanceCents

                balancePrefix : Ui.Element msg
                balancePrefix =
                    Ui.el
                        [ Ui.Font.size Theme.font.sm
                        , Ui.Font.color Theme.base.textSubtle
                        ]
                        (Ui.text (T.homeYourBalance i18n ++ " "))
            in
            if cents > 0 then
                Ui.row [ Ui.spacing Theme.spacing.sm, Ui.width Ui.shrink ]
                    [ balancePrefix
                    , Ui.el
                        [ Ui.Font.size Theme.font.sm
                        , Ui.Font.weight Theme.fontWeight.medium
                        , Ui.Font.color Theme.success.text
                        ]
                        (Ui.text ("+€" ++ Format.formatCents cents))
                    ]

            else if cents < 0 then
                Ui.row [ Ui.spacing Theme.spacing.sm, Ui.width Ui.shrink ]
                    [ balancePrefix
                    , Ui.el
                        [ Ui.Font.size Theme.font.sm
                        , Ui.Font.weight Theme.fontWeight.medium
                        , Ui.Font.color Theme.danger.text
                        ]
                        (Ui.text ("-€" ++ Format.formatCents (abs cents)))
                    ]

            else
                Ui.row [ Ui.spacing Theme.spacing.sm, Ui.width Ui.shrink ]
                    [ balancePrefix
                    , Ui.el
                        [ Ui.Font.size Theme.font.sm
                        , Ui.Font.color Theme.base.textSubtle
                        ]
                        (Ui.text (T.homeSettled i18n))
                    ]
    in
    UI.Components.card
        [ Ui.padding Theme.spacing.lg
        , Ui.pointer
        , Ui.link (Route.toPath groupRoute)
        , Ui.Events.preventDefaultOn "click"
            (Json.Decode.succeed ( ctx.onNavigate groupRoute, True ))
        ]
        [ Ui.el
            [ Ui.Font.size Theme.font.lg
            , Ui.Font.weight Theme.fontWeight.semibold
            , Ui.Font.letterSpacing Theme.letterSpacing.tight
            ]
            (Ui.text summary.name)
        , Ui.row
            [ Ui.spacing Theme.spacing.lg
            , Ui.paddingTop Theme.spacing.xs
            , Ui.Font.size Theme.font.sm
            , Ui.Font.color Theme.base.textSubtle
            ]
            [ Ui.text metaLine ]
        , Ui.el [ Ui.paddingXY 0 Theme.spacing.sm, Ui.width Ui.fill ]
            UI.Components.horizontalSeparator
        , Ui.row
            [ Ui.width Ui.fill
            , Ui.spacing Theme.spacing.sm
            ]
            [ balanceView
            , Ui.el
                [ Ui.Font.size Theme.font.sm
                , Ui.Font.color Theme.primary.text
                , Ui.pointer
                , Ui.alignRight
                , Ui.Events.custom "click"
                    (Json.Decode.succeed
                        { message = ctx.onExport summary.id
                        , stopPropagation = True
                        , preventDefault = True
                        }
                    )
                ]
                (Ui.text (T.homeExportGroup i18n))
            ]
        ]


{-| Extract the year from a timestamp in milliseconds.
-}
formatYear : Time.Posix -> String
formatYear posix =
    let
        -- Approximate: ms / (365.25 * 24 * 60 * 60 * 1000) + 1970
        year : Int
        year =
            Time.posixToMillis posix // 31557600000 + 1970
    in
    String.fromInt year



-- IMPORT ERROR


importError : String -> Ui.Element msg
importError error =
    Ui.el
        [ Ui.width Ui.fill
        , Ui.paddingTop Theme.spacing.sm
        ]
        (Ui.el
            [ Ui.Font.size Theme.font.sm
            , Ui.Font.color Theme.danger.text
            , Ui.background Theme.danger.tint
            , Ui.paddingXY Theme.spacing.lg Theme.spacing.md
            , Ui.rounded Theme.radius.md
            , Ui.border Theme.border
            , Ui.borderColor Theme.danger.accent
            , Ui.width Ui.fill
            ]
            (Ui.text error)
        )



-- JOIN INPUT


joinInput : I18n -> (Msg -> msg) -> { a | showJoinInput : Bool, joinLink : String } -> Ui.Element msg
joinInput i18n toMsg data =
    if not data.showJoinInput then
        Ui.none

    else
        Ui.row [ Ui.spacing Theme.spacing.sm ]
            [ Ui.Input.text [ Ui.width Ui.fill ]
                { onChange = toMsg << JoinLinkChanged
                , text = data.joinLink
                , placeholder = Just (T.homeJoinLinkPlaceholder i18n)
                , label = Ui.Input.labelHidden (T.shellJoinGroup i18n)
                }
            , UI.Components.btnDark [ Ui.width Ui.shrink ]
                { label = T.homeGoButton i18n, onPress = toMsg SubmitJoinLink }
            ]



-- FOOTER


footer : I18n -> (Route -> msg) -> Ui.Element msg
footer i18n onNavigate =
    Ui.column
        [ Ui.width Ui.fill
        , Ui.paddingTop Theme.spacing.xxxl
        , Ui.alignBottom
        ]
        [ UI.Components.horizontalSeparator
        , Ui.el
            [ Ui.paddingXY 0 Theme.spacing.lg
            , Ui.centerX
            , Ui.Font.size Theme.font.sm
            , Ui.Font.weight Theme.fontWeight.medium
            , Ui.Font.color Theme.base.textSubtle
            , Ui.pointer
            , Ui.link (Route.toPath Route.About)
            , Ui.Events.preventDefaultOn "click"
                (Json.Decode.succeed ( onNavigate Route.About, True ))
            ]
            (Ui.text (T.aboutTitle i18n))
        ]
