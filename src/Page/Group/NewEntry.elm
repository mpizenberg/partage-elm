module Page.Group.NewEntry exposing (Model, init, initDuplicate, initFromEntry, outputToKind, update, view)

import Dict exposing (Dict)
import Domain.Date exposing (Date)
import Domain.Entry as Entry
import Domain.Member as Member
import FeatherIcons
import Field
import Form
import Form.NewEntry as NewEntry
import Page.Group.NewEntry.ExpenseView as ExpenseView
import Page.Group.NewEntry.IncomeView as IncomeView
import Page.Group.NewEntry.Shared as Shared
    exposing
        ( EntryKind(..)
        , ModelData
        , Msg(..)
        , Output(..)
        , SplitData(..)
        , SplitMode(..)
        )
import Page.Group.NewEntry.TransferView as TransferView
import Translations as T exposing (I18n)
import UI.Components
import UI.Theme as Theme
import Ui
import Ui.Anim as Anim
import Ui.Font
import Ui.Input
import Validation as V


{-| Page model holding form state, split mode, payer mode, and related data.
-}
type Model
    = Model ModelData


{-| Initialize a blank new entry form using the given configuration.
-}
init : Shared.Config -> Model
init config =
    Model
        { form = NewEntry.form |> NewEntry.initDate config.today
        , submitted = False
        , isEditing = False
        , kind = ExpenseKind
        , kindLocked = False
        , payerAmounts = Dict.singleton config.currentUserRootId ""
        , beneficiaries = Dict.fromList (List.map (\mid -> ( mid, 1 )) config.activeMembersRootIds)
        , splitMode = ShareSplit
        , exactAmounts = Dict.empty
        , fromMemberId = Just config.currentUserRootId
        , toMemberId = Nothing
        , receiverMemberId = Just config.currentUserRootId
        , category = Nothing
        , notes = ""
        , currency = config.defaultCurrency
        , groupDefaultCurrency = config.defaultCurrency
        , defaultCurrencyAmount = ""
        }


{-| Initialize from an existing entry for editing.
-}
initFromEntry : Shared.Config -> Entry.Entry -> Model
initFromEntry config entry =
    case entry.kind of
        Entry.Expense data ->
            initFromExpenseData config True data

        Entry.Transfer data ->
            initFromTransferData config True data

        Entry.Income data ->
            initFromIncomeData config True data


{-| Initialize from an existing entry for duplication (creates a new entry).
-}
initDuplicate : Shared.Config -> Entry.Kind -> Model
initDuplicate config kind =
    case kind of
        Entry.Expense data ->
            initFromExpenseData config False data

        Entry.Transfer data ->
            initFromTransferData config False data

        Entry.Income data ->
            initFromIncomeData config False data


initFromExpenseData : Shared.Config -> Bool -> Entry.ExpenseData -> Model
initFromExpenseData config editing data =
    let
        isExactSplit : Bool
        isExactSplit =
            List.any
                (\b ->
                    case b of
                        Entry.ExactBeneficiary _ ->
                            True

                        _ ->
                            False
                )
                data.beneficiaries

        beneficiaryDict : Dict Member.Id Int
        beneficiaryDict =
            List.map
                (\b ->
                    case b of
                        Entry.ShareBeneficiary s ->
                            ( s.memberId, s.shares )

                        Entry.ExactBeneficiary e ->
                            ( e.memberId, 1 )
                )
                data.beneficiaries
                |> Dict.fromList

        exactAmountsDict : Dict Member.Id String
        exactAmountsDict =
            if isExactSplit then
                List.filterMap
                    (\b ->
                        case b of
                            Entry.ExactBeneficiary e ->
                                Just ( e.memberId, Shared.centsToDecimalString e.amount )

                            _ ->
                                Nothing
                    )
                    data.beneficiaries
                    |> Dict.fromList

            else
                Dict.empty

        payerAmountsDict : Dict Member.Id String
        payerAmountsDict =
            List.map (\p -> ( p.memberId, Shared.centsToDecimalString p.amount )) data.payers
                |> Dict.fromList
    in
    Model
        { form =
            NewEntry.form
                |> NewEntry.initDescription data.description
                |> NewEntry.initAmount data.amount
                |> NewEntry.initDate data.date
        , submitted = False
        , isEditing = editing
        , kind = ExpenseKind
        , kindLocked = editing
        , payerAmounts = payerAmountsDict
        , beneficiaries = beneficiaryDict
        , splitMode =
            if isExactSplit then
                ExactSplit

            else
                ShareSplit
        , exactAmounts = exactAmountsDict
        , fromMemberId = Nothing
        , toMemberId = Nothing
        , receiverMemberId = Nothing
        , category = data.category
        , notes = Maybe.withDefault "" data.notes
        , currency = data.currency
        , groupDefaultCurrency = config.defaultCurrency
        , defaultCurrencyAmount =
            case data.defaultCurrencyAmount of
                Just amt ->
                    Shared.centsToDecimalString amt

                Nothing ->
                    ""
        }


