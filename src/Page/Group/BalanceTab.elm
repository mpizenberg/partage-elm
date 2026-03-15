module Page.Group.BalanceTab exposing (Config, Model, Msg, init, update, view)

{-| Balance tab showing per-member balances and settlement plan.
-}

import Dict
import Domain.Balance as Balance exposing (MemberBalance)
import Domain.GroupState as GroupState exposing (GroupState)
import Domain.Member as Member
import Domain.Settlement as Settlement
import FeatherIcons
import Format
import Html
import Html.Attributes
import List.Extra
import Translations as T exposing (I18n)
import UI.Components
import UI.Theme as Theme
import Ui
import Ui.Font
import Ui.Input


type Model
    = Model
        { expandedMember : Maybe Member.Id
        , selectedSettlement : Maybe Int
        }


type Msg
    = ToggleMember Member.Id
    | ToggleSettlement Int


init : Model
init =
    Model { expandedMember = Nothing, selectedSettlement = Nothing }


update : Msg -> Model -> Model
update msg (Model data) =
    case msg of
        ToggleMember memberId ->
            Model
                { data
                    | expandedMember =
                        if data.expandedMember == Just memberId then
                            Nothing

                        else
                            Just memberId
                }

        ToggleSettlement idx ->
            Model
                { data
                    | selectedSettlement =
                        if data.selectedSettlement == Just idx then
                            Nothing

                        else
                            Just idx
                }


{-| Configuration for callbacks used by the balance tab.
-}
type alias Config msg =
    { onRecordTransfer : Settlement.Transaction -> msg
    , onSavePreferences : { memberRootId : Member.Id, preferredRecipients : List Member.Id } -> msg
    , onNewTransfer : { toMemberId : Member.Id, amountCents : Int } -> msg
    , newTransferHref : String
    , toMsg : Msg -> msg
    }


{-| Render the balance tab with per-member balances and a settlement plan.
-}
view : I18n -> Config msg -> Maybe Member.Id -> Model -> GroupState -> Ui.Element msg
view i18n config maybeUserRootId (Model data) state =
    if Dict.isEmpty state.entries then
        Ui.column [ Ui.spacing Theme.spacing.lg, Ui.width Ui.fill ]
            [ Ui.el [ Ui.Font.size Theme.font.lg, Ui.Font.weight Theme.fontWeight.bold ] (Ui.text (T.balanceTabTitle i18n))
            , Ui.el [ Ui.Font.size Theme.font.sm, Ui.Font.color Theme.base.textSubtle ]
                (Ui.text (T.balanceNoEntries i18n))
            ]

    else
        Ui.column [ Ui.spacing Theme.spacing.lg ]
            (List.filterMap identity
                [ Maybe.map (\uid -> yourBalanceCard i18n uid state) maybeUserRootId
                , Just (otherMembersSection i18n config data.expandedMember maybeUserRootId state)
                , Just (settlementSection i18n config maybeUserRootId data.selectedSettlement state)
                , Maybe.map (\uid -> preferencesSection i18n config uid state) maybeUserRootId
                ]
            )



-- YOUR BALANCE CARD


yourBalanceCard : I18n -> Member.Id -> GroupState -> Ui.Element msg
yourBalanceCard i18n currentUserRootId state =
    let
        myBalance : Maybe MemberBalance
        myBalance =
            Dict.get currentUserRootId state.balances

        ( amountText, detailText ) =
            case myBalance of
                Just b ->
                    let
                        status : Balance.Status
                        status =
                            Balance.status b

                        prefix : String
                        prefix =
                            case status of
                                Balance.Creditor ->
                                    "+"

                                Balance.Debtor ->
                                    "-"

                                Balance.Settled ->
                                    ""
                    in
                    ( prefix ++ Format.formatCents (abs b.netBalance)
                    , case status of
                        Balance.Creditor ->
                            T.balanceIsOwedYou i18n

                        Balance.Debtor ->
                            T.balanceOwesYou i18n

                        Balance.Settled ->
                            T.balanceSettled i18n
                    )

                Nothing ->
                    ( Format.formatCents 0, T.balanceSettled i18n )

        amountColor : Ui.Color
        amountColor =
            case myBalance |> Maybe.map Balance.status of
                Just Balance.Creditor ->
                    Theme.success.accentSubtle

                Just Balance.Debtor ->
                    Theme.danger.accentSubtle

                _ ->
                    Theme.base.bgSubtle
    in
    Ui.column
        [ Ui.background Theme.base.text
        , Ui.rounded Theme.radius.lg
        , Ui.padding Theme.spacing.xl
        , Ui.spacing Theme.spacing.sm
        , Theme.shadowXl
        ]
        [ Ui.el
            [ Ui.Font.size Theme.font.sm
            , Ui.Font.weight Theme.fontWeight.semibold
            , Ui.Font.letterSpacing Theme.letterSpacing.wide
            , Ui.Font.color Theme.base.solidStrong
            ]
            (Ui.text (T.balanceYourBalance i18n))
        , Ui.el
            [ Ui.Font.size Theme.font.xxl
            , Ui.Font.weight Theme.fontWeight.bold
            , Ui.Font.letterSpacing Theme.letterSpacing.tight
            , Ui.Font.color amountColor
            ]
            (Ui.text amountText)
        , Ui.el
            [ Ui.Font.size Theme.font.sm
            , Ui.Font.color Theme.base.bgSubtle
            ]
            (Ui.text detailText)
        ]



