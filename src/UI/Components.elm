module UI.Components exposing (balanceCard, entryCard, languageSelector, memberRow, settlementRow)

{-| Reusable view components for group data display.
-}

import Domain.Balance as Balance exposing (MemberBalance)
import Domain.Entry as Entry exposing (Entry, Kind(..))
import Domain.GroupState as GroupState
import Domain.Member as Member
import Domain.Settlement as Settlement
import Format
import Translations as T exposing (I18n, Language(..))
import UI.Theme as Theme
import Ui
import Ui.Events
import Ui.Font


{-| A card showing a member's balance with color coding.
-}
balanceCard : I18n -> { name : String, balance : MemberBalance, isCurrentUser : Bool } -> Ui.Element msg
balanceCard i18n config =
    let
        balanceStatus =
            Balance.status config.balance

        bgColor =
            case balanceStatus of
                Balance.Creditor ->
                    Theme.successLight

                Balance.Debtor ->
                    Theme.dangerLight

                Balance.Settled ->
                    Theme.neutral200

        fgColor =
            Theme.balanceColor balanceStatus

        statusText =
            case ( balanceStatus, config.isCurrentUser ) of
                ( Balance.Creditor, True ) ->
                    T.balanceIsOwedYou i18n

                ( Balance.Creditor, False ) ->
                    T.balanceIsOwed i18n

                ( Balance.Debtor, True ) ->
                    T.balanceOwesYou i18n

                ( Balance.Debtor, False ) ->
                    T.balanceOwes i18n

                ( Balance.Settled, _ ) ->
                    T.balanceSettled i18n

        nameLabel =
            if config.isCurrentUser then
                T.nameYouSuffix config.name i18n

            else
                config.name
    in
    Ui.column
        [ Ui.width Ui.fill
        , Ui.background bgColor
        , Ui.rounded Theme.rounding.md
        , Ui.padding Theme.spacing.md
        , Ui.spacing Theme.spacing.xs
        ]
        [ Ui.row [ Ui.width Ui.fill, Ui.spacing Theme.spacing.sm ]
            [ Ui.el [ Ui.Font.bold, Ui.Font.size Theme.fontSize.md ] (Ui.text nameLabel)
            , Ui.el [ Ui.alignRight, Ui.Font.color fgColor, Ui.Font.bold, Ui.Font.size Theme.fontSize.lg ]
                (Ui.text (Format.formatCents (abs config.balance.netBalance)))
            ]
        , Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral700 ]
            (Ui.text statusText)
        ]


{-| A card displaying an entry (expense or transfer). Clickable via onClick.
-}
entryCard : I18n -> (Member.Id -> String) -> msg -> Entry -> Ui.Element msg
entryCard i18n resolveName onClick entry =
    let
        rowAttrs =
            [ Ui.width Ui.fill
            , Ui.padding Theme.spacing.md
            , Ui.borderWith { bottom = Theme.borderWidth.sm, top = 0, left = 0, right = 0 }
            , Ui.borderColor Theme.neutral200
            , Ui.spacing Theme.spacing.md
            , Ui.pointer
            , Ui.Events.onClick onClick
            ]
    in
    case entry.kind of
        Expense data ->
            Ui.row rowAttrs
                [ Ui.column [ Ui.width Ui.fill, Ui.spacing Theme.spacing.xs ]
                    [ Ui.el [ Ui.Font.bold ] (Ui.text data.description)
                    , Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ]
                        (Ui.text (payerSummary i18n resolveName data.payers))
                    ]
                , Ui.el [ Ui.alignRight, Ui.Font.bold ]
                    (Ui.text (Format.formatCentsWithCurrency data.amount data.currency))
                ]

        Transfer data ->
            Ui.row rowAttrs
                [ Ui.column [ Ui.width Ui.fill, Ui.spacing Theme.spacing.xs ]
                    [ Ui.el [ Ui.Font.bold ] (Ui.text (T.entryTransfer i18n))
                    , Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ]
                        (Ui.text (T.entryTransferDirection { from = resolveName data.from, to = resolveName data.to } i18n))
                    ]
                , Ui.el [ Ui.alignRight, Ui.Font.bold ]
                    (Ui.text (Format.formatCentsWithCurrency data.amount data.currency))
                ]