initFromTransferData : Shared.Config -> Bool -> Entry.TransferData -> Model
initFromTransferData config editing data =
    Model
        { form =
            NewEntry.form
                |> NewEntry.initAmount data.amount
                |> NewEntry.initDate data.date
        , submitted = False
        , isEditing = editing
        , kind = TransferKind
        , kindLocked = editing
        , payerAmounts = Dict.singleton config.currentUserRootId ""
        , beneficiaries = Dict.fromList (List.map (\mid -> ( mid, 1 )) config.activeMembersRootIds)
        , splitMode = ShareSplit
        , exactAmounts = Dict.empty
        , fromMemberId = Just data.from
        , toMemberId = Just data.to
        , receiverMemberId = Nothing
        , category = Nothing
        , notes = Maybe.withDefault "" data.notes
        , currency = data.currency
        , groupDefaultCurrency = config.defaultCurrency
        , defaultCurrencyAmount =
            case data.defaultCurrencyAmount of
                Just amt ->
                    Shared.centsToDecimalString amt

                Nothing ->
                    ""
        }


initFromIncomeData : Shared.Config -> Bool -> Entry.IncomeData -> Model
initFromIncomeData config editing data =
    let
        isExactSplit : Bool
        isExactSplit =
            List.any
                (\b ->
                    case b of
                        Entry.ExactBeneficiary _ ->
                            True

                        _ ->
                            False
                )
                data.beneficiaries

        beneficiaryDict : Dict Member.Id Int
        beneficiaryDict =
            List.map
                (\b ->
                    case b of
                        Entry.ShareBeneficiary s ->
                            ( s.memberId, s.shares )

                        Entry.ExactBeneficiary e ->
                            ( e.memberId, 1 )
                )
                data.beneficiaries
                |> Dict.fromList

        exactAmountsDict : Dict Member.Id String
        exactAmountsDict =
            if isExactSplit then
                List.filterMap
                    (\b ->
                        case b of
                            Entry.ExactBeneficiary e ->
                                Just ( e.memberId, Shared.centsToDecimalString e.amount )

                            _ ->
                                Nothing
                    )
                    data.beneficiaries
                    |> Dict.fromList

            else
                Dict.empty
    in
    Model
        { form =
            NewEntry.form
                |> NewEntry.initDescription data.description
                |> NewEntry.initAmount data.amount
                |> NewEntry.initDate data.date
        , submitted = False
        , isEditing = editing
        , kind = IncomeKind
        , kindLocked = editing
        , payerAmounts = Dict.singleton config.currentUserRootId ""
        , beneficiaries = beneficiaryDict
        , splitMode =
            if isExactSplit then
                ExactSplit

            else
                ShareSplit
        , exactAmounts = exactAmountsDict
        , fromMemberId = Nothing
        , toMemberId = Nothing
        , receiverMemberId = Just data.receivedBy
        , category = Nothing
        , notes = Maybe.withDefault "" data.notes
        , currency = data.currency
        , groupDefaultCurrency = config.defaultCurrency
        , defaultCurrencyAmount =
            case data.defaultCurrencyAmount of
                Just amt ->
                    Shared.centsToDecimalString amt

                Nothing ->
                    ""
        }