-- OTHER MEMBERS SECTION


otherMembersSection : I18n -> Config msg -> Maybe Member.Id -> Maybe Member.Id -> GroupState -> Ui.Element msg
otherMembersSection i18n config expandedMember maybeUserRootId state =
    let
        balances : List MemberBalance
        balances =
            (case maybeUserRootId of
                Just uid ->
                    Dict.remove uid state.balances

                Nothing ->
                    state.balances
            )
                |> Dict.values
                |> List.sortBy (\b -> resolveName b.memberRootId)

        resolveName : Member.Id -> String
        resolveName =
            GroupState.resolveMemberName state
    in
    if List.isEmpty balances then
        Ui.none

    else
        Ui.column []
            [ UI.Components.sectionLabel (T.membersTabTitle i18n)
            , Ui.column [ Ui.spacing Theme.spacing.xs ]
                (List.map (memberBalanceCard i18n config (maybeUserRootId /= Nothing) resolveName expandedMember) balances)
            ]


memberBalanceCard : I18n -> Config msg -> Bool -> (Member.Id -> String) -> Maybe Member.Id -> MemberBalance -> Ui.Element msg
memberBalanceCard i18n config isMember resolveName expandedMember b =
    let
        name : String
        name =
            resolveName b.memberRootId

        balanceStatus : Balance.Status
        balanceStatus =
            Balance.status b

        isExpanded : Bool
        isExpanded =
            expandedMember == Just b.memberRootId

        statusText : String
        statusText =
            case balanceStatus of
                Balance.Creditor ->
                    T.balanceIsOwed i18n

                Balance.Debtor ->
                    T.balanceOwes i18n

                Balance.Settled ->
                    T.balanceSettled i18n

        amountColor : Ui.Color
        amountColor =
            case balanceStatus of
                Balance.Creditor ->
                    Theme.success.text

                Balance.Debtor ->
                    Theme.danger.text

                Balance.Settled ->
                    Theme.base.textSubtle

        avatarColor : UI.Components.AvatarColor
        avatarColor =
            case balanceStatus of
                Balance.Creditor ->
                    UI.Components.AvatarRed

                Balance.Debtor ->
                    UI.Components.AvatarAccent

                Balance.Settled ->
                    UI.Components.AvatarNeutral

        initials : String
        initials =
            String.left 2 (String.toUpper name)
    in
    UI.Components.card
        [ Ui.Input.button (config.toMsg (ToggleMember b.memberRootId))
        , Ui.paddingXY Theme.spacing.lg Theme.spacing.md
        , Ui.pointer
        , Ui.spacing Theme.spacing.md
        ]
        [ Ui.row [ Ui.width Ui.fill, Ui.contentCenterY ]
            [ Ui.row [ Ui.spacing Theme.spacing.md, Ui.contentCenterY ]
                [ UI.Components.avatar avatarColor initials
                , Ui.column [ Ui.spacing Theme.spacing.xs ]
                    [ Ui.el
                        [ Ui.Font.weight Theme.fontWeight.semibold
                        , Ui.Font.size Theme.font.md
                        ]
                        (Ui.text name)
                    , Ui.el
                        [ Ui.Font.size Theme.font.sm
                        , Ui.Font.color Theme.base.textSubtle
                        ]
                        (Ui.text statusText)
                    ]
                ]
            , Ui.el
                [ Ui.alignRight
                , Ui.Font.size Theme.font.md
                , Ui.Font.weight Theme.fontWeight.semibold
                , Ui.Font.color amountColor
                ]
                (Ui.text
                    ((case balanceStatus of
                        Balance.Creditor ->
                            "+"

                        Balance.Debtor ->
                            "-"

                        Balance.Settled ->
                            ""
                     )
                        ++ Format.formatCents (abs b.netBalance)
                    )
                )
            ]
        , if isExpanded && isMember then
            transferActionBtn i18n
                config.newTransferHref
                (config.onNewTransfer { toMemberId = b.memberRootId, amountCents = abs b.netBalance })

          else
            Ui.none
        ]


