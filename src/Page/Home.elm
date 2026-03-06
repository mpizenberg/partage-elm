module Page.Home exposing (Context, Model, Msg, Output(..), init, update, view)

import Domain.Group as Group
import File
import File.Select
import GroupExport
import Json.Decode
import Pwa
import Route exposing (Route)
import Set exposing (Set)
import Storage exposing (GroupSummary)
import Task
import Translations as T exposing (I18n)
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


view : I18n -> Context msg -> (Msg -> msg) -> Model -> List GroupSummary -> Ui.Element msg
view i18n ctx toMsg (Model data) groups =
    Ui.column [ Ui.spacing Theme.spacing.md, Ui.width Ui.fill ]
        (List.concat
            [ [ Ui.el [ Ui.Font.size Theme.fontSize.xl, Ui.Font.bold ] (Ui.text (T.homeYourGroups i18n)) ]
            , notificationBanner i18n ctx
            , case data.importError of
                Just error ->
                    [ Ui.el
                        [ Ui.Font.size Theme.fontSize.sm
                        , Ui.Font.color Theme.danger
                        , Ui.padding Theme.spacing.sm
                        ]
                        (Ui.text error)
                    ]

                Nothing ->
                    []
            , if List.isEmpty groups then
                [ Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ]
                    (Ui.text (T.homeNoGroups i18n))
                ]

              else
                List.map (groupCard i18n ctx) groups
            , [ Ui.row [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
                    [ newGroupButton i18n ctx.onNavigate
                    , importButton i18n toMsg
                    , joinButton i18n toMsg
                    ]
              ]
            , joinInput i18n toMsg data
            , [ aboutLink i18n ctx.onNavigate ]
            ]
        )


notificationBanner : I18n -> Context msg -> List (Ui.Element msg)
notificationBanner i18n ctx =
    case ctx.notificationPermission of
        Just Pwa.Unsupported ->
            []

        Just Pwa.Denied ->
            [ Ui.el
                [ Ui.Font.size Theme.fontSize.sm
                , Ui.Font.color Theme.neutral500
                , Ui.padding Theme.spacing.sm
                ]
                (Ui.text (T.notificationsDenied i18n))
            ]

        Just Pwa.Granted ->
            if ctx.pushActive then
                [ Ui.el
                    [ Ui.Font.size Theme.fontSize.sm
                    , Ui.Font.color Theme.success
                    , Ui.padding Theme.spacing.sm
                    ]
                    (Ui.text (T.notificationsEnabled i18n))
                ]

            else
                []

        _ ->
            [ Ui.el
                [ Ui.paddingXY Theme.spacing.md Theme.spacing.sm
                , Ui.rounded Theme.rounding.sm
                , Ui.background Theme.primaryLight
                , Ui.Font.color Theme.primary
                , Ui.Font.size Theme.fontSize.sm
                , Ui.Font.bold
                , Ui.pointer
                , Ui.Events.onClick ctx.onEnableNotifications
                ]
                (Ui.text (T.notificationsEnable i18n))
            ]


groupCard : I18n -> Context msg -> GroupSummary -> Ui.Element msg
groupCard i18n ctx summary =
    let
        groupRoute : Route
        groupRoute =
            Route.GroupRoute summary.id (Route.Tab Route.BalanceTab)
    in
    Ui.row
        [ Ui.width Ui.fill
        , Ui.padding Theme.spacing.md
        , Ui.rounded Theme.rounding.md
        , Ui.border Theme.borderWidth.sm
        , Ui.borderColor Theme.neutral200
        , Ui.spacing Theme.spacing.sm
        ]
        [ Ui.el
            [ Ui.Font.bold
            , Ui.Font.size Theme.fontSize.lg
            , Ui.width Ui.fill
            , Ui.pointer
            , Ui.link (Route.toPath groupRoute)
            , Ui.Events.preventDefaultOn "click"
                (Json.Decode.succeed ( ctx.onNavigate groupRoute, True ))
            ]
            (Ui.text summary.name)
        , Ui.el
            [ Ui.Font.size Theme.fontSize.sm
            , Ui.Font.color Theme.primary
            , Ui.pointer
            , Ui.Events.onClick (ctx.onExport summary.id)
            ]
            (Ui.text (T.homeExportGroup i18n))
        ]