{-| Handle form input and submission for expense or transfer entries.
-}
update : Shared.Msg -> Model -> ( Model, Maybe Shared.Output )
update msg (Model data) =
    case msg of
        InputDescription s ->
            ( Model { data | form = Form.modify .description (Field.setFromString s) data.form }
            , Nothing
            )

        InputAmount s ->
            ( Model { data | form = Form.modify .amount (Field.setFromString s) data.form }
            , Nothing
            )

        InputNotes s ->
            ( Model { data | notes = s }, Nothing )

        SelectEntryKind kind ->
            ( Model { data | kind = kind }, Nothing )

        TogglePayer memberId ->
            let
                newDict : Dict Member.Id String
                newDict =
                    if Dict.member memberId data.payerAmounts then
                        Dict.remove memberId data.payerAmounts

                    else
                        Dict.insert memberId "" data.payerAmounts
            in
            ( Model { data | payerAmounts = newDict }, Nothing )

        InputPayerAmount memberId s ->
            ( Model { data | payerAmounts = Dict.insert memberId s data.payerAmounts }, Nothing )

        ToggleBeneficiary memberId ->
            let
                newDict : Dict Member.Id Int
                newDict =
                    if Dict.member memberId data.beneficiaries then
                        Dict.remove memberId data.beneficiaries

                    else
                        Dict.insert memberId 1 data.beneficiaries
            in
            ( Model { data | beneficiaries = newDict }, Nothing )

        IncrementShares memberId ->
            let
                newDict : Dict Member.Id Int
                newDict =
                    case Dict.get memberId data.beneficiaries of
                        Just s ->
                            Dict.insert memberId (s + 1) data.beneficiaries

                        Nothing ->
                            Dict.insert memberId 1 data.beneficiaries
            in
            ( Model { data | beneficiaries = newDict }, Nothing )

        DecrementShares memberId ->
            let
                newDict : Dict Member.Id Int
                newDict =
                    Dict.update memberId
                        (Maybe.andThen
                            (\s ->
                                if s <= 1 then
                                    Nothing

                                else
                                    Just (s - 1)
                            )
                        )
                        data.beneficiaries
            in
            ( Model { data | beneficiaries = newDict }, Nothing )

        InputSplitMode mode ->
            ( Model { data | splitMode = mode }, Nothing )

        InputExactAmount memberId s ->
            ( Model { data | exactAmounts = Dict.insert memberId s data.exactAmounts }, Nothing )

        CycleTransferRole memberId ->
            if data.fromMemberId == Just memberId then
                ( Model { data | fromMemberId = Nothing }, Nothing )

            else if data.toMemberId == Just memberId then
                ( Model { data | toMemberId = Nothing }, Nothing )

            else if data.fromMemberId == Nothing then
                ( Model { data | fromMemberId = Just memberId }, Nothing )

            else if data.toMemberId == Nothing then
                ( Model { data | toMemberId = Just memberId }, Nothing )

            else
                ( Model data, Nothing )

        SelectReceiver memberId ->
            ( Model { data | receiverMemberId = Just memberId }, Nothing )

        InputCategory cat ->
            ( Model { data | category = cat }, Nothing )

        InputCurrency c ->
            ( Model { data | currency = c }, Nothing )

        InputDefaultCurrencyAmount s ->
            ( Model { data | defaultCurrencyAmount = s }, Nothing )

        InputDate s ->
            ( Model { data | form = Form.modify .date (Field.setFromString s) data.form }, Nothing )

        Submit ->
            case data.kind of
                ExpenseKind ->
                    submitExpense data

                TransferKind ->
                    submitTransfer data

                IncomeKind ->
                    submitIncome data


