module Page.Group.MembersTab exposing (Config, Model, Msg, Output(..), init, update, view)

{-| Members tab showing active and retired members with warm minimal styling.
-}

import Dict
import Domain.GroupState exposing (GroupMetadata, GroupState)
import Domain.Member as Member
import FeatherIcons
import Html
import Html.Attributes
import QRCode
import Set exposing (Set)
import Time
import Translations as T exposing (I18n)
import UI.Components
import UI.Theme as Theme
import Ui
import Ui.Font
import Ui.Input


type alias Model =
    { showQrCode : Bool
    , expandedMembers : Set Member.Id
    , showRetired : Bool
    }


init : Model
init =
    { showQrCode = False
    , expandedMembers = Set.empty
    , showRetired = False
    }


{-| Actions that can be triggered from the members tab.
-}
type Output
    = RetireOutput Member.Id
    | UnretireOutput Member.Id
    | EditMetadataOutput Member.Id


type Msg
    = ToggleQrCode
    | ToggleMember Member.Id
    | ToggleRetired
    | Retire Member.Id
    | Unretire Member.Id
    | EditMetadata Member.Id


update : Msg -> Model -> ( Model, Maybe Output )
update msg model =
    case msg of
        ToggleQrCode ->
            ( { model | showQrCode = not model.showQrCode }, Nothing )

        ToggleMember memberId ->
            ( { model
                | expandedMembers =
                    if Set.member memberId model.expandedMembers then
                        Set.remove memberId model.expandedMembers

                    else
                        Set.insert memberId model.expandedMembers
              }
            , Nothing
            )

        ToggleRetired ->
            ( { model | showRetired = not model.showRetired }, Nothing )

        Retire memberId ->
            ( model, Just (RetireOutput memberId) )

        Unretire memberId ->
            ( model, Just (UnretireOutput memberId) )

        EditMetadata memberId ->
            ( model, Just (EditMetadataOutput memberId) )


{-| Callback messages for member interactions on this tab.
-}
type alias Config msg =
    { onAddMember : msg
    , onEditGroupMetadata : msg
    , inviteLink : String
    , isSynced : Bool
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
    in
    Ui.column [ Ui.spacing Theme.spacing.xl, Ui.width Ui.fill ]
        [ -- Push Notifications
          if config.isSynced then
            notificationRow config

          else
            Ui.none

        -- Group Info
        , groupInfoSection config.onEditGroupMetadata state

        -- Invite
        , if config.isSynced then
            inviteSection i18n toMsg model config state.groupMeta.name

          else
            Ui.none

        -- Active Members
        , Ui.column []
            [ UI.Components.sectionLabel (T.membersTabTitle i18n ++ " (" ++ String.fromInt (List.length active) ++ ")")
            , Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
                (List.map (memberCard i18n toMsg model.expandedMembers currentUserRootId) active)
            ]

        -- Retired Members
        , if not (List.isEmpty retired) then
            Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
                [ UI.Components.expandTrigger
                    { label = T.membersDeparted i18n ++ " (" ++ String.fromInt (List.length retired) ++ ")"
                    , isOpen = model.showRetired
                    , onPress = toMsg ToggleRetired
                    }
                , if model.showRetired then
                    Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill, Ui.opacity 0.6 ]
                        (List.map (memberCard i18n toMsg model.expandedMembers currentUserRootId) retired)

                  else
                    Ui.none
                ]

          else
            Ui.none

        -- Add Member
        , UI.Components.btnPrimary [] { label = T.memberAddButton i18n, onPress = config.onAddMember }
        ]



-- NOTIFICATION ROW


