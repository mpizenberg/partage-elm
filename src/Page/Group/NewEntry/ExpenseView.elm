module Page.Group.NewEntry.ExpenseView exposing (expenseFields)

{-| Expense-specific view functions for the new entry form.
-}

import Dict
import Domain.Currency as Currency
import Domain.Entry as Entry
import Domain.Member as Member
import FeatherIcons
import Field
import Form
import Format
import Page.Group.NewEntry.Shared as Shared exposing (ModelData, Msg(..), SplitMode(..))
import Translations as T exposing (I18n)
import UI.Components
import UI.Theme as Theme
import Ui
import Ui.Font
import Ui.Input


expenseFields : I18n -> List Member.ChainState -> ModelData -> List (Ui.Element Msg)
expenseFields i18n activeMembers data =
    [ descriptionField i18n data
    , Shared.amountCurrencyField i18n data
    , Shared.defaultCurrencyAmountField i18n data
    , Shared.dateField i18n data
    , payerField i18n activeMembers data
    , beneficiariesField i18n activeMembers data
    , categoryField i18n data
    , Shared.notesField i18n data
    ]


descriptionField : I18n -> ModelData -> Ui.Element Msg
descriptionField i18n data =
    let
        field : Field.Field String
        field =
            Form.get .description data.form
    in
    Shared.formField { label = T.newEntryDescriptionLabel i18n, required = True }
        [ Ui.Input.text [ Ui.width Ui.fill ]
            { onChange = InputDescription
            , text = Field.toRawString field
            , placeholder = Just (T.newEntryDescriptionPlaceholder i18n)
            , label = Ui.Input.labelHidden (T.newEntryDescriptionLabel i18n)
            }
        , Shared.formHint (T.newEntryDescriptionHint i18n)
        , Shared.fieldError i18n data.submitted field
        ]


payerField : I18n -> List Member.ChainState -> ModelData -> Ui.Element Msg
payerField i18n activeMembers data =
    let
        isMultiPayer : Bool
        isMultiPayer =
            Dict.size data.payerAmounts > 1

        payerAmountRows : List (Ui.Element Msg)
        payerAmountRows =
            if isMultiPayer then
                let
                    payerMismatchError : Ui.Element Msg
                    payerMismatchError =
                        let
                            totalPayer : Int
                            totalPayer =
                                Dict.values data.payerAmounts
                                    |> List.filterMap Shared.parseAmountCents
                                    |> List.sum

                            totalAmount : Int
                            totalAmount =
                                Form.get .amount data.form |> Field.toMaybe |> Maybe.withDefault 0
                        in
                        Shared.errorWhen (data.submitted && totalPayer /= totalAmount) (T.newEntryPayerMismatch i18n)

                    amountRow : Member.ChainState -> Ui.Element Msg
                    amountRow member =
                        Ui.row [ Ui.spacing Theme.spacing.sm, Ui.contentCenterY ]
                            [ Ui.el [ Ui.alignRight ] (Ui.text member.name)
                            , Ui.Input.text [ Ui.width (Ui.px 100) ]
                                { onChange = InputPayerAmount member.rootId
                                , text = Maybe.withDefault "" (Dict.get member.rootId data.payerAmounts)
                                , placeholder = Just "0.00"
                                , label = Ui.Input.labelHidden member.name
                                }
                            , Ui.text <| "(" ++ Currency.currencySymbol data.currency ++ ")"
                            ]
                in
                List.filterMap
                    (\member ->
                        if Dict.member member.rootId data.payerAmounts then
                            Just (amountRow member)

                        else
                            Nothing
                    )
                    activeMembers
                    ++ [ payerMismatchError ]

            else
                []
    in
    Shared.formField { label = T.newEntryPayerLabel i18n, required = True }
        ([ Ui.row [ Ui.spacing Theme.spacing.sm, Ui.wrap ]
            (List.map
                (\member ->
                    UI.Components.toggleMemberBtn
                        { name = member.name
                        , initials = String.left 2 (String.toUpper member.name)
                        , selected = Dict.member member.rootId data.payerAmounts
                        , onPress = TogglePayer member.rootId
                        }
                )
                activeMembers
            )
         , Shared.errorWhen (data.submitted && Dict.isEmpty data.payerAmounts) (T.newEntryNoPayerError i18n)
         ]
            ++ payerAmountRows
        )