submitExpense : ModelData -> ( Model, Maybe Shared.Output )
submitExpense data =
    case Form.validate data.form |> V.toResult of
        Ok formOutput ->
            if Dict.isEmpty data.beneficiaries then
                ( Model { data | submitted = True }, Nothing )

            else
                let
                    splitResult : Result () SplitData
                    splitResult =
                        case data.splitMode of
                            ShareSplit ->
                                Ok
                                    (ShareSplitData
                                        (Dict.toList data.beneficiaries
                                            |> List.map (\( mid, shares ) -> { memberId = mid, shares = shares })
                                        )
                                    )

                            ExactSplit ->
                                let
                                    selectedIds : List Member.Id
                                    selectedIds =
                                        Dict.keys data.beneficiaries

                                    parsedAmounts : List { memberId : Member.Id, amount : Int }
                                    parsedAmounts =
                                        List.filterMap
                                            (\mid ->
                                                Dict.get mid data.exactAmounts
                                                    |> Maybe.andThen Shared.parseAmountCents
                                                    |> Maybe.map (\cents -> { memberId = mid, amount = cents })
                                            )
                                            selectedIds
                                in
                                if List.length parsedAmounts /= List.length selectedIds then
                                    Err ()

                                else
                                    let
                                        totalExact : Int
                                        totalExact =
                                            List.foldl (\b acc -> acc + b.amount) 0 parsedAmounts
                                    in
                                    if totalExact /= formOutput.amountCents then
                                        Err ()

                                    else
                                        Ok (ExactSplitData parsedAmounts)

                    payersResult : Result () (List Entry.Payer)
                    payersResult =
                        let
                            selectedPayers : List Member.Id
                            selectedPayers =
                                Dict.keys data.payerAmounts
                        in
                        case selectedPayers of
                            [] ->
                                Err ()

                            [ singlePayerId ] ->
                                Ok [ { memberId = singlePayerId, amount = formOutput.amountCents } ]

                            _ ->
                                let
                                    parsed : List Entry.Payer
                                    parsed =
                                        Dict.toList data.payerAmounts
                                            |> List.filterMap
                                                (\( mid, s ) ->
                                                    Shared.parseAmountCents s
                                                        |> Maybe.map (\cents -> { memberId = mid, amount = cents })
                                                )
                                in
                                if List.length parsed /= List.length selectedPayers then
                                    Err ()

                                else
                                    let
                                        totalPayer : Int
                                        totalPayer =
                                            List.foldl (\p acc -> acc + p.amount) 0 parsed
                                    in
                                    if totalPayer /= formOutput.amountCents then
                                        Err ()

                                    else
                                        Ok parsed

                    defaultCurrencyAmountResult : Result () (Maybe Int)
                    defaultCurrencyAmountResult =
                        if data.currency /= data.groupDefaultCurrency then
                            case Shared.parseAmountCents (String.trim data.defaultCurrencyAmount) of
                                Just amt ->
                                    Ok (Just amt)

                                Nothing ->
                                    Err ()

                        else
                            Ok Nothing
                in
                case ( splitResult, payersResult, defaultCurrencyAmountResult ) of
                    ( Ok splitData, Ok payers, Ok defaultCurrencyAmount ) ->
                        let
                            notes : Maybe String
                            notes =
                                if String.isEmpty (String.trim data.notes) then
                                    Nothing

                                else
                                    Just (String.trim data.notes)
                        in
                        ( Model { data | submitted = False }
                        , Just
                            (ExpenseOutput
                                { description = formOutput.description
                                , amountCents = formOutput.amountCents
                                , currency = data.currency
                                , defaultCurrencyAmount = defaultCurrencyAmount
                                , notes = notes
                                , payers = payers
                                , split = splitData
                                , category = data.category
                                , date = formOutput.date
                                }
                            )
                        )

                    _ ->
                        ( Model { data | submitted = True }, Nothing )

        Err _ ->
            ( Model { data | submitted = True }, Nothing )


submitTransfer : ModelData -> ( Model, Maybe Shared.Output )
submitTransfer data =
    let
        amountAndDate : Maybe ( Int, Date )
        amountAndDate =
            Form.get .amount data.form
                |> Field.toMaybe
                |> Maybe.andThen
                    (\amountCents ->
                        Form.get .date data.form
                            |> Field.toMaybe
                            |> Maybe.map (\date -> ( amountCents, date ))
                    )
    in
    case ( amountAndDate, data.fromMemberId, data.toMemberId ) of
        ( Just ( amountCents, date ), Just fromId, Just toId ) ->
            if fromId == toId then
                ( Model { data | submitted = True }, Nothing )

            else
                let
                    defaultCurrencyAmountResult : Result () (Maybe Int)
                    defaultCurrencyAmountResult =
                        if data.currency /= data.groupDefaultCurrency then
                            case Shared.parseAmountCents (String.trim data.defaultCurrencyAmount) of
                                Just amt ->
                                    Ok (Just amt)

                                Nothing ->
                                    Err ()

                        else
                            Ok Nothing
                in
                case defaultCurrencyAmountResult of
                    Ok defaultCurrencyAmount ->
                        let
                            notes : Maybe String
                            notes =
                                if String.isEmpty (String.trim data.notes) then
                                    Nothing

                                else
                                    Just (String.trim data.notes)
                        in
                        ( Model { data | submitted = False }
                        , Just
                            (TransferOutput
                                { amountCents = amountCents
                                , currency = data.currency
                                , defaultCurrencyAmount = defaultCurrencyAmount
                                , fromMemberId = fromId
                                , toMemberId = toId
                                , notes = notes
                                , date = date
                                }
                            )
                        )

                    Err () ->
                        ( Model { data | submitted = True }, Nothing )

        _ ->
            ( Model { data | submitted = True }, Nothing )