notificationRow : Config msg -> Ui.Element msg
notificationRow config =
    let
        ( statusText, toggleEl ) =
            if not config.pushActive then
                ( "Not available", Ui.none )

            else
                ( if config.isSubscribed then
                    "Enabled"

                  else
                    "Disabled"
                , UI.Components.toggle { isOn = config.isSubscribed, onPress = config.onToggleNotification }
                )
    in
    Ui.row [ Ui.width Ui.fill, Ui.contentCenterY ]
        [ Ui.row [ Ui.spacing Theme.spacing.md, Ui.contentCenterY, Ui.width Ui.shrink ]
            [ notifIcon
            , Ui.column [ Ui.spacing Theme.spacing.xs ]
                [ Ui.el
                    [ Ui.Font.size Theme.font.md
                    , Ui.Font.weight Theme.fontWeight.medium
                    ]
                    (Ui.text "Notifications")
                , Ui.el
                    [ Ui.Font.size Theme.font.xs
                    , Ui.Font.color Theme.base.textSubtle
                    ]
                    (Ui.text statusText)
                ]
            ]
        , toggleEl
        ]


notifIcon : Ui.Element msg
notifIcon =
    Ui.el
        [ Ui.width (Ui.px Theme.sizing.lg)
        , Ui.height (Ui.px Theme.sizing.lg)
        , Ui.rounded Theme.radius.md
        , Ui.background Theme.primary.tint
        , Ui.contentCenterX
        , Ui.contentCenterY
        , Ui.Font.size Theme.font.lg
        ]
        (UI.Components.featherIcon 18 FeatherIcons.bell)



-- GROUP INFO CARD


groupInfoSection : msg -> GroupState -> Ui.Element msg
groupInfoSection onEditGroupMetadata state =
    let
        meta : GroupMetadata
        meta =
            state.groupMeta

        hasInfo : Bool
        hasInfo =
            meta.subtitle /= Nothing || meta.description /= Nothing || not (List.isEmpty meta.links)

        viewSubtitle : String -> Ui.Element msg
        viewSubtitle sub =
            Ui.el [ Ui.Font.size Theme.font.lg ] (Ui.text sub)

        viewDescription : String -> Ui.Element msg
        viewDescription desc =
            Ui.el [ Ui.Font.color Theme.base.textSubtle ] (Ui.text desc)

        viewLinks : Ui.Element msg
        viewLinks =
            if List.isEmpty meta.links then
                Ui.none

            else
                Ui.column [ Ui.spacing Theme.spacing.sm ]
                    (List.map (linkItem FeatherIcons.externalLink) meta.links)

        editLabel : String
        editLabel =
            if hasInfo then
                "Edit group info"

            else
                "Edit group name or add a description"
    in
    Ui.column [ Ui.spacing Theme.spacing.md, Ui.width Ui.fill ]
        [ Maybe.map viewSubtitle meta.subtitle
            |> Maybe.withDefault Ui.none
        , Maybe.map viewDescription meta.description
            |> Maybe.withDefault Ui.none
        , viewLinks
        , UI.Components.btnOutline [ Ui.paddingXY Theme.spacing.md Theme.spacing.sm ]
            { label = editLabel
            , icon = Just (UI.Components.featherIcon 14 FeatherIcons.edit)
            , onPress = onEditGroupMetadata
            }
        ]


linkItem : FeatherIcons.Icon -> { label : String, url : String } -> Ui.Element msg
linkItem icon link =
    let
        displayLabel : String
        displayLabel =
            if String.isEmpty link.label then
                shortenUrl link.url

            else if String.length link.label > 40 then
                String.left 37 link.label ++ "..."

            else
                link.label

        displayUrl : String
        displayUrl =
            shortenUrl link.url
    in
    Ui.row
        [ Ui.linkNewTab link.url
        , Ui.spacing Theme.spacing.sm
        , Ui.contentCenterY
        , Ui.pointer
        , Ui.clipWithEllipsis
        , Ui.Font.size Theme.font.sm
        ]
        [ Ui.el [ Ui.Font.color Theme.primary.text, Ui.width Ui.shrink ] (UI.Components.featherIcon 14 icon)
        , Ui.el
            [ Ui.Font.color Theme.primary.text
            , Ui.Font.underline
            , Ui.Font.noWrap
            , Ui.width Ui.shrink
            ]
            (Ui.text displayLabel)
        , Ui.el
            [ Ui.Font.color Theme.base.textSubtle
            , Ui.Font.noWrap

            -- , Ui.clipWithEllipsis
            ]
            (Ui.text displayUrl)
        ]