transferActionBtn : I18n -> String -> msg -> Ui.Element msg
transferActionBtn i18n href onPress =
    Ui.row
        (Ui.width Ui.fill
            :: Ui.spacing Theme.spacing.xs
            :: Ui.contentCenterX
            :: Ui.contentCenterY
            :: Ui.paddingXY Theme.spacing.md Theme.spacing.sm
            :: Ui.border Theme.border
            :: Ui.borderColor Theme.base.accent
            :: Ui.rounded Theme.radius.sm
            :: Ui.background Theme.base.bgSubtle
            :: Ui.Font.size Theme.font.sm
            :: Ui.Font.weight Theme.fontWeight.medium
            :: Ui.Font.color Theme.primary.text
            :: Ui.pointer
            :: UI.Components.spaLinkAttrs href onPress
        )
        [ Ui.text (T.balanceNewTransfer i18n) ]



-- SETTLEMENT SECTION


settlementSection : I18n -> Config msg -> Maybe Member.Id -> Maybe Int -> GroupState -> Ui.Element msg
settlementSection i18n config maybeUserRootId selectedSettlement state =
    let
        transactions : List Settlement.Transaction
        transactions =
            Settlement.computeSettlement state.balances state.settlementPreferences
    in
    if List.isEmpty transactions then
        Ui.none

    else
        let
            resolveName : Member.Id -> String
            resolveName =
                GroupState.resolveMemberName state

            settlementRow : Int -> Settlement.Transaction -> List (Ui.Element msg)
            settlementRow idx tx =
                let
                    isSelected : Bool
                    isSelected =
                        selectedSettlement == Just idx
                in
                settlementItem i18n config resolveName maybeUserRootId (idx > 0) isSelected idx tx state
        in
        Ui.column []
            [ UI.Components.sectionLabel (T.balanceSettlementPlan i18n)
            , UI.Components.card [ Ui.clip ]
                (List.concat (List.indexedMap settlementRow transactions))
            ]


settlementItem : I18n -> Config msg -> (Member.Id -> String) -> Maybe Member.Id -> Bool -> Bool -> Int -> Settlement.Transaction -> GroupState -> List (Ui.Element msg)
settlementItem i18n config resolveName maybeUserRootId showTopBorder isSelected idx t state =
    let
        isCurrentUser : Bool
        isCurrentUser =
            case maybeUserRootId of
                Just uid ->
                    t.from == uid || t.to == uid

                Nothing ->
                    False

        ( bgColor, textColor, amountColor ) =
            if isCurrentUser then
                ( Ui.background Theme.base.text
                , Ui.Font.color Theme.base.solidText
                , Ui.Font.color Theme.base.solidText
                )

            else
                ( Ui.noAttr, Ui.noAttr, Ui.noAttr )

        ( topBorder, borderColor ) =
            if showTopBorder then
                ( Ui.borderWith { top = Theme.border, bottom = 0, left = 0, right = 0 }
                , Ui.borderColor Theme.base.accent
                )

            else
                ( Ui.noAttr, Ui.noAttr )

        headerRow : Ui.Element msg
        headerRow =
            Ui.row
                [ Ui.Input.button (config.toMsg (ToggleSettlement idx))
                , Ui.paddingXY Theme.spacing.lg Theme.spacing.md
                , Ui.pointer
                , Ui.contentCenterY
                , topBorder
                , borderColor
                , bgColor
                , textColor
                ]
                [ Ui.row [ Ui.spacing Theme.spacing.sm, Ui.Font.size Theme.font.md, Ui.contentCenterY, Ui.width Ui.shrink ]
                    [ Ui.el [ Ui.Font.weight Theme.fontWeight.semibold ] (Ui.text (resolveName t.from))
                    , Ui.el [ Ui.Font.color Theme.base.textSubtle ] (Ui.text "→")
                    , Ui.el [ Ui.Font.weight Theme.fontWeight.semibold ] (Ui.text (resolveName t.to))
                    ]
                , Ui.el
                    [ Ui.alignRight
                    , Ui.Font.weight Theme.fontWeight.semibold
                    , amountColor
                    ]
                    (Ui.text (Format.formatCents t.amount))
                ]
    in
    if isSelected then
        [ headerRow
        , settlementDetail i18n config (maybeUserRootId /= Nothing) resolveName t state
        ]

    else
        [ headerRow ]


