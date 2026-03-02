module Page.EntryDetail exposing (Context, Model, Msg, Output(..), init, update, view)

{-| Entry detail view showing full entry data with edit/delete/restore actions.
Uses a two-stage confirmation pattern for destructive actions.
-}

import Domain.Date as Date
import Domain.Entry as Entry exposing (Entry, Kind(..))
import Domain.GroupState exposing (EntryState)
import Domain.Member as Member
import Format
import Translations as T exposing (I18n)
import UI.Theme as Theme
import Ui
import Ui.Events
import Ui.Font
import Ui.Input


{-| Actions that can be triggered from the entry detail page.
-}
type Output
    = EditRequested
    | DeleteRequested
    | RestoreRequested
    | BackRequested


{-| Page model holding the confirmation state.
-}
type Model
    = Model { confirmingAction : Maybe ConfirmAction }


type ConfirmAction
    = ConfirmDelete
    | ConfirmRestore


{-| Messages produced by user interaction on the entry detail page.
-}
type Msg
    = ClickEdit
    | ClickBack
    | ClickDelete
    | ClickRestore
    | Confirm
    | CancelConfirm


{-| Configuration for name resolution.
-}
type alias Context =
    { currentUserRootId : Member.Id
    , resolveName : Member.Id -> String
    }


{-| Initialize with no pending confirmation.
-}
init : Model
init =
    Model { confirmingAction = Nothing }


{-| Handle user interactions, returning updated model and optional output.
-}
update : Msg -> Model -> ( Model, Maybe Output )
update msg (Model data) =
    case msg of
        ClickEdit ->
            ( Model data, Just EditRequested )

        ClickBack ->
            ( Model data, Just BackRequested )

        ClickDelete ->
            ( Model { data | confirmingAction = Just ConfirmDelete }, Nothing )

        ClickRestore ->
            ( Model { data | confirmingAction = Just ConfirmRestore }, Nothing )

        Confirm ->
            case data.confirmingAction of
                Just ConfirmDelete ->
                    ( Model { data | confirmingAction = Nothing }, Just DeleteRequested )

                Just ConfirmRestore ->
                    ( Model { data | confirmingAction = Nothing }, Just RestoreRequested )

                Nothing ->
                    ( Model data, Nothing )

        CancelConfirm ->
            ( Model { data | confirmingAction = Nothing }, Nothing )


labelAttrs : List (Ui.Attribute msg)
labelAttrs =
    [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ]


actionBtn : Msg -> Ui.Color -> String -> Ui.Element Msg
actionBtn msg bgColor label =
    Ui.el
        [ Ui.Input.button msg
        , Ui.width Ui.fill
        , Ui.padding Theme.spacing.md
        , Ui.rounded Theme.rounding.md
        , Ui.background bgColor
        , Ui.Font.color Theme.white
        , Ui.Font.center
        , Ui.Font.bold
        , Ui.pointer
        ]
        (Ui.text label)


{-| Render the full entry detail view with edit, delete, and restore actions.
-}
view : I18n -> Context -> (Msg -> msg) -> Model -> EntryState -> Ui.Element msg
view i18n ctx toMsg (Model data) entryState =
    let
        entry : Entry
        entry =
            entryState.currentVersion
    in
    Ui.column [ Ui.spacing Theme.spacing.lg, Ui.width Ui.fill ]
        [ backLink i18n
        , Ui.el [ Ui.Font.size Theme.fontSize.xl, Ui.Font.bold ] (Ui.text (T.entryDetailTitle i18n))
        , deletedBanner i18n entryState.isDeleted
        , entryContent i18n ctx entry
        , metadataFooter i18n ctx entry
        , actionButtons i18n data.confirmingAction entryState.isDeleted
        ]
        |> Ui.map toMsg