beneficiariesField : I18n -> List Member.ChainState -> ModelData -> Ui.Element Msg
beneficiariesField i18n activeMembers data =
    let
        exactMismatchError : Ui.Element Msg
        exactMismatchError =
            case data.splitMode of
                ExactSplit ->
                    let
                        totalExact : Int
                        totalExact =
                            Dict.keys data.beneficiaries
                                |> List.filterMap (\mid -> Dict.get mid data.exactAmounts |> Maybe.andThen Shared.parseAmountCents)
                                |> List.sum

                        totalAmount : Int
                        totalAmount =
                            Form.get .amount data.form |> Field.toMaybe |> Maybe.withDefault 0
                    in
                    Shared.errorWhen (data.submitted && totalExact /= totalAmount) (T.newEntryExactMismatch i18n)

                ShareSplit ->
                    Ui.none

        headerRow : Ui.Element Msg
        headerRow =
            Ui.row [ Ui.width Ui.fill, Ui.contentCenterY ]
                [ Shared.fieldTitle (T.newEntryBeneficiariesLabel i18n) True
                , Ui.row [ Ui.alignRight, Ui.spacing Theme.spacing.sm, Ui.contentCenterY ]
                    [ Ui.el
                        [ Ui.Font.size Theme.font.sm
                        , Ui.Font.color Theme.base.textSubtle
                        ]
                        (Ui.text (T.newEntrySplitExact i18n))
                    , UI.Components.toggle
                        { isOn = data.splitMode == ExactSplit
                        , onPress = InputSplitMode (toggleSplitMode data.splitMode)
                        }
                    ]
                ]
    in
    Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
        [ headerRow
        , Shared.formHint (T.newEntryBeneficiariesHint i18n)
        , Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
            (List.map (beneficiaryRow data) activeMembers)
        , Shared.errorWhen (data.submitted && Dict.isEmpty data.beneficiaries) (T.newEntryNoBeneficiaries i18n)
        , exactMismatchError
        ]


toggleSplitMode : SplitMode -> SplitMode
toggleSplitMode mode =
    case mode of
        ShareSplit ->
            ExactSplit

        ExactSplit ->
            ShareSplit


beneficiaryRow : ModelData -> Member.ChainState -> Ui.Element Msg
beneficiaryRow data member =
    let
        isSelected : Bool
        isSelected =
            Dict.member member.rootId data.beneficiaries

        shares : Int
        shares =
            Dict.get member.rootId data.beneficiaries |> Maybe.withDefault 0

        totalShares : Int
        totalShares =
            Dict.values data.beneficiaries |> List.sum

        splitAmount : Ui.Element Msg
        splitAmount =
            if not isSelected || totalShares == 0 then
                Ui.none

            else
                case data.splitMode of
                    ShareSplit ->
                        let
                            totalAmountCents : Int
                            totalAmountCents =
                                Form.get .amount data.form |> Field.toMaybe |> Maybe.withDefault 0

                            cents : Int
                            cents =
                                (totalAmountCents * shares) // totalShares
                        in
                        Ui.el
                            [ Ui.Font.size Theme.font.sm
                            , Ui.Font.color Theme.base.textSubtle
                            ]
                            (Ui.text (Format.formatCentsWithCurrency cents data.currency))

                    ExactSplit ->
                        Ui.none

        rightControl : Ui.Element Msg
        rightControl =
            case data.splitMode of
                ShareSplit ->
                    shareStepper member.rootId shares

                ExactSplit ->
                    if isSelected then
                        Ui.row [ Ui.spacing Theme.spacing.xs, Ui.contentCenterY ]
                            [ Ui.Input.text [ Ui.width (Ui.px 100) ]
                                { onChange = InputExactAmount member.rootId
                                , text = Maybe.withDefault "" (Dict.get member.rootId data.exactAmounts)
                                , placeholder = Just "0.00"
                                , label = Ui.Input.labelHidden member.name
                                }
                            , Ui.el [ Ui.Font.size Theme.font.sm, Ui.Font.color Theme.base.textSubtle ]
                                (Ui.text (Currency.currencySymbol data.currency))
                            ]

                    else
                        Ui.none
    in
    Ui.row [ Ui.width Ui.fill, Ui.spacing Theme.spacing.sm, Ui.contentCenterY ]
        [ UI.Components.toggleMemberBtn
            { name = member.name
            , initials = String.left 2 (String.toUpper member.name)
            , selected = isSelected
            , onPress = ToggleBeneficiary member.rootId
            }
        , splitAmount
        , Ui.el [ Ui.alignRight ] rightControl
        ]


