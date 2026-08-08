module Page.Group.NewEntry.IncomeView exposing (incomeFields)

{-| Income-specific view functions for the new entry form.
-}

import Domain.Member as Member
import Field
import Form
import Page.Group.NewEntry.Shared as Shared exposing (ModelData, Msg(..))
import Translations as T exposing (I18n)
import UI.Components
import UI.Theme as Theme
import Ui
import Ui.Input


incomeFields : I18n -> List Member.State -> ModelData -> List (Ui.Element Msg)
incomeFields i18n activeMembers data =
    [ descriptionField i18n data
    , Shared.amountCurrencyField i18n data
    , Shared.defaultCurrencyAmountField i18n data
    , Shared.dateField i18n data
    , receiverField i18n activeMembers data
    , Shared.beneficiariesField i18n (T.newEntryIncomeBeneficiariesHint i18n) activeMembers data
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
        , Shared.formHint (T.newEntryIncomeDescriptionHint i18n)
        , Shared.fieldError i18n data.submitted field
        ]


receiverField : I18n -> List Member.State -> ModelData -> Ui.Element Msg
receiverField i18n activeMembers data =
    Shared.formField { label = T.newEntryReceivedByLabel i18n, required = True }
        [ Ui.row [ Ui.spacing Theme.spacing.sm, Ui.wrap ]
            (List.map
                (\member ->
                    UI.Components.toggleMemberBtn
                        { name = member.name
                        , initials = String.left 2 (String.toUpper member.name)
                        , selected = data.receiverMemberId == Just member.rootId
                        , onPress = SelectReceiver member.rootId
                        }
                )
                activeMembers
            )
        , Shared.errorWhen (data.submitted && data.receiverMemberId == Nothing) (T.newEntryNoReceiverError i18n)
        ]
