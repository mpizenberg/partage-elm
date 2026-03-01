module Page.EntryDetail exposing (Context, view)

{-| Entry detail view showing full entry data with edit/delete/restore actions.
-}

import Domain.Date as Date
import Domain.Entry as Entry exposing (Entry, Kind(..))
import Domain.GroupState as GroupState exposing (EntryState)
import Domain.Member as Member
import Format
import Translations as T exposing (I18n)
import UI.Theme as Theme
import Ui
import Ui.Events
import Ui.Font
import Ui.Input


type alias Context msg =
    { onEdit : msg
    , onDelete : msg
    , onRestore : msg
    , onBack : msg
    , currentUserRootId : Member.Id
    , resolveName : Member.Id -> String
    }


view : I18n -> Context msg -> EntryState -> Ui.Element msg
view i18n ctx entryState =
    let
        entry =
            entryState.currentVersion
    in
    Ui.column [ Ui.spacing Theme.spacing.lg, Ui.width Ui.fill ]
        [ backLink i18n ctx.onBack
        , Ui.el [ Ui.Font.size Theme.fontSize.xl, Ui.Font.bold ] (Ui.text (T.entryDetailTitle i18n))
        , deletedBanner i18n entryState.isDeleted
        , entryContent i18n ctx entry
        , metadataFooter i18n ctx entry
        , actionButtons i18n ctx entryState.isDeleted
        ]


backLink : I18n -> msg -> Ui.Element msg
backLink i18n onBack =
    Ui.el
        [ Ui.pointer
        , Ui.Events.onClick onBack
        , Ui.Font.size Theme.fontSize.sm
        , Ui.Font.color Theme.primary
        ]
        (Ui.text (T.entryDetailBack i18n))


deletedBanner : I18n -> Bool -> Ui.Element msg
deletedBanner i18n isDeleted =
    if isDeleted then
        Ui.el
            [ Ui.width Ui.fill
            , Ui.padding Theme.spacing.md
            , Ui.rounded Theme.rounding.md
            , Ui.background Theme.dangerLight
            , Ui.Font.color Theme.danger
            , Ui.Font.bold
            , Ui.Font.size Theme.fontSize.sm
            ]
            (Ui.text (T.entryDetailDeletedBanner i18n))

    else
        Ui.none


entryContent : I18n -> Context msg -> Entry -> Ui.Element msg
entryContent i18n ctx entry =
    case entry.kind of
        Expense data ->
            expenseContent i18n ctx data

        Transfer data ->
            transferContent i18n ctx data


expenseContent : I18n -> Context msg -> Entry.ExpenseData -> Ui.Element msg
expenseContent i18n ctx data =
    Ui.column [ Ui.spacing Theme.spacing.md, Ui.width Ui.fill ]
        (List.concat
            [ [ detailRow (T.newEntryDescriptionLabel i18n) data.description
              , detailRow (T.entryDetailDate i18n) (Date.toString data.date)
              , detailRow (T.newEntryAmountLabel i18n) (Format.formatCentsWithCurrency data.amount data.currency)
              ]
            , defaultCurrencyAmountRow data.defaultCurrencyAmount
            , [ detailRow (T.entryDetailPaidBy i18n) (payerNames ctx.resolveName data.payers)
              , beneficiariesSection i18n ctx.resolveName data.beneficiaries
              ]
            , categoryRow i18n data.category
            , optionalRow (T.entryDetailNotes i18n) data.notes
            ]
        )


transferContent : I18n -> Context msg -> Entry.TransferData -> Ui.Element msg
transferContent i18n ctx data =
    Ui.column [ Ui.spacing Theme.spacing.md, Ui.width Ui.fill ]
        (List.concat
            [ [ detailRow (T.entryDetailDate i18n) (Date.toString data.date)
              , detailRow (T.newEntryAmountLabel i18n) (Format.formatCentsWithCurrency data.amount data.currency)
              ]
            , defaultCurrencyAmountRow data.defaultCurrencyAmount
            , [ detailRow (T.entryDetailFrom i18n) (ctx.resolveName data.from)
              , detailRow (T.entryDetailTo i18n) (ctx.resolveName data.to)
              ]
            , optionalRow (T.entryDetailNotes i18n) data.notes
            ]
        )


defaultCurrencyAmountRow : Maybe Int -> List (Ui.Element msg)
defaultCurrencyAmountRow maybeAmount =
    case maybeAmount of
        Just amount ->
            [ Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ]
                (Ui.text ("≈ " ++ Format.formatCents amount))
            ]

        Nothing ->
            []


detailRow : String -> String -> Ui.Element msg
detailRow label value =
    Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ] (Ui.text label)
        , Ui.el [ Ui.Font.size Theme.fontSize.md ] (Ui.text value)
        ]


