module Page.Group.BalanceTab exposing (Config, Model, Msg, init, update, view)

{-| Balance tab showing per-member balances and settlement plan.
-}

import Dict
import Domain.Balance as Balance exposing (MemberBalance)
import Domain.GroupState as GroupState exposing (GroupState)
import Domain.Member as Member
import Domain.Settlement as Settlement
import Format
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
        }


type Msg
    = ToggleMember Member.Id


init : Model
init =
    Model { expandedMember = Nothing }


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


{-| Configuration for callbacks used by the balance tab.
-}
type alias Config msg =
    { onSettle : Settlement.Transaction -> msg
    , onPayMember : { toMemberId : Member.Id, amountCents : Int } -> msg
    , onSavePreferences : { memberRootId : Member.Id, preferredRecipients : List Member.Id } -> msg
    , onNewTransfer : msg
    , toMsg : Msg -> msg
    }


{-| Render the balance tab with per-member balances and a settlement plan.
-}
view : I18n -> Config msg -> Member.Id -> Model -> GroupState -> Ui.Element msg
view i18n config currentUserRootId (Model data) state =
    if Dict.isEmpty state.entries then
        Ui.column [ Ui.spacing Theme.spacing.lg, Ui.width Ui.fill ]
            [ Ui.el [ Ui.Font.size Theme.font.lg, Ui.Font.weight Theme.fontWeight.bold ] (Ui.text (T.balanceTabTitle i18n))
            , Ui.el [ Ui.Font.size Theme.font.sm, Ui.Font.color Theme.base.textSubtle ]
                (Ui.text (T.balanceNoEntries i18n))
            ]

    else
        Ui.column [ Ui.spacing Theme.spacing.lg ]
            [ yourBalanceCard i18n currentUserRootId state
            , otherMembersSection i18n config data.expandedMember currentUserRootId state
            , settlementSection i18n config.onSettle currentUserRootId state
            , preferencesSection i18n config currentUserRootId state
            ]



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


otherMembersSection : I18n -> Config msg -> Maybe Member.Id -> Member.Id -> GroupState -> Ui.Element msg
otherMembersSection i18n config expandedMember currentUserRootId state =
    let
        otherBalances : List MemberBalance
        otherBalances =
            Dict.remove currentUserRootId state.balances
                |> Dict.values
                |> List.sortBy (\b -> resolveName b.memberRootId)

        resolveName : Member.Id -> String
        resolveName =
            GroupState.resolveMemberName state
    in
    if List.isEmpty otherBalances then
        Ui.none

    else
        let
            otherMemberCard : MemberBalance -> Ui.Element msg
            otherMemberCard balance =
                memberBalanceCard i18n config resolveName expandedMember balance
        in
        Ui.column []
            [ UI.Components.sectionLabel (T.membersTabTitle i18n)
            , Ui.column [ Ui.spacing Theme.spacing.xs ]
                (List.map otherMemberCard otherBalances)
            ]


memberBalanceCard : I18n -> Config msg -> (Member.Id -> String) -> Maybe Member.Id -> MemberBalance -> Ui.Element msg
memberBalanceCard i18n config resolveName expandedMember b =
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
        , if isExpanded then
            transferActionBtn config.onNewTransfer

          else
            Ui.none
        ]


transferActionBtn : msg -> Ui.Element msg
transferActionBtn onPress =
    Ui.row
        [ Ui.Input.button onPress
        , Ui.width Ui.fill
        , Ui.spacing Theme.spacing.xs
        , Ui.contentCenterX
        , Ui.contentCenterY
        , Ui.paddingXY Theme.spacing.md Theme.spacing.sm
        , Ui.border Theme.border
        , Ui.borderColor Theme.base.accent
        , Ui.rounded Theme.radius.sm
        , Ui.background Theme.base.bgSubtle
        , Ui.Font.size Theme.font.sm
        , Ui.Font.weight Theme.fontWeight.medium
        , Ui.Font.color Theme.primary.text
        , Ui.pointer
        ]
        [ Ui.text "+ Record new transfer" ]



-- SETTLEMENT SECTION


settlementSection : I18n -> (Settlement.Transaction -> msg) -> Member.Id -> GroupState -> Ui.Element msg
settlementSection i18n onSettle currentUserRootId state =
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

            settlementRow : Int -> Settlement.Transaction -> Ui.Element msg
            settlementRow idx tx =
                -- Show top border (separator) for rows > 0
                settlementItem resolveName currentUserRootId onSettle (idx > 0) tx
        in
        Ui.column []
            [ UI.Components.sectionLabel (T.balanceSettlementPlan i18n)
            , UI.Components.card [ Ui.clip ]
                (List.indexedMap settlementRow transactions)
            ]


settlementItem : (Member.Id -> String) -> Member.Id -> (Settlement.Transaction -> msg) -> Bool -> Settlement.Transaction -> Ui.Element msg
settlementItem resolveName currentUserRootId onSettle showTopBorder t =
    let
        isCurrentUser : Bool
        isCurrentUser =
            t.from == currentUserRootId || t.to == currentUserRootId

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
    in
    Ui.row
        [ Ui.Input.button (onSettle t)
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
