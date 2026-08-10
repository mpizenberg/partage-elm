module Page.JoinGroup exposing (Model, Msg, Output(..), PreviewData, acceptanceFailed, defaultAction, error, getPreview, init, showPreview, update, view, viewPreview)

{-| Join group page shown when opening an invite link.
Displays a group preview with options to claim a virtual member or join as new.
-}

import Dict
import Domain.Event as Event
import Domain.Group as Group
import Domain.GroupState exposing (GroupState)
import Domain.Member as Member
import Set exposing (Set)
import Translations as T exposing (I18n, Language)
import UI.Components
import UI.Theme as Theme
import Ui
import Ui.Font
import Ui.Input
import WebCrypto.Symmetric as Symmetric


type Model
    = FetchingGroup
    | ShowingPreview PreviewData
    | Accepting PreviewData
    | Error String


type alias PreviewData =
    { groupId : Group.Id
    , groupName : String
    , groupState : GroupState
    , groupKey : Symmetric.Key
    , events : List Event.Envelope
    , unpushedIds : Set Event.Id
    , syncCursor : Maybe Group.SyncCursor
    , selectedAction : Member.JoinAction
    , newMemberName : String
    , historyWarning : Bool
    }


type Msg
    = SelectMember Member.Id
    | SelectJoinAsNew
    | InputNewMemberName String
    | ConfirmJoin


type Output
    = JoinConfirmed PreviewData


init : Model
init =
    FetchingGroup


showPreview : PreviewData -> Model
showPreview =
    ShowingPreview


error : String -> Model
error =
    Error


acceptanceFailed : Model -> Model
acceptanceFailed model =
    case model of
        Accepting preview ->
            ShowingPreview preview

        _ ->
            model


getPreview : Model -> Maybe PreviewData
getPreview model =
    case model of
        ShowingPreview preview ->
            Just preview

        Accepting preview ->
            Just preview

        _ ->
            Nothing


{-| Pick the default join action: select the first virtual member if any, otherwise join as new.
-}
defaultAction : GroupState -> Member.JoinAction
defaultAction groupState =
    Dict.values groupState.members
        |> List.filter (\m -> m.memberType == Member.Virtual && not m.isRetired)
        |> List.sortBy (\m -> String.toLower m.name)
        |> List.head
        |> Maybe.map (\m -> Member.ClaimMember m.rootId)
        |> Maybe.withDefault Member.JoinAsNewMember


update : Msg -> Model -> ( Model, Maybe Output )
update msg model =
    case ( msg, model ) of
        ( SelectMember memberId, ShowingPreview preview ) ->
            ( ShowingPreview { preview | selectedAction = Member.ClaimMember memberId }
            , Nothing
            )

        ( SelectJoinAsNew, ShowingPreview preview ) ->
            ( ShowingPreview { preview | selectedAction = Member.JoinAsNewMember }
            , Nothing
            )

        ( InputNewMemberName name, ShowingPreview preview ) ->
            ( ShowingPreview { preview | newMemberName = name }
            , Nothing
            )

        ( ConfirmJoin, ShowingPreview preview ) ->
            case preview.selectedAction of
                Member.JoinAsNewMember ->
                    let
                        trimmed : String
                        trimmed =
                            String.trim preview.newMemberName

                        nameExists : Bool
                        nameExists =
                            Dict.values preview.groupState.members
                                |> List.filter (not << .isRetired)
                                |> List.any (\m -> String.toLower m.name == String.toLower trimmed)
                    in
                    if String.isEmpty trimmed || nameExists then
                        ( model, Nothing )

                    else
                        ( Accepting preview
                        , Just (JoinConfirmed { preview | newMemberName = trimmed })
                        )

                Member.ClaimMember _ ->
                    ( Accepting preview
                    , Just (JoinConfirmed preview)
                    )

        _ ->
            ( model, Nothing )


