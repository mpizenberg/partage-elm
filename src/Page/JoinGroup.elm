module Page.JoinGroup exposing (JoinAction(..), Model, Msg, Output(..), PreviewData, error, getPreview, init, showPreview, update, view)

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
import Ui.Anim as Anim
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
    Ui.column [ Ui.spacing Theme.spacing.lg, Ui.width Ui.fill, Ui.paddingXY 0 Theme.spacing.xl ]
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
        , Ui.Font.size Theme.font.lg
        , Ui.Font.weight Theme.fontWeight.semibold
        , Ui.Font.color Theme.base.textSubtle
        ]
        (Ui.text (T.joinGroupTitle i18n))
    , Ui.el
        [ Ui.centerX
        , Ui.Font.size Theme.font.xxl
        , Ui.Font.weight Theme.fontWeight.bold
        , Ui.Font.letterSpacing Theme.letterSpacing.tight
        ]
        (Ui.text preview.groupName)
    , if not (List.isEmpty virtualMembers) then
        Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
            [ UI.Components.sectionLabel (T.joinGroupClaimMember i18n)
            , UI.Components.card []
                (List.map (viewMemberOption preview.selectedAction) virtualMembers)
            ]

      else
        Ui.none
    , if not (List.isEmpty realMembers) then
        Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
            [ UI.Components.sectionLabel (T.joinGroupRecoverMember i18n)
            , UI.Components.card []
                (List.map (viewMemberOption preview.selectedAction) realMembers)
            ]

      else
        Ui.none
    , Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
        [ UI.Components.sectionLabel (T.joinGroupJoinAsNew i18n)
        , UI.Components.card [ Ui.padding Theme.spacing.lg ]
            [ radioOption isJoinAsNew (T.joinGroupJoinAsNew i18n) SelectJoinAsNew
            , if isJoinAsNew then
                Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill, Ui.paddingWith { top = Theme.spacing.md, bottom = 0, left = 0, right = 0 } ]
                    [ Ui.el
                        [ Ui.Font.size Theme.font.sm
                        , Ui.Font.weight Theme.fontWeight.semibold
                        ]
                        (Ui.text (T.joinGroupNameLabel i18n))
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
        ]
    , if canConfirm then
        UI.Components.btnPrimary []
            { label = T.joinGroupConfirm i18n
            , onPress = ConfirmJoin
            }

      else
        Ui.none
    ]


viewMemberOption : JoinAction -> Member.ChainState -> Ui.Element Msg
viewMemberOption selectedAction member =
    let
        isSelected : Bool
        isSelected =
            case selectedAction of
                ClaimMember id ->
                    id == member.rootId

                _ ->
                    False
    in
    radioOption isSelected member.name (SelectMember member.rootId)


radioOption : Bool -> String -> msg -> Ui.Element msg
radioOption isSelected label onClick =
    Ui.row
        [ Ui.Input.button onClick
        , Ui.width Ui.fill
        , Ui.spacing Theme.spacing.md
        , Ui.paddingXY Theme.spacing.lg Theme.spacing.md
        , Ui.pointer
        , Ui.Font.size Theme.font.md
        , Ui.Font.weight Theme.fontWeight.medium
        , Ui.contentCenterY
        , if isSelected then
            Ui.background Theme.primary.tint

          else
            Ui.noAttr
        ]
        [ Ui.el
            [ Ui.width (Ui.px 20)
            , Ui.height (Ui.px 20)
            , Ui.rounded Theme.radius.xxxl
            , Ui.border Theme.border
            , Ui.contentCenterX
            , Ui.contentCenterY
            , Anim.transition (Anim.ms 200)
                [ Anim.borderColor
                    (if isSelected then
                        Theme.primary.solid

                     else
                        Theme.base.accent
                    )
                ]
            ]
            (if isSelected then
                Ui.el
                    [ Ui.width (Ui.px 10)
                    , Ui.height (Ui.px 10)
                    , Ui.rounded Theme.radius.xxxl
                    , Ui.background Theme.primary.solid
                    ]
                    Ui.none

             else
                Ui.none
            )
        , Ui.text label
        ]
