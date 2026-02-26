module UI.Components exposing (balanceCard, entryCard, memberRow, settlementRow)

{-| Reusable view components for group data display.
-}

import Domain.Balance as Balance exposing (MemberBalance)
import Domain.Entry as Entry exposing (Entry, Kind(..))
import Domain.GroupState as GroupState
import Domain.Member as Member
import Domain.Settlement as Settlement
import Format
import Translations as T exposing (I18n)
import UI.Theme as Theme
import Ui
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


{-| A card displaying an entry (expense or transfer).
-}
entryCard : I18n -> { entry : Entry, resolveName : Member.Id -> String } -> Ui.Element msg
entryCard i18n config =
    case config.entry.kind of
        Expense data ->
            Ui.row
                [ Ui.width Ui.fill
                , Ui.padding Theme.spacing.md
                , Ui.borderWith { bottom = Theme.borderWidth.sm, top = 0, left = 0, right = 0 }
                , Ui.borderColor Theme.neutral200
                , Ui.spacing Theme.spacing.md
                ]
                [ Ui.column [ Ui.width Ui.fill, Ui.spacing Theme.spacing.xs ]
                    [ Ui.el [ Ui.Font.bold ] (Ui.text data.description)
                    , Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ]
                        (Ui.text (payerSummary i18n config.resolveName data.payers))
                    ]
                , Ui.el [ Ui.alignRight, Ui.Font.bold ]
                    (Ui.text (Format.formatCentsWithCurrency data.amount data.currency))
                ]

        Transfer data ->
            Ui.row
                [ Ui.width Ui.fill
                , Ui.padding Theme.spacing.md
                , Ui.borderWith { bottom = Theme.borderWidth.sm, top = 0, left = 0, right = 0 }
                , Ui.borderColor Theme.neutral200
                , Ui.spacing Theme.spacing.md
                ]
                [ Ui.column [ Ui.width Ui.fill, Ui.spacing Theme.spacing.xs ]
                    [ Ui.el [ Ui.Font.bold ] (Ui.text (T.entryTransfer i18n))
                    , Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ]
                        (Ui.text (T.entryTransferDirection { from = config.resolveName data.from, to = config.resolveName data.to } i18n))
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


{-| A row displaying a member in the member list.
-}
memberRow : I18n -> { member : GroupState.MemberState, isCurrentUser : Bool } -> Ui.Element msg
memberRow i18n config =
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
        ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.md ] (Ui.text nameLabel)
        , Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ] (Ui.text typeLabel)
        ]


{-| A row displaying a settlement transaction.
-}
settlementRow : I18n -> { transaction : Settlement.Transaction, resolveName : Member.Id -> String } -> Ui.Element msg
settlementRow i18n config =
    let
        t =
            config.transaction
    in
    Ui.row
        [ Ui.width Ui.fill
        , Ui.padding Theme.spacing.sm
        , Ui.spacing Theme.spacing.sm
        , Ui.background Theme.neutral200
        , Ui.rounded Theme.rounding.sm
        ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.sm ]
            (Ui.text (config.resolveName t.from))
        , Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ]
            (Ui.text (T.settlementPays i18n))
        , Ui.el [ Ui.Font.size Theme.fontSize.sm ]
            (Ui.text (config.resolveName t.to))
        , Ui.el [ Ui.alignRight, Ui.Font.bold, Ui.Font.size Theme.fontSize.sm ]
            (Ui.text (Format.formatCents t.amount))
        ]
