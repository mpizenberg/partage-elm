module Page.JoinGroup exposing (JoinAction(..), Model, Msg, Output(..), PreviewData, defaultAction, error, getPreview, init, showPreview, update, view)

{-| Join group page shown when opening an invite link.
Displays a group preview with options to claim a virtual member or join as new.
-}

import Dict
import Domain.Event as Event
import Domain.GroupState exposing (GroupState)
import Domain.Member as Member
import Translations as T exposing (I18n)
import UI.Components
import UI.Theme as Theme
import Ui
import Ui.Font
import Ui.Input


type Model
    = FetchingGroup
    | ShowingPreview PreviewData
    | Error String


type alias PreviewData =
    { groupName : String
    , groupState : GroupState
    , events : List Event.Envelope
    , syncCursor : String
    , selectedAction : JoinAction
    , newMemberName : String
    }


type JoinAction
    = ClaimMember Member.Id
    | JoinAsNewMember


type Msg
    = SelectMember Member.Id
    | SelectJoinAsNew
    | InputNewMemberName String
    | ConfirmJoin


type Output
    = JoinConfirmed { selectedAction : JoinAction, newMemberName : String }


init : Model
init =
    FetchingGroup


showPreview : PreviewData -> Model
showPreview =
    ShowingPreview


error : String -> Model
error =
    Error


getPreview : Model -> Maybe PreviewData
getPreview model =
    case model of
        ShowingPreview preview ->
            Just preview

        _ ->
            Nothing


{-| Pick the default join action: select the first virtual member if any, otherwise join as new.
-}
defaultAction : GroupState -> JoinAction
defaultAction groupState =
    Dict.values groupState.members
        |> List.filter (\m -> m.currentMember.memberType == Member.Virtual && not m.isRetired)
        |> List.sortBy (\m -> String.toLower m.name)
        |> List.head
        |> Maybe.map (\m -> ClaimMember m.rootId)
        |> Maybe.withDefault JoinAsNewMember


update : Msg -> Model -> ( Model, Maybe Output )
update msg model =
    case ( msg, model ) of
        ( SelectMember memberId, ShowingPreview preview ) ->
            ( ShowingPreview { preview | selectedAction = ClaimMember memberId }
            , Nothing
            )

        ( SelectJoinAsNew, ShowingPreview preview ) ->
            ( ShowingPreview { preview | selectedAction = JoinAsNewMember }
            , Nothing
            )

        ( InputNewMemberName name, ShowingPreview preview ) ->
            ( ShowingPreview { preview | newMemberName = name }
            , Nothing
            )

        ( ConfirmJoin, ShowingPreview preview ) ->
            case preview.selectedAction of
                JoinAsNewMember ->
                    if String.isEmpty (String.trim preview.newMemberName) then
                        ( model, Nothing )

                    else
                        ( model
                        , Just
                            (JoinConfirmed
                                { selectedAction = preview.selectedAction
                                , newMemberName = String.trim preview.newMemberName
                                }
                            )
                        )

                ClaimMember _ ->
                    ( model
                    , Just
                        (JoinConfirmed
                            { selectedAction = preview.selectedAction
                            , newMemberName = preview.newMemberName
                            }
                        )
                    )

        _ ->
            ( model, Nothing )


view : I18n -> Model -> Ui.Element Msg
view i18n model =
    Ui.column [ Ui.spacing Theme.spacing.xl ]
        (case model of
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
        )


viewPreview : I18n -> PreviewData -> List (Ui.Element Msg)
viewPreview i18n preview =
    let
        virtualMembers : List Member.ChainState
        virtualMembers =
            Dict.values preview.groupState.members
                |> List.filter (\m -> m.currentMember.memberType == Member.Virtual && not m.isRetired)
                |> List.sortBy (\m -> String.toLower m.name)

        realMembers : List Member.ChainState
        realMembers =
            Dict.values preview.groupState.members
                |> List.filter (\m -> m.currentMember.memberType == Member.Real && not m.isRetired)
                |> List.sortBy (\m -> String.toLower m.name)

        isJoinAsNew : Bool
        isJoinAsNew =
            case preview.selectedAction of
                JoinAsNewMember ->
                    True

                _ ->
                    False

        canConfirm : Bool
        canConfirm =
            case preview.selectedAction of
                ClaimMember _ ->
                    True

                JoinAsNewMember ->
                    not (String.isEmpty (String.trim preview.newMemberName))
    in
    [ Ui.el
        [ Ui.centerX
        , Ui.Font.size Theme.font.xl
        , Ui.Font.weight Theme.fontWeight.bold
        , Ui.Font.letterSpacing Theme.letterSpacing.tight
        ]
        (Ui.text preview.groupName)
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
                ]

          else
            Ui.none
        ]
    , if canConfirm then
        let
            confirmLabel : String
            confirmLabel =
                case preview.selectedAction of
                    ClaimMember memberId ->
                        let
                            member : Maybe Member.ChainState
                            member =
                                Dict.get memberId preview.groupState.members
                        in
                        case Maybe.map (\m -> ( m.name, m.currentMember.memberType )) member of
                            Just ( name, Member.Virtual ) ->
                                T.joinGroupConfirmClaim name i18n

                            Just ( name, _ ) ->
                                T.joinGroupConfirmRecover name i18n

                            Nothing ->
                                T.joinGroupConfirm i18n

                    JoinAsNewMember ->
                        T.joinGroupConfirmNew i18n
        in
        UI.Components.btnPrimary []
            { label = confirmLabel
            , onPress = ConfirmJoin
            }

      else
        Ui.none
    ]


viewMemberToggle : JoinAction -> Member.ChainState -> Ui.Element Msg
viewMemberToggle selectedAction member =
    let
        isSelected : Bool
        isSelected =
            case selectedAction of
                ClaimMember id ->
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