submitIncome : ModelData -> ( Model, Maybe Shared.Output )
submitIncome data =
    case Form.validate data.form |> V.toResult of
        Ok formOutput ->
            if Dict.isEmpty data.beneficiaries then
                ( Model { data | submitted = True }, Nothing )

            else
                let
                    splitResult : Result () SplitData
                    splitResult =
                        case data.splitMode of
                            ShareSplit ->
                                Ok
                                    (ShareSplitData
                                        (Dict.toList data.beneficiaries
                                            |> List.map (\( mid, shares ) -> { memberId = mid, shares = shares })
                                        )
                                    )

                            ExactSplit ->
                                let
                                    selectedIds : List Member.Id
                                    selectedIds =
                                        Dict.keys data.beneficiaries

                                    parsedAmounts : List { memberId : Member.Id, amount : Int }
                                    parsedAmounts =
                                        List.filterMap
                                            (\mid ->
                                                Dict.get mid data.exactAmounts
                                                    |> Maybe.andThen Shared.parseAmountCents
                                                    |> Maybe.map (\cents -> { memberId = mid, amount = cents })
                                            )
                                            selectedIds
                                in
                                if List.length parsedAmounts /= List.length selectedIds then
                                    Err ()

                                else
                                    let
                                        totalExact : Int
                                        totalExact =
                                            List.foldl (\b acc -> acc + b.amount) 0 parsedAmounts
                                    in
                                    if totalExact /= formOutput.amountCents then
                                        Err ()

                                    else
                                        Ok (ExactSplitData parsedAmounts)

                    defaultCurrencyAmountResult : Result () (Maybe Int)
                    defaultCurrencyAmountResult =
                        if data.currency /= data.groupDefaultCurrency then
                            case Shared.parseAmountCents (String.trim data.defaultCurrencyAmount) of
                                Just amt ->
                                    Ok (Just amt)

                                Nothing ->
                                    Err ()

                        else
                            Ok Nothing
                in
                case ( splitResult, data.receiverMemberId, defaultCurrencyAmountResult ) of
                    ( Ok splitData, Just receiverId, Ok defaultCurrencyAmount ) ->
                        let
                            notes : Maybe String
                            notes =
                                if String.isEmpty (String.trim data.notes) then
                                    Nothing

                                else
                                    Just (String.trim data.notes)
                        in
                        ( Model { data | submitted = False }
                        , Just
                            (IncomeOutput
                                { description = formOutput.description
                                , amountCents = formOutput.amountCents
                                , currency = data.currency
                                , defaultCurrencyAmount = defaultCurrencyAmount
                                , notes = notes
                                , receivedBy = receiverId
                                , split = splitData
                                , date = formOutput.date
                                }
                            )
                        )

                    _ ->
                        ( Model { data | submitted = True }, Nothing )

        Err _ ->
            ( Model { data | submitted = True }, Nothing )



-- VIEW


{-| Render the new entry form, adapting fields based on expense vs transfer mode.
-}
view : I18n -> List Member.ChainState -> (Shared.Msg -> msg) -> Model -> Ui.Element msg
view i18n activeMembers toMsg (Model data) =
    let
        content : Ui.Element Msg
        content =
            case data.kind of
                ExpenseKind ->
                    Ui.column [ Ui.spacing Theme.spacing.lg ] <|
                        ExpenseView.expenseFields i18n activeMembers data

                TransferKind ->
                    Ui.column [ Ui.spacing Theme.spacing.lg ] <|
                        TransferView.transferFields i18n activeMembers data

                IncomeKind ->
                    Ui.column [ Ui.spacing Theme.spacing.lg ] <|
                        IncomeView.incomeFields i18n activeMembers data

        ( entryKindTabs, confirmButton ) =
            if data.isEditing then
                ( Ui.none
                , UI.Components.btnPrimary [] { label = T.editEntrySubmit i18n, onPress = Submit }
                )

            else
                ( modeToggle i18n data.kind
                , UI.Components.btnPrimary [] { label = T.newEntrySubmit i18n, onPress = Submit }
                )
    in
    Ui.column [ Ui.spacing Theme.spacing.lg, Ui.width Ui.fill ]
        [ entryKindTabs
        , content
        , confirmButton
        , Ui.el [] Ui.none -- bottom spacer
        ]
        |> Ui.map toMsg