shortenUrl : String -> String
shortenUrl url =
    url
        |> String.replace "https://" ""
        |> String.replace "http://" ""
        |> (\s ->
                if String.endsWith "/" s then
                    String.dropRight 1 s

                else
                    s
           )



-- INVITE SECTION


inviteSection : I18n -> (Msg -> msg) -> Model -> Config msg -> String -> Ui.Element msg
inviteSection i18n toMsg model config groupName =
    let
        link : String
        link =
            config.inviteLink
    in
    Ui.column []
        [ UI.Components.sectionLabel (T.inviteLinkTitle i18n)
        , Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
            [ Ui.el
                [ Ui.Font.size Theme.font.sm
                , Ui.Font.color Theme.base.textSubtle
                ]
                (Ui.text (T.inviteLinkHint i18n))
            , Ui.row [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
                [ copyBtn link (T.inviteLinkCopy i18n)
                , shareBtn link groupName (T.inviteLinkShare i18n)
                , UI.Components.btnOutline [ Ui.width Ui.shrink ]
                    { label = "QR"
                    , icon = Just (UI.Components.featherIcon 16 FeatherIcons.grid)
                    , onPress = toMsg ToggleQrCode
                    }
                ]
            , if model.showQrCode then
                qrCodeView link

              else
                Ui.none
            ]
        ]


{-| Copy button: elm-ui button with transparent copy-button web component overlaid.
We assume clipboard API is always supported.
-}
copyBtn : String -> String -> Ui.Element msg
copyBtn copyText label =
    Ui.row
        (Ui.width Ui.shrink
            :: Ui.inFront
                (Ui.el [ Ui.width Ui.fill, Ui.height Ui.fill ]
                    (Ui.html
                        (Html.node "copy-button"
                            [ Html.Attributes.attribute "data-copy" copyText
                            , Html.Attributes.style "display" "block"
                            , Html.Attributes.style "width" "100%"
                            , Html.Attributes.style "height" "100%"
                            , Html.Attributes.style "cursor" "pointer"
                            ]
                            []
                        )
                    )
                )
            :: UI.Components.btnOutlineAttrs
        )
        [ UI.Components.featherIcon 16 FeatherIcons.copy
        , Ui.text label
        ]


{-| Share button: elm-ui button rendered inside the share-button web component.
The web component handles feature detection and hides itself when unsupported.
-}
shareBtn : String -> String -> String -> Ui.Element msg
shareBtn shareUrl shareTitle label =
    Ui.html
        (Html.node "share-button"
            [ Html.Attributes.attribute "data-share-url" shareUrl
            , Html.Attributes.attribute "data-share-title" shareTitle

            -- , Html.Attributes.style "display" "contents"
            ]
            [ Ui.layout (Ui.default |> Ui.withNoStylesheet)
                []
                (Ui.row
                    (Ui.width Ui.shrink :: UI.Components.btnOutlineAttrs)
                    [ UI.Components.featherIcon 16 FeatherIcons.share2
                    , Ui.text label
                    ]
                )
            ]
        )


qrCodeView : String -> Ui.Element msg
qrCodeView link =
    case QRCode.fromString link of
        Ok qrCode ->
            UI.Components.card [ Ui.padding Theme.spacing.xl ]
                [ Ui.html
                    (QRCode.toSvg
                        [ Html.Attributes.attribute "width" "100%"
                        , Html.Attributes.style "max-width" "200px"
                        , Html.Attributes.style "margin" "0 auto"
                        , Html.Attributes.style "display" "block"
                        ]
                        qrCode
                    )
                ]

        Err _ ->
            Ui.none



-- MEMBER CARD


memberCard : I18n -> (Msg -> msg) -> Set Member.Id -> Member.Id -> Member.ChainState -> Ui.Element msg
memberCard i18n toMsg expandedMembers currentUserRootId member =
    let
        isCurrentUser : Bool
        isCurrentUser =
            member.rootId == currentUserRootId

        isExpanded : Bool
        isExpanded =
            Set.member member.rootId expandedMembers

        nameLabel : String
        nameLabel =
            if isCurrentUser then
                T.nameYouSuffix member.name i18n

            else
                member.name

        isVirtual : Bool
        isVirtual =
            member.currentMember.memberType == Member.Virtual

        initials : String
        initials =
            String.left 2 (String.toUpper member.name)

        cardAttrs : List (Ui.Attribute msg)
        cardAttrs =
            if isCurrentUser then
                [ Ui.background Theme.base.text
                , Ui.borderColor Theme.base.text
                ]

            else
                []

        nameAttrs : List (Ui.Attribute msg)
        nameAttrs =
            if isCurrentUser then
                [ Ui.Font.color Theme.base.bg ]

            else
                []

        avatarEl : Ui.Element msg
        avatarEl =
            UI.Components.avatar
                (if isCurrentUser then
                    UI.Components.AvatarNeutralInversed

                 else
                    UI.Components.AvatarAccent
                )
                initials
    in
    UI.Components.card
        ([ Ui.paddingXY Theme.spacing.lg Theme.spacing.md
         , Ui.spacing Theme.spacing.md
         ]
            ++ cardAttrs
        )
        [ -- Header row (clickable to expand/collapse)
          Ui.row
            [ Ui.Input.button (toMsg (ToggleMember member.rootId))
            , Ui.spacing Theme.spacing.md
            , Ui.contentCenterY
            , Ui.width Ui.fill
            , Ui.pointer
            ]
            [ avatarEl
            , Ui.column [ Ui.spacing Theme.spacing.xs ]
                [ Ui.row [ Ui.spacing Theme.spacing.xs, Ui.contentCenterY, Ui.width Ui.shrink ]
                    [ Ui.el
                        ([ Ui.Font.weight Theme.fontWeight.semibold
                         , Ui.Font.size Theme.font.md
                         ]
                            ++ nameAttrs
                        )
                        (Ui.text nameLabel)
                    , if isVirtual then
                        virtualTag i18n

                      else
                        Ui.none
                    ]
                , Ui.el
                    [ Ui.Font.size Theme.font.xs
                    , Ui.Font.color
                        (if isCurrentUser then
                            Theme.base.bgSubtle

                         else
                            Theme.base.textSubtle
                        )
                    ]
                    (Ui.text (formatJoinDate member.joinedAt))
                ]
            ]

        -- Expanded detail content
        , if isExpanded then
            memberDetail i18n toMsg currentUserRootId member

          else
            Ui.none
        ]


virtualTag : I18n -> Ui.Element msg
virtualTag i18n =
    Ui.el
        [ Ui.Font.size Theme.font.xs
        , Ui.Font.weight Theme.fontWeight.semibold
        , Ui.paddingXY Theme.spacing.sm Theme.spacing.xs
        , Ui.rounded Theme.radius.sm
        , Ui.background Theme.base.tint
        , Ui.Font.color Theme.base.textSubtle
        , Ui.width Ui.shrink
        ]
        (Ui.text (T.memberVirtualLabel i18n))


memberDetail : I18n -> (Msg -> msg) -> Member.Id -> Member.ChainState -> Ui.Element msg
memberDetail i18n toMsg currentUserRootId member =
    let
        retireButton : Ui.Element msg
        retireButton =
            if member.isRetired then
                Ui.row
                    [ Ui.Input.button (toMsg (Unretire member.rootId))
                    , Ui.width Ui.fill
                    , Ui.spacing Theme.spacing.sm
                    , Ui.contentCenterX
                    , Ui.contentCenterY
                    , Ui.padding Theme.spacing.md
                    , Ui.rounded Theme.radius.md
                    , Ui.background Theme.success.solid
                    , Ui.Font.color Theme.success.solidText
                    , Ui.Font.weight Theme.fontWeight.semibold
                    , Ui.pointer
                    ]
                    [ UI.Components.featherIcon 16 FeatherIcons.userPlus
                    , Ui.text (T.memberUnretireButton i18n)
                    ]

            else if member.rootId /= currentUserRootId then
                Ui.row
                    [ Ui.Input.button (toMsg (Retire member.rootId))
                    , Ui.width Ui.fill
                    , Ui.spacing Theme.spacing.sm
                    , Ui.contentCenterX
                    , Ui.contentCenterY
                    , Ui.padding Theme.spacing.md
                    , Ui.rounded Theme.radius.md
                    , Ui.background Theme.danger.solid
                    , Ui.Font.color Theme.danger.solidText
                    , Ui.Font.weight Theme.fontWeight.semibold
                    , Ui.pointer
                    ]
                    [ UI.Components.featherIcon 16 FeatherIcons.trash2
                    , Ui.text (T.memberRetireButton i18n)
                    ]

            else
                Ui.none

        notesSection : String -> Ui.Element msg
        notesSection notes =
            Ui.column []
                [ UI.Components.sectionLabel (T.memberMetadataNotes i18n)
                , Ui.el [ Ui.Font.color Theme.base.textSubtle ] (Ui.text notes)
                ]

        metadataSections : Ui.Element msg
        metadataSections =
            let
                meta : Member.Metadata
                meta =
                    member.metadata

                infoRows : List (Ui.Element msg)
                infoRows =
                    List.filterMap identity
                        [ Maybe.map (\v -> infoRow FeatherIcons.phone (T.memberMetadataPhone i18n) v (Just ("tel:" ++ stripSpaces v))) meta.phone
                        , Maybe.map (\v -> infoRow FeatherIcons.atSign (T.memberMetadataEmail i18n) v (Just ("mailto:" ++ v))) meta.email
                        ]

                contactSection : Maybe (Ui.Element msg)
                contactSection =
                    if List.isEmpty infoRows then
                        Nothing

                    else
                        Just
                            (Ui.column []
                                [ UI.Components.sectionLabel (T.memberDetailContactInfo i18n)
                                , Ui.column [ Ui.spacing Theme.spacing.md ] infoRows
                                ]
                            )

                paymentMethods : List (Ui.Element msg)
                paymentMethods =
                    case meta.payment of
                        Just payment ->
                            List.filterMap identity
                                [ Maybe.map (\v -> infoRow FeatherIcons.creditCard (T.memberMetadataIban i18n) v Nothing) payment.iban
                                , Maybe.map (\v -> infoRow FeatherIcons.smartphone (T.memberMetadataWero i18n) v Nothing) payment.wero
                                , Maybe.map (\v -> infoRow FeatherIcons.dollarSign (T.memberMetadataLydia i18n) v (Just (normalizeHandle "https://pay.lydia.me/l?t=" v))) payment.lydia
                                , Maybe.map (\v -> infoRow FeatherIcons.dollarSign (T.memberMetadataRevolut i18n) v (Just (normalizeHandle "https://revolut.me/" v))) payment.revolut
                                , Maybe.map (\v -> infoRow FeatherIcons.dollarSign (T.memberMetadataPaypal i18n) v (Just (normalizeHandle "https://paypal.me/" v))) payment.paypal
                                , Maybe.map (\v -> infoRow FeatherIcons.dollarSign (T.memberMetadataVenmo i18n) v (Just (normalizeHandle "https://venmo.com/" v))) payment.venmo
                                , Maybe.map (\v -> infoRow FeatherIcons.key (T.memberMetadataBtc i18n) v (Just ("bitcoin:" ++ v))) payment.btcAddress
                                , Maybe.map (\v -> infoRow FeatherIcons.key (T.memberMetadataAda i18n) v Nothing) payment.adaAddress
                                ]

                        Nothing ->
                            []

                paymentMethodsSection : Maybe (Ui.Element msg)
                paymentMethodsSection =
                    if List.isEmpty paymentMethods then
                        Nothing

                    else
                        Just
                            (Ui.column []
                                [ UI.Components.sectionLabel (T.memberMetadataPayment i18n)
                                , Ui.column [ Ui.spacing Theme.spacing.md ] paymentMethods
                                ]
                            )

                sections : List (Ui.Element msg)
                sections =
                    List.filterMap identity
                        [ contactSection
                        , Maybe.map notesSection meta.notes
                        , paymentMethodsSection
                        ]
            in
            if List.isEmpty sections then
                Ui.none

            else
                Ui.column [ Ui.spacing Theme.spacing.xl, Ui.width Ui.fill ] sections
    in
    Ui.column [ Ui.spacing Theme.spacing.md, Ui.width Ui.fill ]
        [ -- Metadata sections
          metadataSections

        -- Action buttons
        , UI.Components.btnOutline []
            { label = T.memberEditMetadataButton i18n
            , icon = Just (UI.Components.featherIcon 16 FeatherIcons.edit)
            , onPress = toMsg (EditMetadata member.rootId)
            }
        , retireButton
        ]



-- MEMBER DETAIL HELPERS


infoRow : FeatherIcons.Icon -> String -> String -> Maybe String -> Ui.Element msg
infoRow icon label value maybeUrl =
    Ui.row [ Ui.spacing Theme.spacing.sm, Ui.contentCenterY ]
        [ Ui.el [ Ui.Font.color Theme.base.textSubtle, Ui.width Ui.shrink ] (UI.Components.featherIcon 16 icon)
        , Ui.el
            [ Ui.Font.size Theme.font.sm
            , Ui.Font.color Theme.base.textSubtle
            , Ui.width Ui.shrink
            ]
            (Ui.text label)
        , case maybeUrl of
            Just url ->
                Ui.el
                    [ Ui.linkNewTab url
                    , Ui.Font.size Theme.font.md
                    , Ui.Font.color Theme.primary.text
                    , Ui.Font.underline
                    , Ui.pointer
                    , Ui.width Ui.shrink
                    , Ui.clipWithEllipsis
                    ]
                    (Ui.text value)

            Nothing ->
                Ui.el [ Ui.Font.size Theme.font.md, Ui.clipWithEllipsis ] (Ui.text value)
        , copyButton value
        ]


copyButton : String -> Ui.Element msg
copyButton value =
    Ui.el
        [ Ui.width Ui.shrink
        , Ui.alignRight
        , Ui.inFront
            (Ui.el [ Ui.width Ui.fill, Ui.height Ui.fill ]
                (Ui.html
                    (Html.node "copy-button"
                        [ Html.Attributes.attribute "data-copy" value
                        , Html.Attributes.style "display" "block"
                        , Html.Attributes.style "width" "100%"
                        , Html.Attributes.style "height" "100%"
                        , Html.Attributes.style "cursor" "pointer"
                        ]
                        []
                    )
                )
            )
        , Ui.Font.color Theme.base.textSubtle
        , Ui.pointer
        ]
        (UI.Components.featherIcon 16 FeatherIcons.copy)


normalizeHandle : String -> String -> String
normalizeHandle prefix value =
    let
        trimmed : String
        trimmed =
            String.trim value
    in
    if String.startsWith prefix trimmed then
        trimmed

    else
        let
            withoutLeadingAt : String
            withoutLeadingAt =
                if String.startsWith "@" trimmed then
                    String.dropLeft 1 trimmed

                else
                    trimmed
        in
        prefix ++ withoutLeadingAt


stripSpaces : String -> String
stripSpaces =
    String.filter (\c -> c /= ' ')



-- HELPERS


boolToInt : Bool -> Int
boolToInt b =
    if b then
        1

    else
        0


formatJoinDate : Time.Posix -> String
formatJoinDate posix =
    let
        zone : Time.Zone
        zone =
            Time.utc

        month : String
        month =
            case Time.toMonth zone posix of
                Time.Jan ->
                    "Jan"

                Time.Feb ->
                    "Feb"

                Time.Mar ->
                    "Mar"

                Time.Apr ->
                    "Apr"

                Time.May ->
                    "May"

                Time.Jun ->
                    "Jun"

                Time.Jul ->
                    "Jul"

                Time.Aug ->
                    "Aug"

                Time.Sep ->
                    "Sep"

                Time.Oct ->
                    "Oct"

                Time.Nov ->
                    "Nov"

                Time.Dec ->
                    "Dec"

        year : String
        year =
            String.fromInt (Time.toYear zone posix)
    in
    "Joined " ++ month ++ " " ++ year
