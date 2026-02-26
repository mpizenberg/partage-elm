module UI.Components exposing (balanceCard, entryCard, memberRow, settlementRow)

{-| Reusable view components for group data display.
-}

import Domain.Balance as Balance exposing (MemberBalance)
import Domain.Entry as Entry exposing (Entry, Kind(..))
import Domain.GroupState as GroupState
import Domain.Member as Member
import Domain.Settlement as Settlement
import Format
import UI.Theme as Theme
import Ui
import Ui.Font


{-| A card showing a member's balance with color coding.
-}
balanceCard : { name : String, balance : MemberBalance, isCurrentUser : Bool } -> Ui.Element msg
balanceCard config =
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
            case balanceStatus of
                Balance.Creditor ->
                    "is owed"

                Balance.Debtor ->
                    "owes"

                Balance.Settled ->
                    "settled"

        nameLabel =
            if config.isCurrentUser then
                config.name ++ " (you)"

            else
                config.name
    in
    Ui.column
        [ Ui.width Ui.fill
        , Ui.background bgColor
        , Ui.rounded 8
        , Ui.padding Theme.spacing.md
        , Ui.spacing Theme.spacing.xs
        ]
        [ Ui.row [ Ui.width Ui.fill, Ui.spacing Theme.spacing.sm ]
            [ Ui.el [ Ui.Font.bold, Ui.Font.size 16 ] (Ui.text nameLabel)
            , Ui.el [ Ui.alignRight, Ui.Font.color fgColor, Ui.Font.bold, Ui.Font.size 18 ]
                (Ui.text (Format.formatCents (abs config.balance.netBalance)))
            ]
        , Ui.el [ Ui.Font.size 13, Ui.Font.color Theme.neutral700 ]
            (Ui.text statusText)
        ]


{-| A card displaying an entry (expense or transfer).
-}
entryCard : { entry : Entry, resolveName : Member.Id -> String } -> Ui.Element msg
entryCard config =
    case config.entry.kind of
        Expense data ->
            Ui.row
                [ Ui.width Ui.fill
                , Ui.padding Theme.spacing.md
                , Ui.borderWith { bottom = 1, top = 0, left = 0, right = 0 }
                , Ui.borderColor Theme.neutral200
                , Ui.spacing Theme.spacing.md
                ]
                [ Ui.column [ Ui.width Ui.fill, Ui.spacing Theme.spacing.xs ]
                    [ Ui.el [ Ui.Font.bold ] (Ui.text data.description)
                    , Ui.el [ Ui.Font.size 13, Ui.Font.color Theme.neutral500 ]
                        (Ui.text (payerSummary config.resolveName data.payers))
                    ]
                , Ui.el [ Ui.alignRight, Ui.Font.bold ]
                    (Ui.text (Format.formatCentsWithCurrency data.amount data.currency))
                ]

        Transfer data ->
            Ui.row
                [ Ui.width Ui.fill
                , Ui.padding Theme.spacing.md
                , Ui.borderWith { bottom = 1, top = 0, left = 0, right = 0 }
                , Ui.borderColor Theme.neutral200
                , Ui.spacing Theme.spacing.md
                ]
                [ Ui.column [ Ui.width Ui.fill, Ui.spacing Theme.spacing.xs ]
                    [ Ui.el [ Ui.Font.bold ] (Ui.text "Transfer")
                    , Ui.el [ Ui.Font.size 13, Ui.Font.color Theme.neutral500 ]
                        (Ui.text (config.resolveName data.from ++ " -> " ++ config.resolveName data.to))
                    ]
                , Ui.el [ Ui.alignRight, Ui.Font.bold ]
                    (Ui.text (Format.formatCentsWithCurrency data.amount data.currency))
                ]


payerSummary : (Member.Id -> String) -> List Entry.Payer -> String
payerSummary resolveName payers =
    case payers of
        [] ->
            ""

        [ single ] ->
            "Paid by " ++ resolveName single.memberId

        multiple ->
            "Paid by " ++ String.join ", " (List.map (.memberId >> resolveName) multiple)


{-| A row displaying a member in the member list.
-}
memberRow : { member : GroupState.MemberState, isCurrentUser : Bool } -> Ui.Element msg
memberRow config =
    let
        nameLabel =
            if config.isCurrentUser then
                config.member.name ++ " (you)"

            else
                config.member.name

        typeLabel =
            case config.member.memberType of
                Member.Virtual ->
                    " - virtual"

                Member.Real ->
                    ""
    in
    Ui.row
        [ Ui.width Ui.fill
        , Ui.padding Theme.spacing.md
        , Ui.borderWith { bottom = 1, top = 0, left = 0, right = 0 }
        , Ui.borderColor Theme.neutral200
        , Ui.spacing Theme.spacing.sm
        ]
        [ Ui.el [ Ui.Font.size 16 ] (Ui.text nameLabel)
        , Ui.el [ Ui.Font.size 13, Ui.Font.color Theme.neutral500 ] (Ui.text typeLabel)
        ]


{-| A row displaying a settlement transaction.
-}
settlementRow : { transaction : Settlement.Transaction, resolveName : Member.Id -> String } -> Ui.Element msg
settlementRow config =
    let
        t =
            config.transaction
    in
    Ui.row
        [ Ui.width Ui.fill
        , Ui.padding Theme.spacing.sm
        , Ui.spacing Theme.spacing.sm
        , Ui.background Theme.neutral200
        , Ui.rounded 6
        ]
        [ Ui.el [ Ui.Font.size 14 ]
            (Ui.text (config.resolveName t.from))
        , Ui.el [ Ui.Font.size 14, Ui.Font.color Theme.neutral500 ]
            (Ui.text "pays")
        , Ui.el [ Ui.Font.size 14 ]
            (Ui.text (config.resolveName t.to))
        , Ui.el [ Ui.alignRight, Ui.Font.bold, Ui.Font.size 14 ]
            (Ui.text (Format.formatCents t.amount))
        ]