shareStepper : Member.Id -> Int -> Ui.Element Msg
shareStepper memberId shares =
    Ui.row
        [ Ui.spacing Theme.spacing.xs
        , Ui.contentCenterY
        , Ui.rounded Theme.radius.md
        , Ui.border Theme.border
        , Ui.borderColor Theme.base.accent
        , Ui.paddingXY Theme.spacing.xs 0
        ]
        [ stepperBtn (DecrementShares memberId) FeatherIcons.minus (shares > 0)
        , Ui.el
            [ Ui.Font.center
            , Ui.Font.weight Theme.fontWeight.semibold
            , Ui.widthMin Theme.sizing.xs
            ]
            (Ui.text (String.fromInt shares))
        , stepperBtn (IncrementShares memberId) FeatherIcons.plus True
        ]


stepperBtn : msg -> FeatherIcons.Icon -> Bool -> Ui.Element msg
stepperBtn onPress icon enabled =
    Ui.el
        (Ui.width (Ui.px Theme.sizing.md)
            :: Ui.height (Ui.px Theme.sizing.md)
            :: Ui.contentCenterX
            :: Ui.contentCenterY
            :: (if enabled then
                    [ Ui.Input.button onPress
                    , Ui.pointer
                    , Ui.Font.color Theme.base.text
                    ]

                else
                    [ Ui.Font.color Theme.base.accent ]
               )
        )
        (UI.Components.featherIcon (toFloat Theme.sizing.xs) icon)


categoryField : I18n -> ModelData -> Ui.Element Msg
categoryField i18n data =
    Shared.formField { label = T.newEntryCategoryLabel i18n, required = False }
        [ Ui.row [ Ui.spacing Theme.spacing.xs, Ui.wrap ]
            (List.map
                (\( cat, label ) ->
                    UI.Components.chip
                        { label = label
                        , selected = data.category == cat
                        , onPress = InputCategory cat
                        }
                )
                [ ( Nothing, T.newEntryCategoryNone i18n )
                , ( Just Entry.Food, "🍽️ " ++ T.categoryFood i18n )
                , ( Just Entry.Transport, "🚗 " ++ T.categoryTransport i18n )
                , ( Just Entry.Accommodation, "🏠 " ++ T.categoryAccommodation i18n )
                , ( Just Entry.Entertainment, "🎭 " ++ T.categoryEntertainment i18n )
                , ( Just Entry.Shopping, "🛍️ " ++ T.categoryShopping i18n )
                , ( Just Entry.Groceries, "🛒 " ++ T.categoryGroceries i18n )
                , ( Just Entry.Utilities, "⚡ " ++ T.categoryUtilities i18n )
                , ( Just Entry.Healthcare, "💊 " ++ T.categoryHealthcare i18n )
                , ( Just Entry.Other, "📦 " ++ T.categoryOther i18n )
                ]
            )
        ]
