module Page.Group.NewEntry.ExpenseView exposing (expenseFields)

{-| Expense-specific view functions for the new entry form.
-}

import Dict
import Domain.Currency as Currency
import Domain.Entry as Entry
import Domain.Member as Member
import Field
import Form
import Page.Group.NewEntry.Shared as Shared exposing (ModelData, Msg(..))
import Translations as T exposing (I18n)
import UI.Categories as Categories
import UI.Components
import UI.Theme as Theme
import Ui
import Ui.Input


expenseFields : I18n -> List Member.State -> ModelData -> List (Ui.Element Msg)
expenseFields i18n activeMembers data =
    [ descriptionField i18n data
    , Shared.amountCurrencyField i18n data
    , Shared.defaultCurrencyAmountField i18n data
    , Shared.dateField i18n data
    , payerField i18n activeMembers data
    , Shared.beneficiariesField i18n (T.newEntryBeneficiariesHint i18n) activeMembers data
    , categoryField i18n data
    , Shared.notesField i18n data
    , Shared.attachmentsField i18n data
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


payerField : I18n -> List Member.State -> ModelData -> Ui.Element Msg
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
                                    |> List.filterMap (Shared.parseAmountCents data.currency)
                                    |> List.sum

                            totalAmount : Int
                            totalAmount =
                                Form.get .amount data.form |> Field.toMaybe |> Maybe.withDefault 0
                        in
                        Shared.errorWhen (data.submitted && totalPayer /= totalAmount) (T.newEntryPayerMismatch i18n)

                    amountRow : Member.State -> Ui.Element Msg
                    amountRow member =
                        Ui.row [ Ui.spacing Theme.spacing.sm, Ui.contentCenterY ]
                            [ Ui.el [ Ui.alignRight ] (Ui.text member.name)
                            , Ui.Input.text [ Ui.width (Ui.px 100), Shared.decimalInputAttr ]
                                { onChange = InputPayerAmount member.rootId
                                , text = Maybe.withDefault "" (Dict.get member.rootId data.payerAmounts)
                                , placeholder = Just (Shared.zeroAmountPlaceholder i18n data.currency)
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
                (( Nothing, T.newEntryCategoryNone i18n )
                    :: List.map
                        (\category -> ( Just category, Categories.labelWithEmoji i18n category ))
                        Entry.allCategories
                )
            )
        ]