payerSummary : I18n -> (Member.Id -> String) -> List Entry.Payer -> String
payerSummary i18n resolveName payers =
    case payers of
        [] ->
            ""

        [ single ] ->
            T.entryPaidBySingle (resolveName single.memberId) i18n

        multiple ->
            T.entryPaidByMultiple (String.join ", " (List.map (.memberId >> resolveName) multiple)) i18n


{-| A row displaying a member in the member list. Clickable via onClick.
-}
memberRow : I18n -> msg -> { member : GroupState.MemberState, isCurrentUser : Bool } -> Ui.Element msg
memberRow i18n onClick config =
    let
        nameLabel =
            if config.isCurrentUser then
                T.nameYouSuffix config.member.name i18n

            else
                config.member.name

        typeLabel =
            case config.member.memberType of
                Member.Virtual ->
                    T.memberVirtualLabel i18n

                Member.Real ->
                    ""
    in
    Ui.row
        [ Ui.width Ui.fill
        , Ui.padding Theme.spacing.md
        , Ui.borderWith { bottom = Theme.borderWidth.sm, top = 0, left = 0, right = 0 }
        , Ui.borderColor Theme.neutral200
        , Ui.spacing Theme.spacing.sm
        , Ui.pointer
        , Ui.Events.onClick onClick
        ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.md ] (Ui.text nameLabel)
        , Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ] (Ui.text typeLabel)
        ]


{-| A row displaying a settlement transaction, with a "Mark as Paid" button
and highlighting when the current user is involved.
-}
settlementRow : I18n -> (Member.Id -> String) -> Member.Id -> (Settlement.Transaction -> msg) -> Settlement.Transaction -> Ui.Element msg
settlementRow i18n resolveName currentUserRootId onSettle t =
    let
        isCurrentUser =
            t.from == currentUserRootId || t.to == currentUserRootId

        bgColor =
            if isCurrentUser then
                Theme.primaryLight

            else
                Theme.neutral200
    in
    Ui.row
        [ Ui.width Ui.fill
        , Ui.padding Theme.spacing.sm
        , Ui.spacing Theme.spacing.sm
        , Ui.background bgColor
        , Ui.rounded Theme.rounding.sm
        ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.sm ]
            (Ui.text (resolveName t.from))
        , Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ]
            (Ui.text (T.settlementPays i18n))
        , Ui.el [ Ui.Font.size Theme.fontSize.sm ]
            (Ui.text (resolveName t.to))
        , Ui.el [ Ui.alignRight, Ui.Font.bold, Ui.Font.size Theme.fontSize.sm ]
            (Ui.text (Format.formatCents t.amount))
        , Ui.el
            [ Ui.Font.size Theme.fontSize.sm
            , Ui.Font.color Theme.white
            , Ui.background Theme.primary
            , Ui.rounded Theme.rounding.sm
            , Ui.paddingXY Theme.spacing.sm Theme.spacing.xs
            , Ui.pointer
            , Ui.Events.onClick (onSettle t)
            ]
            (Ui.text (T.settlementMarkAsPaid i18n))
        ]


{-| Flag-based language selector. Active language is full opacity, others dimmed.
-}
languageSelector : (Language -> msg) -> Language -> Ui.Element msg
languageSelector onSwitch current =
    Ui.row [ Ui.spacing Theme.spacing.xs ]
        (List.map
            (\lang ->
                Ui.el
                    [ Ui.pointer
                    , Ui.Font.size Theme.fontSize.lg
                    , Ui.Events.onClick (onSwitch lang)
                    , if lang == current then
                        Ui.opacity 1.0

                      else
                        Ui.opacity 0.5
                    ]
                    (Ui.text (languageFlag lang))
            )
            T.languages
        )


languageFlag : Language -> String
languageFlag lang =
    case lang of
        En ->
            "🇬🇧"

        Fr ->
            "🇫🇷"
