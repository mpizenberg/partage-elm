module Page.Group.MembersTab exposing (Msg, view)

{-| Members tab showing active and retired members.
-}

import Dict
import Domain.GroupState exposing (GroupState)
import Domain.Member as Member
import Translations as T exposing (I18n)
import UI.Components
import UI.Theme as Theme
import Ui
import Ui.Font
import Ui.Input


type alias Msg msg =
    { onMemberClick : Member.Id -> msg
    , onAddMember : msg
    }


view : I18n -> Msg msg -> Member.Id -> GroupState -> Ui.Element msg
view i18n msg currentUserRootId state =
    let
        allMembers =
            Dict.values state.members

        active =
            allMembers
                |> List.filter .isActive
                |> List.sortBy (\m -> ( boolToInt (m.rootId /= currentUserRootId), String.toLower m.name ))

        retired =
            allMembers
                |> List.filter .isRetired
                |> List.sortBy (\m -> String.toLower m.name)

        viewMember member =
            UI.Components.memberRow i18n
                (msg.onMemberClick member.rootId)
                { member = member
                , isCurrentUser = member.rootId == currentUserRootId
                }
    in
    Ui.column [ Ui.spacing Theme.spacing.md, Ui.width Ui.fill ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.lg, Ui.Font.bold ] (Ui.text (T.membersTabTitle i18n))
        , Ui.column [ Ui.width Ui.fill ]
            (List.map viewMember active)
        , if not (List.isEmpty retired) then
            Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
                [ Ui.el [ Ui.Font.size Theme.fontSize.md, Ui.Font.bold, Ui.Font.color Theme.neutral500 ]
                    (Ui.text (T.membersDeparted i18n))
                , Ui.column [ Ui.width Ui.fill ]
                    (List.map viewMember retired)
                ]

          else
            Ui.none
        , addMemberButton i18n msg.onAddMember
        ]


addMemberButton : I18n -> msg -> Ui.Element msg
addMemberButton i18n onAddMember =
    Ui.el
        [ Ui.Input.button onAddMember
        , Ui.width Ui.fill
        , Ui.padding Theme.spacing.md
        , Ui.rounded Theme.rounding.md
        , Ui.background Theme.primary
        , Ui.Font.color Theme.white
        , Ui.Font.center
        , Ui.Font.bold
        , Ui.pointer
        ]
        (Ui.text (T.memberAddButton i18n))


boolToInt : Bool -> Int
boolToInt b =
    if b then
        1

    else
        0