optionalRow : String -> Maybe String -> List (Ui.Element msg)
optionalRow label maybeValue =
    case maybeValue of
        Just value ->
            [ detailRow label value ]

        Nothing ->
            []


payerNames : (Member.Id -> String) -> List Entry.Payer -> String
payerNames resolveName payers =
    payers
        |> List.map (\p -> resolveName p.memberId)
        |> String.join ", "


beneficiariesSection : I18n -> (Member.Id -> String) -> List Entry.Beneficiary -> Ui.Element msg
beneficiariesSection i18n resolveName beneficiaries =
    Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ]
            (Ui.text (T.entryDetailSplitAmong i18n))
        , Ui.column [ Ui.spacing Theme.spacing.xs ]
            (List.map (beneficiaryItem resolveName) beneficiaries)
        ]


beneficiaryItem : (Member.Id -> String) -> Entry.Beneficiary -> Ui.Element msg
beneficiaryItem resolveName beneficiary =
    case beneficiary of
        Entry.ShareBeneficiary data ->
            Ui.row [ Ui.spacing Theme.spacing.sm ]
                [ Ui.el [ Ui.Font.size Theme.fontSize.md ]
                    (Ui.text (resolveName data.memberId))
                , if data.shares > 1 then
                    Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ]
                        (Ui.text ("×" ++ String.fromInt data.shares))

                  else
                    Ui.none
                ]

        Entry.ExactBeneficiary data ->
            Ui.row [ Ui.spacing Theme.spacing.sm ]
                [ Ui.el [ Ui.Font.size Theme.fontSize.md ] (Ui.text (resolveName data.memberId))
                , Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ]
                    (Ui.text (Format.formatCents data.amount))
                ]


categoryRow : I18n -> Maybe Entry.Category -> List (Ui.Element msg)
categoryRow i18n maybeCategory =
    case maybeCategory of
        Just category ->
            [ detailRow (T.entryDetailCategory i18n) (categoryLabel i18n category) ]

        Nothing ->
            []


categoryLabel : I18n -> Entry.Category -> String
categoryLabel i18n category =
    case category of
        Entry.Food ->
            T.categoryFood i18n

        Entry.Transport ->
            T.categoryTransport i18n

        Entry.Accommodation ->
            T.categoryAccommodation i18n

        Entry.Entertainment ->
            T.categoryEntertainment i18n

        Entry.Shopping ->
            T.categoryShopping i18n

        Entry.Groceries ->
            T.categoryGroceries i18n

        Entry.Utilities ->
            T.categoryUtilities i18n

        Entry.Healthcare ->
            T.categoryHealthcare i18n

        Entry.Other ->
            T.categoryOther i18n


metadataFooter : I18n -> Context msg -> Entry -> Ui.Element msg
metadataFooter i18n ctx entry =
    let
        createdByName =
            ctx.resolveName entry.meta.createdBy

        editedIndicator =
            if entry.meta.depth > 0 then
                Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500, Ui.Font.italic ]
                    (Ui.text (T.entryDetailEdited i18n))

            else
                Ui.none
    in
    Ui.row [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ]
            (Ui.text (T.entryPaidBySingle createdByName i18n))
        , editedIndicator
        ]


actionButtons : I18n -> Context msg -> Bool -> Ui.Element msg
actionButtons i18n ctx isDeleted =
    Ui.row [ Ui.spacing Theme.spacing.md, Ui.width Ui.fill ]
        [ Ui.el
            [ Ui.Input.button ctx.onEdit
            , Ui.width Ui.fill
            , Ui.padding Theme.spacing.md
            , Ui.rounded Theme.rounding.md
            , Ui.background Theme.primary
            , Ui.Font.color Theme.white
            , Ui.Font.center
            , Ui.Font.bold
            , Ui.pointer
            ]
            (Ui.text (T.entryDetailEditButton i18n))
        , if isDeleted then
            Ui.el
                [ Ui.Input.button ctx.onRestore
                , Ui.width Ui.fill
                , Ui.padding Theme.spacing.md
                , Ui.rounded Theme.rounding.md
                , Ui.background Theme.success
                , Ui.Font.color Theme.white
                , Ui.Font.center
                , Ui.Font.bold
                , Ui.pointer
                ]
                (Ui.text (T.entryDetailRestoreButton i18n))

          else
            Ui.el
                [ Ui.Input.button ctx.onDelete
                , Ui.width Ui.fill
                , Ui.padding Theme.spacing.md
                , Ui.rounded Theme.rounding.md
                , Ui.background Theme.danger
                , Ui.Font.color Theme.white
                , Ui.Font.center
                , Ui.Font.bold
                , Ui.pointer
                ]
                (Ui.text (T.entryDetailDeleteButton i18n))
        ]