view : I18n -> { toMsg : Msg -> msg, onSwitchLanguage : Language -> msg, onRetry : msg, onGoHome : msg } -> Model -> Ui.Element msg
view i18n config model =
    let
        content : List (Ui.Element Msg)
        content =
            case model of
                FetchingGroup ->
                    [ Ui.el
                        [ Ui.centerX
                        , Ui.Font.size Theme.font.md
                        , Ui.Font.color Theme.base.textSubtle
                        ]
                        (Ui.text (T.joinGroupFetching i18n))
                    ]

                Error errorMsg ->
                    [ UI.Components.card [ Ui.padding Theme.spacing.lg ]
                        [ Ui.column [ Ui.spacing Theme.spacing.sm ]
                            [ Ui.el
                                [ Ui.centerX
                                , Ui.Font.size Theme.font.md
                                , Ui.Font.color Theme.danger.text
                                , Ui.Font.weight Theme.fontWeight.semibold
                                ]
                                (Ui.text (T.joinGroupError i18n))
                            , Ui.el
                                [ Ui.centerX
                                , Ui.Font.size Theme.font.sm
                                , Ui.Font.color Theme.base.textSubtle
                                ]
                                (Ui.text errorMsg)
                            ]
                        ]
                    ]

                ShowingPreview preview ->
                    viewPreview i18n preview

                Accepting preview ->
                    viewPreview i18n preview

        errorActions : List (Ui.Element msg)
        errorActions =
            case model of
                Error _ ->
                    [ Ui.row [ Ui.centerX, Ui.spacing Theme.spacing.sm ]
                        [ UI.Components.btnPrimary [ Ui.width Ui.shrink ]
                            { label = T.joinGroupRetry i18n, onPress = config.onRetry }
                        , UI.Components.btnOutline [ Ui.width Ui.shrink ]
                            { label = T.joinGroupGoHome i18n, icon = Nothing, onPress = config.onGoHome }
                        ]
                    ]

                _ ->
                    []
    in
    Ui.column [ Ui.spacing Theme.spacing.xl ]
        (List.map (Ui.map config.toMsg) content
            ++ errorActions
            ++ [ Ui.el [ Ui.centerX ]
                    (UI.Components.languageSelector config.onSwitchLanguage (T.currentLanguage i18n))
               ]
        )


