module Page.Group.MembersTab exposing (view)

{-| Members tab showing active and retired members.
-}

import Dict
import Domain.GroupState exposing (GroupState)
import Domain.Member as Member
import UI.Components
import UI.Theme as Theme
import Ui
import Ui.Font


view : GroupState -> Member.Id -> Ui.Element msg
view state currentUserRootId =
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
            UI.Components.memberRow
                { member = member
                , isCurrentUser = member.rootId == currentUserRootId
                }
    in
    Ui.column [ Ui.spacing Theme.spacing.md, Ui.width Ui.fill ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.lg, Ui.Font.bold ] (Ui.text "Members")
        , Ui.column [ Ui.width Ui.fill ]
            (List.map viewMember active)
        , if not (List.isEmpty retired) then
            Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
                [ Ui.el [ Ui.Font.size Theme.fontSize.md, Ui.Font.bold, Ui.Font.color Theme.neutral500 ]
                    (Ui.text "Departed")
                , Ui.column [ Ui.width Ui.fill ]
                    (List.map viewMember retired)
                ]

          else
            Ui.none
        ]


boolToInt : Bool -> Int
boolToInt b =
    if b then
        1

    else
        0
