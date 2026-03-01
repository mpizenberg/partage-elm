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
    , onEditGroupMetadata : msg
    }


view : I18n -> Msg msg -> Member.Id -> GroupState -> Ui.Element msg
view i18n msg currentUserRootId state =
    let
        allMembers =
            Dict.values state.members

        active =
            allMembers
                |> List.filter (not << .isRetired)
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
        [ groupInfoSection i18n state
        , editGroupButton i18n msg.onEditGroupMetadata
        , Ui.el [ Ui.Font.size Theme.fontSize.lg, Ui.Font.bold ] (Ui.text (T.membersTabTitle i18n))
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


groupInfoSection : I18n -> GroupState -> Ui.Element msg
groupInfoSection i18n state =
    let
        meta =
            state.groupMeta

        subtitleEl =
            case meta.subtitle of
                Just subtitle ->
                    Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
                        [ Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.bold, Ui.Font.color Theme.neutral500 ]
                            (Ui.text (T.groupInfoSubtitle i18n))
                        , Ui.el [ Ui.Font.size Theme.fontSize.md ] (Ui.text subtitle)
                        ]

                Nothing ->
                    Ui.none

        descriptionEl =
            case meta.description of
                Just description ->
                    Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
                        [ Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.bold, Ui.Font.color Theme.neutral500 ]
                            (Ui.text (T.groupInfoDescription i18n))
                        , Ui.el [ Ui.Font.size Theme.fontSize.md ] (Ui.text description)
                        ]

                Nothing ->
                    Ui.none

        linksEl =
            if List.isEmpty meta.links then
                Ui.none

            else
                Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
                    [ Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.bold, Ui.Font.color Theme.neutral500 ]
                        (Ui.text (T.groupInfoLinks i18n))
                    , Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
                        (List.map viewLink meta.links)
                    ]

        hasInfo =
            meta.subtitle /= Nothing || meta.description /= Nothing || not (List.isEmpty meta.links)
    in
    if hasInfo then
        Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
            [ subtitleEl, descriptionEl, linksEl ]

    else
        Ui.none


viewLink : { label : String, url : String } -> Ui.Element msg
viewLink link =
    let
        displayLabel =
            if String.isEmpty link.label then
                link.url

            else
                link.label
    in
    Ui.el [ Ui.Font.color Theme.primary, Ui.Font.size Theme.fontSize.md ]
        (Ui.text displayLabel)


editGroupButton : I18n -> msg -> Ui.Element msg
editGroupButton i18n onEdit =
    Ui.el
        [ Ui.Input.button onEdit
        , Ui.Font.color Theme.primary
        , Ui.Font.bold
        , Ui.Font.size Theme.fontSize.sm
        , Ui.pointer
        ]
        (Ui.text (T.groupSettingsEditButton i18n))


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