{-| The member picker (claim an existing member or join as new). Also used by
the group page to let a non-member re-join an imported group.
-}
viewPreview : I18n -> PreviewData -> List (Ui.Element Msg)
viewPreview i18n preview =
    let
        virtualMembers : List Member.State
        virtualMembers =
            Dict.values preview.groupState.members
                |> List.filter (\m -> m.memberType == Member.Virtual && not m.isRetired)
                |> List.sortBy (\m -> String.toLower m.name)

        realMembers : List Member.State
        realMembers =
            Dict.values preview.groupState.members
                |> List.filter (\m -> m.memberType == Member.Real && not m.isRetired)
                |> List.sortBy (\m -> String.toLower m.name)

        isJoinAsNew : Bool
        isJoinAsNew =
            case preview.selectedAction of
                Member.JoinAsNewMember ->
                    True

                _ ->
                    False

        existingNames : List String
        existingNames =
            Dict.values preview.groupState.members
                |> List.filter (not << .isRetired)
                |> List.map (\m -> String.toLower m.name)

        trimmedName : String
        trimmedName =
            String.trim preview.newMemberName

        isDuplicateName : Bool
        isDuplicateName =
            List.member (String.toLower trimmedName) existingNames

        canConfirm : Bool
        canConfirm =
            case preview.selectedAction of
                Member.ClaimMember _ ->
                    True

                Member.JoinAsNewMember ->
                    not (String.isEmpty trimmedName) && not isDuplicateName
    in
    [ Ui.el
        [ Ui.centerX
        , Ui.Font.size Theme.font.xl
        , Ui.Font.weight Theme.fontWeight.bold
        , Ui.Font.letterSpacing Theme.letterSpacing.tight
        ]
        (Ui.text preview.groupName)
    , if preview.historyWarning then
        UI.Components.card [ Ui.padding Theme.spacing.md ]
            [ Ui.el
                [ Ui.Font.size Theme.font.sm
                , Ui.Font.color Theme.danger.text
                ]
                (Ui.text (T.joinGroupHistoryWarning i18n))
            ]

      else
        Ui.none
    , if not (List.isEmpty virtualMembers) then
        Ui.column []
            [ UI.Components.sectionLabel (T.joinGroupClaimMember i18n)
            , Ui.row [ Ui.wrap, Ui.spacing Theme.spacing.sm ]
                (List.map (viewMemberToggle preview.selectedAction) virtualMembers)
            ]

      else
        Ui.none
    , if not (List.isEmpty realMembers) then
        Ui.column []
            [ UI.Components.sectionLabel (T.joinGroupRecoverMember i18n)
            , Ui.row [ Ui.wrap, Ui.spacing Theme.spacing.sm ]
                (List.map (viewMemberToggle preview.selectedAction) realMembers)
            ]

      else
        Ui.none
    , Ui.column []
        [ UI.Components.sectionLabel (T.joinGroupJoinAsNew i18n)
        , UI.Components.chip
            { label = T.joinGroupJoinAsNew i18n
            , selected = isJoinAsNew
            , onPress = SelectJoinAsNew
            }
        , if isJoinAsNew then
            Ui.column [ Ui.paddingTop Theme.spacing.md, Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
                [ UI.Components.formLabel (T.joinGroupNameLabel i18n) True
                , Ui.Input.text
                    [ Ui.width Ui.fill
                    , Ui.padding Theme.spacing.sm
                    , Ui.rounded Theme.radius.sm
                    , Ui.border Theme.border
                    , Ui.borderColor Theme.base.accent
                    ]
                    { onChange = InputNewMemberName
                    , text = preview.newMemberName
                    , placeholder = Just (T.joinGroupNamePlaceholder i18n)
                    , label = Ui.Input.labelHidden (T.joinGroupNameLabel i18n)
                    }
                , if isDuplicateName && not (String.isEmpty trimmedName) then
                    Ui.el [ Ui.Font.size Theme.font.sm, Ui.Font.color Theme.danger.text ]
                        (Ui.text (T.joinGroupNameTaken i18n))

                  else
                    Ui.none
                ]

          else
            Ui.none
        ]
    , if canConfirm then
        let
            confirmLabel : String
            confirmLabel =
                case preview.selectedAction of
                    Member.ClaimMember memberId ->
                        let
                            member : Maybe Member.State
                            member =
                                Dict.get memberId preview.groupState.members
                        in
                        case Maybe.map (\m -> ( m.name, m.memberType )) member of
                            Just ( name, Member.Virtual ) ->
                                T.joinGroupConfirmClaim name i18n

                            Just ( name, _ ) ->
                                T.joinGroupConfirmRecover name i18n

                            Nothing ->
                                T.joinGroupConfirm i18n

                    Member.JoinAsNewMember ->
                        T.joinGroupConfirmNew trimmedName i18n
        in
        UI.Components.btnPrimary []
            { label = confirmLabel
            , onPress = ConfirmJoin
            }

      else
        Ui.none
    ]


viewMemberToggle : Member.JoinAction -> Member.State -> Ui.Element Msg
viewMemberToggle selectedAction member =
    let
        isSelected : Bool
        isSelected =
            case selectedAction of
                Member.ClaimMember id ->
                    id == member.rootId

                _ ->
                    False
    in
    UI.Components.toggleMemberBtn
        { name = member.name
        , initials = String.left 2 (String.toUpper member.name)
        , selected = isSelected
        , onPress = SelectMember member.rootId
        }