newGroupButton : I18n -> (Route -> msg) -> Ui.Element msg
newGroupButton i18n onNavigate =
    let
        route : Route
        route =
            Route.NewGroup
    in
    Ui.el
        [ Ui.width Ui.fill
        , Ui.padding Theme.spacing.md
        , Ui.rounded Theme.rounding.md
        , Ui.background Theme.primary
        , Ui.Font.color Theme.white
        , Ui.Font.center
        , Ui.Font.bold
        , Ui.pointer
        , Ui.link (Route.toPath route)
        , Ui.Events.preventDefaultOn "click"
            (Json.Decode.succeed ( onNavigate route, True ))
        ]
        (Ui.text (T.homeNewGroup i18n))


importButton : I18n -> (Msg -> msg) -> Ui.Element msg
importButton i18n toMsg =
    Ui.el
        [ Ui.width Ui.fill
        , Ui.padding Theme.spacing.md
        , Ui.rounded Theme.rounding.md
        , Ui.border Theme.borderWidth.sm
        , Ui.borderColor Theme.primary
        , Ui.Font.color Theme.primary
        , Ui.Font.center
        , Ui.Font.bold
        , Ui.pointer
        , Ui.Events.onClick (toMsg StartImport)
        ]
        (Ui.text (T.homeImportGroup i18n))


joinButton : I18n -> (Msg -> msg) -> Ui.Element msg
joinButton i18n toMsg =
    Ui.el
        [ Ui.width Ui.fill
        , Ui.padding Theme.spacing.md
        , Ui.rounded Theme.rounding.md
        , Ui.border Theme.borderWidth.sm
        , Ui.borderColor Theme.primary
        , Ui.Font.color Theme.primary
        , Ui.Font.center
        , Ui.Font.bold
        , Ui.pointer
        , Ui.Events.onClick (toMsg ShowJoinInput)
        ]
        (Ui.text (T.shellJoinGroup i18n))


aboutLink : I18n -> (Route -> msg) -> Ui.Element msg
aboutLink i18n onNavigate =
    Ui.el
        [ Ui.width Ui.fill
        , Ui.Font.center
        , Ui.Font.size Theme.fontSize.sm
        , Ui.Font.color Theme.neutral500
        , Ui.pointer
        , Ui.paddingXY 0 Theme.spacing.md
        , Ui.link (Route.toPath Route.About)
        , Ui.Events.preventDefaultOn "click"
            (Json.Decode.succeed ( onNavigate Route.About, True ))
        ]
        (Ui.text (T.aboutTitle i18n))


joinInput : I18n -> (Msg -> msg) -> { a | showJoinInput : Bool, joinLink : String } -> List (Ui.Element msg)
joinInput i18n toMsg data =
    if not data.showJoinInput then
        []

    else
        [ Ui.row [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
            [ Ui.Input.text [ Ui.width Ui.fill ]
                { onChange = toMsg << JoinLinkChanged
                , text = data.joinLink
                , placeholder = Just (T.homeJoinLinkPlaceholder i18n)
                , label = Ui.Input.labelHidden (T.shellJoinGroup i18n)
                }
            , Ui.el
                [ Ui.Input.button (toMsg SubmitJoinLink)
                , Ui.padding Theme.spacing.md
                , Ui.rounded Theme.rounding.md
                , Ui.background Theme.primary
                , Ui.Font.color Theme.white
                , Ui.Font.bold
                , Ui.pointer
                ]
                (Ui.text "Go")
            ]
        ]