settlementDetail : I18n -> Config msg -> Bool -> (Member.Id -> String) -> Settlement.Transaction -> GroupState -> Ui.Element msg
settlementDetail i18n config isMember resolveName t state =
    let
        recipientMetadata : Maybe Member.Metadata
        recipientMetadata =
            Dict.get t.to state.members
                |> Maybe.map .metadata

        paymentMethodRows : List (Ui.Element msg)
        paymentMethodRows =
            case recipientMetadata |> Maybe.andThen .payment of
                Just payment ->
                    List.filterMap identity
                        [ Maybe.map (\v -> paymentRow FeatherIcons.creditCard (T.memberMetadataIban i18n) v Nothing) payment.iban
                        , Maybe.map (\v -> paymentRow FeatherIcons.smartphone (T.memberMetadataWero i18n) v Nothing) payment.wero
                        , Maybe.map (\v -> paymentRow FeatherIcons.dollarSign (T.memberMetadataLydia i18n) v (Just (normalizeHandle "https://pay.lydia.me/l?t=" v))) payment.lydia
                        , Maybe.map (\v -> paymentRow FeatherIcons.dollarSign (T.memberMetadataRevolut i18n) v (Just (normalizeHandle "https://revolut.me/" v))) payment.revolut
                        , Maybe.map (\v -> paymentRow FeatherIcons.dollarSign (T.memberMetadataPaypal i18n) v (Just (normalizeHandle "https://paypal.me/" v))) payment.paypal
                        , Maybe.map (\v -> paymentRow FeatherIcons.dollarSign (T.memberMetadataVenmo i18n) v (Just (normalizeHandle "https://venmo.com/" v))) payment.venmo
                        , Maybe.map (\v -> paymentRow FeatherIcons.key (T.memberMetadataBtc i18n) v (Just ("bitcoin:" ++ v))) payment.btcAddress
                        , Maybe.map (\v -> paymentRow FeatherIcons.key (T.memberMetadataAda i18n) v Nothing) payment.adaAddress
                        ]

                Nothing ->
                    []
    in
    Ui.column
        [ Ui.paddingXY Theme.spacing.lg Theme.spacing.md
        , Ui.spacing Theme.spacing.md
        , Ui.width Ui.fill
        , Ui.borderWith { top = Theme.border, bottom = 0, left = 0, right = 0 }
        , Ui.borderColor Theme.base.accent
        , Ui.background Theme.base.bgSubtle
        ]
        [ if List.isEmpty paymentMethodRows then
            Ui.el
                [ Ui.Font.size Theme.font.sm
                , Ui.Font.color Theme.base.textSubtle
                ]
                (Ui.text (T.settlementNoPaymentMethods (resolveName t.to) i18n))

          else
            Ui.column [ Ui.spacing Theme.spacing.md, Ui.width Ui.fill ] paymentMethodRows
        , if isMember then
            UI.Components.btnPrimary []
                { label = T.settlementRecordTransfer i18n
                , onPress = config.onRecordTransfer t
                }

          else
            Ui.none
        ]


paymentRow : FeatherIcons.Icon -> String -> String -> Maybe String -> Ui.Element msg
paymentRow icon label value maybeUrl =
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



-- SETTLEMENT PREFERENCES


preferencesSection : I18n -> Config msg -> Member.Id -> GroupState -> Ui.Element msg
preferencesSection i18n config currentUserRootId state =
    Ui.column []
        [ UI.Components.sectionLabel (T.settlementPreferencesShow i18n)
        , Ui.el
            [ Ui.Font.size Theme.font.sm
            , Ui.Font.color Theme.base.textSubtle
            ]
            (Ui.text (T.settlementPreferencesHint i18n))
        , preferencesContent currentUserRootId config.onSavePreferences state
        ]


preferencesContent :
    Member.Id
    -> ({ memberRootId : Member.Id, preferredRecipients : List Member.Id } -> msg)
    -> GroupState
    -> Ui.Element msg
preferencesContent currentUserRootId onSavePreferences state =
    let
        otherMembers : List ( Member.Id, String )
        otherMembers =
            Dict.remove currentUserRootId state.members
                |> Dict.values
                |> List.sortBy .name
                |> List.map (\m -> ( m.rootId, m.name ))

        preferredRecipients : List Member.Id
        preferredRecipients =
            List.Extra.find (\pref -> pref.memberRootId == currentUserRootId) state.settlementPreferences
                |> Maybe.map (\pref -> pref.preferredRecipients)
                |> Maybe.withDefault []

        selectCreditor : Member.Id -> msg
        selectCreditor creditorId =
            -- For now, we only allow at most 1 preferred recipient
            if preferredRecipients == [ creditorId ] then
                onSavePreferences { memberRootId = currentUserRootId, preferredRecipients = [] }

            else
                onSavePreferences { memberRootId = currentUserRootId, preferredRecipients = [ creditorId ] }
    in
    Ui.column [ Ui.paddingTop Theme.spacing.md, Ui.spacing Theme.spacing.xs ]
        [ Ui.row [ Ui.wrap, Ui.spacing Theme.spacing.xs ]
            (List.map
                (\( creditorId, creditorName ) ->
                    UI.Components.toggleMemberBtn
                        { name = creditorName
                        , initials = String.left 2 (String.toUpper creditorName)
                        , selected = List.member creditorId preferredRecipients
                        , onPress = selectCreditor creditorId
                        }
                )
                otherMembers
            )
        ]