modeToggle : I18n -> Shared.EntryKind -> Ui.Element Shared.Msg
modeToggle i18n current =
    Ui.row
        [ Ui.width Ui.fill
        , Ui.background Theme.base.bgSubtle
        , Ui.rounded Theme.radius.md
        , Ui.border Theme.border
        , Ui.borderColor Theme.base.accent
        , Ui.padding Theme.spacing.xs
        ]
        [ modeBtn { label = T.newEntryKindExpense i18n, icon = FeatherIcons.shoppingCart, active = current == ExpenseKind, onPress = SelectEntryKind ExpenseKind }
        , modeBtn { label = T.newEntryKindTransfer i18n, icon = FeatherIcons.send, active = current == TransferKind, onPress = SelectEntryKind TransferKind }
        , modeBtn { label = T.newEntryKindIncome i18n, icon = FeatherIcons.download, active = current == IncomeKind, onPress = SelectEntryKind IncomeKind }
        ]


modeBtn : { label : String, icon : FeatherIcons.Icon, active : Bool, onPress : msg } -> Ui.Element msg
modeBtn config =
    Ui.row
        [ Ui.Input.button config.onPress
        , Ui.width Ui.fill
        , Ui.spacing Theme.spacing.sm
        , Ui.paddingXY 0 Theme.spacing.sm
        , Ui.rounded Theme.radius.sm
        , Ui.Font.size Theme.font.md
        , Ui.Font.weight Theme.fontWeight.semibold
        , Ui.contentCenterX
        , Ui.contentCenterY
        , Ui.pointer
        , Anim.transition (Anim.ms 200)
            [ Anim.backgroundColor
                (if config.active then
                    Theme.primary.solid

                 else
                    Theme.base.bgSubtle
                )
            , Anim.fontColor
                (if config.active then
                    Theme.primary.solidText

                 else
                    Theme.base.textSubtle
                )
            ]
        ]
        [ UI.Components.featherIcon 16 config.icon
        , Ui.text config.label
        ]


{-| Convert a validated Output into an Entry.Kind for storage.
-}
outputToKind : Shared.Output -> Entry.Kind
outputToKind output =
    case output of
        ExpenseOutput data ->
            Entry.Expense
                { description = data.description
                , amount = data.amountCents
                , currency = data.currency
                , defaultCurrencyAmount = data.defaultCurrencyAmount
                , date = data.date
                , payers = data.payers
                , beneficiaries =
                    case data.split of
                        ShareSplitData items ->
                            List.map
                                (\b -> Entry.ShareBeneficiary { memberId = b.memberId, shares = b.shares })
                                items

                        ExactSplitData items ->
                            List.map
                                (\b -> Entry.ExactBeneficiary { memberId = b.memberId, amount = b.amount })
                                items
                , category = data.category
                , location = Nothing
                , notes = data.notes
                }

        TransferOutput data ->
            Entry.Transfer
                { amount = data.amountCents
                , currency = data.currency
                , defaultCurrencyAmount = data.defaultCurrencyAmount
                , date = data.date
                , from = data.fromMemberId
                , to = data.toMemberId
                , notes = data.notes
                }

        IncomeOutput data ->
            Entry.Income
                { description = data.description
                , amount = data.amountCents
                , currency = data.currency
                , defaultCurrencyAmount = data.defaultCurrencyAmount
                , date = data.date
                , receivedBy = data.receivedBy
                , beneficiaries =
                    case data.split of
                        ShareSplitData items ->
                            List.map
                                (\b -> Entry.ShareBeneficiary { memberId = b.memberId, shares = b.shares })
                                items

                        ExactSplitData items ->
                            List.map
                                (\b -> Entry.ExactBeneficiary { memberId = b.memberId, amount = b.amount })
                                items
                , notes = data.notes
                }
