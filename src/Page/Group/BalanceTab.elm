module Page.Group.BalanceTab exposing (Config, Model, Msg, init, update, view)

{-| Balance tab showing per-member balances and settlement plan.
-}

import Dict
import Domain.Balance as Balance exposing (MemberBalance)
import Domain.GroupState as GroupState exposing (GroupState)
import Domain.Member as Member
import Domain.Settlement as Settlement
import Translations as T exposing (I18n)
import UI.Components
import UI.Theme as Theme
import Ui
import Ui.Events
import Ui.Font


type Model
    = Model
        { showPreferences : Bool
        }


type Msg
    = ToggleShowPreferences


init : Model
init =
    Model { showPreferences = False }


update : Msg -> Model -> Model
update msg (Model data) =
    case msg of
        ToggleShowPreferences ->
            Model { data | showPreferences = not data.showPreferences }


{-| Configuration for callbacks used by the balance tab.
-}
type alias Config msg =
    { onSettle : Settlement.Transaction -> msg
    , onPayMember : { toMemberId : Member.Id, amountCents : Int } -> msg
    , onSavePreferences : { memberRootId : Member.Id, preferredRecipients : List Member.Id } -> msg
    , toMsg : Msg -> msg
    }


{-| Render the balance tab with per-member balances and a settlement plan.
-}
view : I18n -> Config msg -> Member.Id -> Model -> GroupState -> Ui.Element msg
view i18n config currentUserRootId (Model data) state =
    if Dict.isEmpty state.entries then
        Ui.column [ Ui.spacing Theme.spacing.lg, Ui.width Ui.fill ]
            [ Ui.el [ Ui.Font.size Theme.fontSize.lg, Ui.Font.bold ] (Ui.text (T.balanceTabTitle i18n))
            , Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ]
                (Ui.text (T.balanceNoEntries i18n))
            ]

    else
        Ui.column [ Ui.spacing Theme.spacing.lg, Ui.width Ui.fill ]
            [ balancesSection i18n config.onPayMember currentUserRootId state
            , settlementSection i18n config.onSettle currentUserRootId state
            , preferencesSection i18n config data.showPreferences currentUserRootId state
            ]


balancesSection : I18n -> ({ toMemberId : Member.Id, amountCents : Int } -> msg) -> Member.Id -> GroupState -> Ui.Element msg
balancesSection i18n onPayMember currentUserRootId state =
    let
        resolveName : Member.Id -> String
        resolveName =
            GroupState.resolveMemberName state

        balances : List MemberBalance
        balances =
            Dict.values state.balances

        -- Current user first, then sorted by name
        sorted : List MemberBalance
        sorted =
            balances
                |> List.sortBy (\b -> ( boolToInt (b.memberRootId /= currentUserRootId), resolveName b.memberRootId ))

        boolToInt : Bool -> Int
        boolToInt b =
            if b then
                1

            else
                0
    in
    Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.lg, Ui.Font.bold ] (Ui.text (T.balanceTabTitle i18n))
        , Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
            (List.map
                (\b ->
                    let
                        isCurrentUser : Bool
                        isCurrentUser =
                            b.memberRootId == currentUserRootId

                        onPay : Maybe msg
                        onPay =
                            if not isCurrentUser && Balance.status b == Balance.Creditor then
                                Just (onPayMember { toMemberId = b.memberRootId, amountCents = b.netBalance })

                            else
                                Nothing
                    in
                    UI.Components.balanceCard i18n
                        onPay
                        { name = resolveName b.memberRootId
                        , balance = b
                        , isCurrentUser = isCurrentUser
                        }
                )
                sorted
            )
        ]


settlementSection : I18n -> (Settlement.Transaction -> msg) -> Member.Id -> GroupState -> Ui.Element msg
settlementSection i18n onSettle currentUserRootId state =
    let
        transactions : List Settlement.Transaction
        transactions =
            Settlement.computeSettlement state.balances state.settlementPreferences
    in
    Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.lg, Ui.Font.bold ] (Ui.text (T.balanceSettlementPlan i18n))
        , if List.isEmpty transactions then
            Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ]
                (Ui.text (T.balanceAllSettled i18n))

          else
            let
                resolveName : Member.Id -> String
                resolveName =
                    GroupState.resolveMemberName state

                settleTx : Settlement.Transaction -> Ui.Element msg
                settleTx =
                    UI.Components.settlementRow i18n resolveName currentUserRootId onSettle
            in
            Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
                (List.map settleTx transactions)
        ]


preferencesSection : I18n -> Config msg -> Bool -> Member.Id -> GroupState -> Ui.Element msg
preferencesSection i18n config showPreferences currentUserRootId state =
    let
        toggleLabel : String
        toggleLabel =
            if showPreferences then
                T.settlementPreferencesHide i18n

            else
                T.settlementPreferencesShow i18n
    in
    Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
        (Ui.el
            [ Ui.Font.size Theme.fontSize.sm
            , Ui.Font.color Theme.primary
            , Ui.pointer
            , Ui.Events.onClick (config.toMsg ToggleShowPreferences)
            ]
            (Ui.text toggleLabel)
            :: (if showPreferences then
                    [ preferencesContent i18n currentUserRootId config.onSavePreferences state ]

                else
                    []
               )
        )


preferencesContent :
    I18n
    -> Member.Id
    -> ({ memberRootId : Member.Id, preferredRecipients : List Member.Id } -> msg)
    -> GroupState
    -> Ui.Element msg
preferencesContent i18n currentUserRootId onSavePreferences state =
    let
        otherMembers : List ( Member.Id, String )
        otherMembers =
            GroupState.activeMembers state
                |> List.filter (\m -> m.rootId /= currentUserRootId)
                |> List.map (\m -> ( m.rootId, m.name ))
                |> List.sortBy Tuple.second

        currentPref : Maybe Member.Id
        currentPref =
            state.settlementPreferences
                |> List.filter (\p -> p.memberRootId == currentUserRootId)
                |> List.head
                |> Maybe.andThen (.preferredRecipients >> List.head)

        selectCreditor : Member.Id -> msg
        selectCreditor creditorId =
            let
                newPrefs : List Member.Id
                newPrefs =
                    if currentPref == Just creditorId then
                        []

                    else
                        [ creditorId ]
            in
            onSavePreferences { memberRootId = currentUserRootId, preferredRecipients = newPrefs }
    in
    Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ]
            (Ui.text (T.settlementPreferencesHint i18n))
        , Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
            (List.map (preferenceOption currentPref selectCreditor) otherMembers)
        ]


preferenceOption : Maybe Member.Id -> (Member.Id -> msg) -> ( Member.Id, String ) -> Ui.Element msg
preferenceOption currentPref onSelect ( creditorId, creditorName ) =
    let
        isSelected : Bool
        isSelected =
            currentPref == Just creditorId

        bgColor : Ui.Attribute msg
        bgColor =
            if isSelected then
                Ui.background Theme.primaryLight

            else
                Ui.background Theme.white

        borderColor : Ui.Attribute msg
        borderColor =
            if isSelected then
                Ui.borderColor Theme.primary

            else
                Ui.borderColor Theme.neutral300

        indicator : String
        indicator =
            if isSelected then
                "● "

            else
                "○ "
    in
    Ui.el
        [ Ui.paddingXY Theme.spacing.md Theme.spacing.sm
        , Ui.rounded Theme.rounding.sm
        , Ui.border Theme.borderWidth.sm
        , bgColor
        , borderColor
        , Ui.pointer
        , Ui.width Ui.fill
        , Ui.Events.onClick (onSelect creditorId)
        ]
        (Ui.text (indicator ++ creditorName))
