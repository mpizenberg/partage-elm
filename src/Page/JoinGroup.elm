module Page.JoinGroup exposing (JoinAction(..), Model, Msg, Output(..), PreviewData, error, getPreview, init, showPreview, update, view)

{-| Join group page shown when opening an invite link.
Displays a group preview with options to claim a virtual member or join as new.
-}

import Dict
import Domain.Event as Event
import Domain.GroupState exposing (GroupState)
import Domain.Member as Member
import Translations as T exposing (I18n)
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
    Ui.column [ Ui.spacing Theme.spacing.lg, Ui.width Ui.fill, Ui.paddingXY Theme.spacing.md Theme.spacing.xl ]
        (case model of
            FetchingGroup ->
                [ Ui.el [ Ui.centerX, Ui.Font.size Theme.fontSize.md, Ui.Font.color Theme.neutral500 ]
                    (Ui.text (T.joinGroupFetching i18n))
                ]

            Error errorMsg ->
                [ Ui.el [ Ui.centerX, Ui.Font.size Theme.fontSize.md, Ui.Font.color Theme.danger ]
                    (Ui.text (T.joinGroupError i18n))
                , Ui.el [ Ui.centerX, Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ]
                    (Ui.text errorMsg)
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
    [ Ui.el [ Ui.centerX, Ui.Font.size Theme.fontSize.lg, Ui.Font.bold ]
        (Ui.text (T.joinGroupTitle i18n))
    , Ui.el [ Ui.centerX, Ui.Font.size Theme.fontSize.hero, Ui.Font.bold ]
        (Ui.text preview.groupName)
    , if not (List.isEmpty virtualMembers) then
        Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
            [ Ui.el [ Ui.Font.size Theme.fontSize.md, Ui.Font.bold ]
                (Ui.text (T.joinGroupClaimMember i18n))
            , Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
                (List.map (viewMemberOption preview.selectedAction) virtualMembers)
            ]

      else
        Ui.none
    , if not (List.isEmpty realMembers) then
        Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
            [ Ui.el [ Ui.Font.size Theme.fontSize.md, Ui.Font.bold ]
                (Ui.text (T.joinGroupRecoverMember i18n))
            , Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
                (List.map (viewMemberOption preview.selectedAction) realMembers)
            ]

      else
        Ui.none
    , Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
        [ radioOption isJoinAsNew (T.joinGroupJoinAsNew i18n) SelectJoinAsNew
        , if isJoinAsNew then
            Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill, Ui.paddingXY Theme.spacing.lg 0 ]
                [ Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.bold ]
                    (Ui.text (T.joinGroupNameLabel i18n))
                , Ui.Input.text
                    [ Ui.width Ui.fill
                    , Ui.padding Theme.spacing.sm
                    , Ui.rounded Theme.rounding.sm
                    , Ui.border 1
                    , Ui.borderColor Theme.neutral300
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
        actionButton (T.joinGroupConfirm i18n) ConfirmJoin

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
    Ui.el
        [ Ui.Input.button onClick
        , Ui.width Ui.fill
        , Ui.padding Theme.spacing.sm
        , Ui.rounded Theme.rounding.sm
        , Ui.pointer
        , if isSelected then
            Ui.background Theme.primaryLight

          else
            Ui.background Theme.neutral200
        , if isSelected then
            Ui.border 2

          else
            Ui.border 1
        , if isSelected then
            Ui.borderColor Theme.primary

          else
            Ui.borderColor Theme.neutral300
        ]
        (Ui.row [ Ui.spacing Theme.spacing.sm ]
            [ Ui.el
                [ Ui.width (Ui.px 18)
                , Ui.height (Ui.px 18)
                , Ui.rounded 9
                , Ui.border 2
                , Ui.borderColor
                    (if isSelected then
                        Theme.primary

                     else
                        Theme.neutral500
                    )
                , Ui.background
                    (if isSelected then
                        Theme.primary

                     else
                        Theme.white
                    )
                ]
                Ui.none
            , Ui.el [ Ui.Font.size Theme.fontSize.md ] (Ui.text label)
            ]
        )


actionButton : String -> msg -> Ui.Element msg
actionButton label onClick =
    Ui.el
        [ Ui.Input.button onClick
        , Ui.centerX
        , Ui.paddingXY Theme.spacing.xl Theme.spacing.sm
        , Ui.rounded Theme.rounding.md
        , Ui.background Theme.primary
        , Ui.Font.color Theme.white
        , Ui.Font.size Theme.fontSize.md
        , Ui.Font.bold
        , Ui.Font.center
        , Ui.pointer
        ]
        (Ui.text label)