backLink : I18n -> Ui.Element Msg
backLink i18n =
    Ui.el
        [ Ui.pointer
        , Ui.Events.onClick ClickBack
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


entryContent : I18n -> Context -> Entry -> Ui.Element msg
entryContent i18n ctx entry =
    case entry.kind of
        Expense data ->
            expenseContent i18n ctx data

        Transfer data ->
            transferContent i18n ctx data


expenseContent : I18n -> Context -> Entry.ExpenseData -> Ui.Element msg
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


transferContent : I18n -> Context -> Entry.TransferData -> Ui.Element msg
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
            [ Ui.el labelAttrs (Ui.text ("≈ " ++ Format.formatCents amount))
            ]

        Nothing ->
            []


detailRow : String -> String -> Ui.Element msg
detailRow label value =
    Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
        [ Ui.el labelAttrs (Ui.text label)
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
        [ Ui.el labelAttrs (Ui.text (T.entryDetailSplitAmong i18n))
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
                    Ui.el labelAttrs (Ui.text ("×" ++ String.fromInt data.shares))

                  else
                    Ui.none
                ]

        Entry.ExactBeneficiary data ->
            Ui.row [ Ui.spacing Theme.spacing.sm ]
                [ Ui.el [ Ui.Font.size Theme.fontSize.md ] (Ui.text (resolveName data.memberId))
                , Ui.el labelAttrs (Ui.text (Format.formatCents data.amount))
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


metadataFooter : I18n -> Context -> Entry -> Ui.Element msg
metadataFooter i18n ctx entry =
    let
        createdByName : String
        createdByName =
            ctx.resolveName entry.meta.createdBy

        editedIndicator : Ui.Element msg
        editedIndicator =
            if entry.meta.depth > 0 then
                Ui.el (Ui.Font.italic :: labelAttrs)
                    (Ui.text (T.entryDetailEdited i18n))

            else
                Ui.none
    in
    Ui.row [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
        [ Ui.el labelAttrs (Ui.text (T.entryPaidBySingle createdByName i18n))
        , editedIndicator
        ]


actionButtons : I18n -> Maybe ConfirmAction -> Bool -> Ui.Element Msg
actionButtons i18n confirmingAction isDeleted =
    case confirmingAction of
        Just ConfirmDelete ->
            confirmSection i18n
                { warning = T.entryDeleteWarning i18n
                , confirmLabel = T.entryDeleteConfirm i18n
                , bgColor = Theme.danger
                }

        Just ConfirmRestore ->
            confirmSection i18n
                { warning = T.entryRestoreWarning i18n
                , confirmLabel = T.entryRestoreConfirm i18n
                , bgColor = Theme.success
                }

        Nothing ->
            defaultButtons i18n isDeleted


confirmSection : I18n -> { warning : String, confirmLabel : String, bgColor : Ui.Color } -> Ui.Element Msg
confirmSection i18n config =
    Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
        [ Ui.el
            [ Ui.width Ui.fill
            , Ui.padding Theme.spacing.md
            , Ui.rounded Theme.rounding.md
            , Ui.background Theme.dangerLight
            , Ui.Font.color Theme.danger
            , Ui.Font.size Theme.fontSize.sm
            ]
            (Ui.text config.warning)
        , Ui.row [ Ui.spacing Theme.spacing.md, Ui.width Ui.fill ]
            [ actionBtn Confirm config.bgColor config.confirmLabel
            , Ui.el
                (Ui.pointer :: Ui.Events.onClick CancelConfirm :: Ui.padding Theme.spacing.md :: labelAttrs)
                (Ui.text (T.memberRenameCancel i18n))
            ]
        ]


defaultButtons : I18n -> Bool -> Ui.Element Msg
defaultButtons i18n isDeleted =
    Ui.row [ Ui.spacing Theme.spacing.md, Ui.width Ui.fill ]
        [ actionBtn ClickEdit Theme.primary (T.entryDetailEditButton i18n)
        , if isDeleted then
            actionBtn ClickRestore Theme.success (T.entryDetailRestoreButton i18n)

          else
            actionBtn ClickDelete Theme.danger (T.entryDetailDeleteButton i18n)
        ]
