module Page.Group.MembersTab exposing (Config, Model, Msg, init, update, view)

{-| Members tab showing active and retired members.
-}

import Dict
import Domain.GroupState exposing (GroupMetadata, GroupState)
import Domain.Member as Member
import Html
import Html.Attributes
import QRCode
import Translations as T exposing (I18n)
import UI.Components
import UI.Theme as Theme
import Ui
import Ui.Events
import Ui.Font
import Ui.Input


type alias Model =
    { showQrCode : Bool
    }


init : Model
init =
    { showQrCode = False
    }


type Msg
    = ToggleQrCode


update : Msg -> Model -> Model
update msg model =
    case msg of
        ToggleQrCode ->
            { model | showQrCode = not model.showQrCode }


{-| Callback messages for member interactions on this tab.
-}
type alias Config msg =
    { onMemberClick : Member.Id -> msg
    , onAddMember : msg
    , onEditGroupMetadata : msg
    , inviteLink : String
    , onToggleNotification : msg
    , isSubscribed : Bool
    , pushActive : Bool
    }


{-| Render the members tab with active and retired member lists.
-}
view : I18n -> Config msg -> (Msg -> msg) -> Model -> Member.Id -> GroupState -> Ui.Element msg
view i18n config toMsg model currentUserRootId state =
    let
        allMembers : List Member.ChainState
        allMembers =
            Dict.values state.members

        active : List Member.ChainState
        active =
            allMembers
                |> List.filter (not << .isRetired)
                |> List.sortBy (\m -> ( boolToInt (m.rootId /= currentUserRootId), String.toLower m.name ))

        retired : List Member.ChainState
        retired =
            allMembers
                |> List.filter .isRetired
                |> List.sortBy (\m -> String.toLower m.name)

        viewMember : Member.ChainState -> Ui.Element msg
        viewMember member =
            UI.Components.memberRow i18n
                (config.onMemberClick member.rootId)
                { member = member
                , isCurrentUser = member.rootId == currentUserRootId
                }
    in
    Ui.column [ Ui.spacing Theme.spacing.md, Ui.width Ui.fill ]
        [ groupInfoSection i18n state
        , editGroupButton i18n config.onEditGroupMetadata
        , inviteLinkSection i18n toMsg model config state.groupMeta.name
        , notificationToggle config
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
        , addMemberButton i18n config.onAddMember
        ]


notificationToggle : Config msg -> Ui.Element msg
notificationToggle config =
    if not config.pushActive then
        Ui.row [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
            [ Ui.el [ Ui.Font.size Theme.fontSize.md, Ui.Font.color Theme.neutral300 ]
                (Ui.text bellOutline)
            , Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral300 ]
                (Ui.text "Notifications")
            ]

    else
        Ui.row
            [ Ui.spacing Theme.spacing.sm
            , Ui.width Ui.fill
            , Ui.pointer
            , Ui.Events.onClick config.onToggleNotification
            ]
            [ Ui.el
                [ Ui.Font.size Theme.fontSize.md
                , Ui.Font.color
                    (if config.isSubscribed then
                        Theme.primary

                     else
                        Theme.neutral500
                    )
                ]
                (Ui.text
                    (if config.isSubscribed then
                        bellFilled

                     else
                        bellOutline
                    )
                )
            , Ui.el
                [ Ui.Font.size Theme.fontSize.sm
                , Ui.Font.color
                    (if config.isSubscribed then
                        Theme.primary

                     else
                        Theme.neutral500
                    )
                ]
                (Ui.text "Notifications")
            ]


bellFilled : String
bellFilled =
    "🔔"


bellOutline : String
bellOutline =
    "🔕"


inviteLinkSection : I18n -> (Msg -> msg) -> Model -> Config msg -> String -> Ui.Element msg
inviteLinkSection i18n toMsg model config groupName =
    let
        link : String
        link =
            config.inviteLink

        buttonStyles : List (Html.Attribute msg)
        buttonStyles =
            [ Html.Attributes.style "cursor" "pointer"
            , Html.Attributes.style "display" "flex"
            , Html.Attributes.style "align-items" "center"
            , Html.Attributes.style "gap" "8px"
            , Html.Attributes.style "padding" "8px 12px"
            , Html.Attributes.style "border-radius" "6px"
            , Html.Attributes.style "background" "#f3f4f6"
            , Html.Attributes.style "font-size" (String.fromInt Theme.fontSize.sm ++ "px")
            ]
    in
    Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.md, Ui.Font.bold ]
            (Ui.text (T.inviteLinkTitle i18n))
        , Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ]
            (Ui.text (T.inviteLinkHint i18n))
        , Ui.html
            (Html.node "copy-button"
                (Html.Attributes.attribute "data-copy" link :: buttonStyles)
                [ Html.text (T.inviteLinkCopy i18n ++ " 📋") ]
            )
        , Ui.html
            (Html.node "share-button"
                (Html.Attributes.attribute "data-share-url" link
                    :: Html.Attributes.attribute "data-share-title" groupName
                    :: buttonStyles
                )
                [ Html.text (T.inviteLinkShare i18n ++ " 🔗") ]
            )
        , Ui.el
            [ Ui.Events.onClick (toMsg ToggleQrCode)
            , Ui.Font.color Theme.primary
            , Ui.Font.size Theme.fontSize.sm
            , Ui.pointer
            ]
            (Ui.text
                (if model.showQrCode then
                    T.inviteLinkHideQR i18n

                 else
                    T.inviteLinkShowQR i18n
                )
            )
        , if model.showQrCode then
            qrCodeView link

          else
            Ui.none
        ]


qrCodeView : String -> Ui.Element msg
qrCodeView link =
    case QRCode.fromString link of
        Ok qrCode ->
            Ui.el [ Ui.width Ui.fill, Ui.padding Theme.spacing.md ]
                (Ui.html
                    (QRCode.toSvg
                        [ Html.Attributes.attribute "width" "100%"
                        , Html.Attributes.style "max-width" "280px"
                        , Html.Attributes.style "margin" "0 auto"
                        , Html.Attributes.style "display" "block"
                        ]
                        qrCode
                    )
                )

        Err _ ->
            Ui.none


groupInfoSection : I18n -> GroupState -> Ui.Element msg
groupInfoSection i18n state =
    let
        meta : GroupMetadata
        meta =
            state.groupMeta

        hasInfo : Bool
        hasInfo =
            meta.subtitle /= Nothing || meta.description /= Nothing || not (List.isEmpty meta.links)
    in
    if hasInfo then
        let
            subtitleEl : Ui.Element msg
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

            descriptionEl : Ui.Element msg
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

            linksEl : Ui.Element msg
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
        in
        Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
            [ subtitleEl, descriptionEl, linksEl ]

    else
        Ui.none


viewLink : { label : String, url : String } -> Ui.Element msg
viewLink link =
    let
        displayLabel : String
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
