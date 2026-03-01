module Page.NewEntry exposing (Config, EntryKind(..), Model, Msg, Output(..), SplitData(..), init, initFromEntry, outputToKind, update, view)

import Dict exposing (Dict)
import Domain.Currency exposing (Currency)
import Domain.Date as Date exposing (Date)
import Domain.Entry as Entry
import Domain.Member as Member
import Field
import Form
import Form.NewEntry as NewEntry exposing (Output)
import Translations as T exposing (I18n)
import UI.Theme as Theme
import Ui
import Ui.Font
import Ui.Input
import Validation as V


type EntryKind
    = ExpenseKind
    | TransferKind


type PayerMode
    = SinglePayer
    | MultiPayer


type SplitMode
    = ShareSplit
    | ExactSplit


type SplitData
    = ShareSplitData (List { memberId : Member.Id, shares : Int })
    | ExactSplitData (List { memberId : Member.Id, amount : Int })


type Output
    = ExpenseOutput
        { description : String
        , amountCents : Int
        , notes : Maybe String
        , payers : List Entry.Payer
        , split : SplitData
        , category : Maybe Entry.Category
        , date : Date
        }
    | TransferOutput
        { amountCents : Int
        , fromMemberId : Member.Id
        , toMemberId : Member.Id
        , notes : Maybe String
        , date : Date
        }


type Model
    = Model ModelData


type alias ModelData =
    { form : NewEntry.Form
    , submitted : Bool
    , kind : EntryKind
    , kindLocked : Bool
    , payerMode : PayerMode
    , payerId : Member.Id
    , payerAmounts : Dict Member.Id String
    , beneficiaries : Dict Member.Id Int
    , splitMode : SplitMode
    , exactAmounts : Dict Member.Id String
    , fromMemberId : Member.Id
    , toMemberId : Member.Id
    , category : Maybe Entry.Category
    , notes : String
    }


type alias Config =
    { currentUserRootId : Member.Id
    , activeMembersRootIds : List Member.Id
    , today : Date
    }


type Msg
    = InputDescription String
    | InputAmount String
    | InputNotes String
    | InputKind EntryKind
    | InputPayerMode PayerMode
    | InputPayer Member.Id
    | TogglePayer Member.Id
    | InputPayerAmount Member.Id String
    | ToggleBeneficiary Member.Id
    | InputBeneficiaryShares Member.Id String
    | InputSplitMode SplitMode
    | InputExactAmount Member.Id String
    | InputFromMember Member.Id
    | InputToMember Member.Id
    | InputCategory (Maybe Entry.Category)
    | InputDate String
    | Submit


init : Config -> Model
init config =
    let
        ( from, to ) =
            case config.activeMembersRootIds of
                first :: second :: _ ->
                    if first == config.currentUserRootId then
                        ( first, second )

                    else
                        ( config.currentUserRootId, first )

                first :: _ ->
                    ( config.currentUserRootId, first )

                [] ->
                    ( config.currentUserRootId, config.currentUserRootId )
    in
    Model
        { form = NewEntry.form |> NewEntry.initDate config.today
        , submitted = False
        , kind = ExpenseKind
        , kindLocked = False
        , payerMode = SinglePayer
        , payerId = config.currentUserRootId
        , payerAmounts = Dict.empty
        , beneficiaries = Dict.fromList (List.map (\mid -> ( mid, 1 )) config.activeMembersRootIds)
        , splitMode = ShareSplit
        , exactAmounts = Dict.empty
        , fromMemberId = from
        , toMemberId = to
        , category = Nothing
        , notes = ""
        }


{-| Initialize from an existing entry for editing.
-}
initFromEntry : Config -> Entry.Entry -> Model
initFromEntry config entry =
    case entry.kind of
        Entry.Expense data ->
            let
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

                beneficiaryDict =
                    List.filterMap
                        (\b ->
                            case b of
                                Entry.ShareBeneficiary s ->
                                    Just ( s.memberId, s.shares )

                                Entry.ExactBeneficiary e ->
                                    Just ( e.memberId, 1 )
                        )
                        data.beneficiaries
                        |> Dict.fromList

                exactAmountsDict =
                    if isExactSplit then
                        List.filterMap
                            (\b ->
                                case b of
                                    Entry.ExactBeneficiary e ->
                                        Just ( e.memberId, centsToDecimalString e.amount )

                                    _ ->
                                        Nothing
                            )
                            data.beneficiaries
                            |> Dict.fromList

                    else
                        Dict.empty

                isMultiPayer =
                    List.length data.payers > 1

                payerId =
                    case data.payers of
                        p :: _ ->
                            p.memberId

                        [] ->
                            config.currentUserRootId

                payerAmountsDict =
                    if isMultiPayer then
                        List.map (\p -> ( p.memberId, centsToDecimalString p.amount )) data.payers
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
                , kind = ExpenseKind
                , kindLocked = True
                , payerMode =
                    if isMultiPayer then
                        MultiPayer

                    else
                        SinglePayer
                , payerId = payerId
                , payerAmounts = payerAmountsDict
                , beneficiaries = beneficiaryDict
                , splitMode =
                    if isExactSplit then
                        ExactSplit

                    else
                        ShareSplit
                , exactAmounts = exactAmountsDict
                , fromMemberId = config.currentUserRootId
                , toMemberId = config.currentUserRootId
                , category = data.category
                , notes = Maybe.withDefault "" data.notes
                }

        Entry.Transfer data ->
            Model
                { form =
                    NewEntry.form
                        |> NewEntry.initAmount data.amount
                        |> NewEntry.initDate data.date
                , submitted = False
                , kind = TransferKind
                , kindLocked = True
                , payerMode = SinglePayer
                , payerId = config.currentUserRootId
                , payerAmounts = Dict.empty
                , beneficiaries = Dict.fromList (List.map (\mid -> ( mid, 1 )) config.activeMembersRootIds)
                , splitMode = ShareSplit
                , exactAmounts = Dict.empty
                , fromMemberId = data.from
                , toMemberId = data.to
                , category = Nothing
                , notes = Maybe.withDefault "" data.notes
                }


update : Msg -> Model -> ( Model, Maybe Output )
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

        InputKind kind ->
            ( Model { data | kind = kind }, Nothing )

        InputPayerMode mode ->
            ( Model { data | payerMode = mode }, Nothing )

        InputPayer memberId ->
            ( Model { data | payerId = memberId }, Nothing )

        TogglePayer memberId ->
            let
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
                newDict =
                    if Dict.member memberId data.beneficiaries then
                        Dict.remove memberId data.beneficiaries

                    else
                        Dict.insert memberId 1 data.beneficiaries
            in
            ( Model { data | beneficiaries = newDict }, Nothing )

        InputBeneficiaryShares memberId s ->
            let
                shares =
                    String.toInt s |> Maybe.withDefault 1 |> max 1

                newDict =
                    Dict.update memberId (Maybe.map (\_ -> shares)) data.beneficiaries
            in
            ( Model { data | beneficiaries = newDict }, Nothing )

        InputSplitMode mode ->
            ( Model { data | splitMode = mode }, Nothing )

        InputExactAmount memberId s ->
            ( Model { data | exactAmounts = Dict.insert memberId s data.exactAmounts }, Nothing )

        InputFromMember memberId ->
            ( Model { data | fromMemberId = memberId }, Nothing )

        InputToMember memberId ->
            ( Model { data | toMemberId = memberId }, Nothing )

        InputCategory cat ->
            ( Model { data | category = cat }, Nothing )

        InputDate s ->
            ( Model { data | form = Form.modify .date (Field.setFromString s) data.form }, Nothing )

        Submit ->
            case data.kind of
                ExpenseKind ->
                    submitExpense data

                TransferKind ->
                    submitTransfer data


submitExpense : ModelData -> ( Model, Maybe Output )
submitExpense data =
    case Form.validate data.form |> V.toResult of
        Ok formOutput ->
            if Dict.isEmpty data.beneficiaries then
                ( Model { data | submitted = True }, Nothing )

            else
                let
                    notes =
                        if String.isEmpty (String.trim data.notes) then
                            Nothing

                        else
                            Just (String.trim data.notes)

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
                                    selectedIds =
                                        Dict.keys data.beneficiaries

                                    parsedAmounts =
                                        List.filterMap
                                            (\mid ->
                                                Dict.get mid data.exactAmounts
                                                    |> Maybe.andThen parseAmountCents
                                                    |> Maybe.map (\cents -> { memberId = mid, amount = cents })
                                            )
                                            selectedIds
                                in
                                if List.length parsedAmounts /= List.length selectedIds then
                                    Err ()

                                else
                                    let
                                        totalExact =
                                            List.foldl (\b acc -> acc + b.amount) 0 parsedAmounts
                                    in
                                    if totalExact /= formOutput.amountCents then
                                        Err ()

                                    else
                                        Ok (ExactSplitData parsedAmounts)

                    payersResult =
                        case data.payerMode of
                            SinglePayer ->
                                Ok [ { memberId = data.payerId, amount = formOutput.amountCents } ]

                            MultiPayer ->
                                let
                                    parsed =
                                        Dict.toList data.payerAmounts
                                            |> List.filterMap
                                                (\( mid, s ) ->
                                                    parseAmountCents s
                                                        |> Maybe.map (\cents -> { memberId = mid, amount = cents })
                                                )
                                in
                                if List.length parsed /= Dict.size data.payerAmounts then
                                    Err ()

                                else
                                    let
                                        totalPayer =
                                            List.foldl (\p acc -> acc + p.amount) 0 parsed
                                    in
                                    if totalPayer /= formOutput.amountCents then
                                        Err ()

                                    else if List.isEmpty parsed then
                                        Err ()

                                    else
                                        Ok parsed
                in
                case ( splitResult, payersResult ) of
                    ( Ok splitData, Ok payers ) ->
                        ( Model { data | submitted = False }
                        , Just
                            (ExpenseOutput
                                { description = formOutput.description
                                , amountCents = formOutput.amountCents
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


submitTransfer : ModelData -> ( Model, Maybe Output )
submitTransfer data =
    let
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
    case amountAndDate of
        Just ( amountCents, date ) ->
            if data.fromMemberId == data.toMemberId then
                ( Model { data | submitted = True }, Nothing )

            else
                let
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
                        , fromMemberId = data.fromMemberId
                        , toMemberId = data.toMemberId
                        , notes = notes
                        , date = date
                        }
                    )
                )

        Nothing ->
            ( Model { data | submitted = True }, Nothing )



-- VIEW


view : I18n -> List Member.ChainState -> (Msg -> msg) -> Model -> Ui.Element msg
view i18n activeMembers toMsg (Model data) =
    let
        content =
            case data.kind of
                ExpenseKind ->
                    expenseFields i18n activeMembers data

                TransferKind ->
                    transferFields i18n activeMembers data
    in
    Ui.column [ Ui.spacing Theme.spacing.lg, Ui.width Ui.fill ]
        (List.concat
            [ [ Ui.el [ Ui.Font.size Theme.fontSize.xl, Ui.Font.bold ] (Ui.text (T.newEntryTitle i18n))
              , if data.kindLocked then
                    Ui.none

                else
                    kindToggle i18n data
              ]
            , content
            , [ submitButton i18n ]
            ]
        )
        |> Ui.map toMsg


kindToggle : I18n -> ModelData -> Ui.Element Msg
kindToggle i18n data =
    Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.bold ]
            (Ui.text (T.newEntryKindLabel i18n))
        , Ui.Input.chooseOne Ui.row
            [ Ui.spacing Theme.spacing.sm ]
            { onChange = InputKind
            , options =
                [ Ui.Input.option ExpenseKind (Ui.text (T.newEntryKindExpense i18n))
                , Ui.Input.option TransferKind (Ui.text (T.newEntryKindTransfer i18n))
                ]
            , selected = Just data.kind
            , label = Ui.Input.labelHidden (T.newEntryKindLabel i18n)
            }
        ]


expenseFields : I18n -> List Member.ChainState -> ModelData -> List (Ui.Element Msg)
expenseFields i18n activeMembers data =
    [ descriptionField i18n data
    , amountField i18n data
    , dateField i18n data
    , payerField i18n activeMembers data
    , beneficiariesField i18n activeMembers data
    , categoryField i18n data
    , notesField i18n data
    ]


transferFields : I18n -> List Member.ChainState -> ModelData -> List (Ui.Element Msg)
transferFields i18n activeMembers data =
    [ amountField i18n data
    , dateField i18n data
    , memberDropdown i18n (T.newEntryFromLabel i18n) InputFromMember activeMembers data.fromMemberId
    , memberDropdown i18n (T.newEntryToLabel i18n) InputToMember activeMembers data.toMemberId
    , errorWhen (data.submitted && data.fromMemberId == data.toMemberId) (T.newEntrySameFromTo i18n)
    , notesField i18n data
    ]


descriptionField : I18n -> ModelData -> Ui.Element Msg
descriptionField i18n data =
    let
        field =
            Form.get .description data.form
    in
    Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.bold ]
            (Ui.text (T.newEntryDescriptionLabel i18n))
        , Ui.Input.text [ Ui.width Ui.fill ]
            { onChange = InputDescription
            , text = Field.toRawString field
            , placeholder = Just (T.newEntryDescriptionPlaceholder i18n)
            , label = Ui.Input.labelHidden (T.newEntryDescriptionLabel i18n)
            }
        , Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ]
            (Ui.text (T.newEntryDescriptionHint i18n))
        , fieldError i18n data.submitted field
        ]


amountField : I18n -> ModelData -> Ui.Element Msg
amountField i18n data =
    let
        field =
            Form.get .amount data.form
    in
    Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.bold ]
            (Ui.text (T.newEntryAmountLabel i18n))
        , Ui.Input.text [ Ui.width Ui.fill ]
            { onChange = InputAmount
            , text = Field.toRawString field
            , placeholder = Just (T.newEntryAmountPlaceholder i18n)
            , label = Ui.Input.labelHidden (T.newEntryAmountLabel i18n)
            }
        , Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ]
            (Ui.text (T.newEntryAmountHint i18n))
        , fieldError i18n data.submitted field
        ]


dateField : I18n -> ModelData -> Ui.Element Msg
dateField i18n data =
    let
        field =
            Form.get .date data.form
    in
    Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.bold ]
            (Ui.text (T.newEntryDateLabel i18n))
        , Ui.Input.text [ Ui.width Ui.fill ]
            { onChange = InputDate
            , text = Field.toRawString field
            , placeholder = Just "YYYY-MM-DD"
            , label = Ui.Input.labelHidden (T.newEntryDateLabel i18n)
            }
        , fieldError i18n data.submitted field
        ]


payerField : I18n -> List Member.ChainState -> ModelData -> Ui.Element Msg
payerField i18n activeMembers data =
    let
        modeToggle =
            Ui.Input.chooseOne Ui.row
                [ Ui.spacing Theme.spacing.sm ]
                { onChange = InputPayerMode
                , options =
                    [ Ui.Input.option SinglePayer (Ui.text (T.newEntryPayerSingle i18n))
                    , Ui.Input.option MultiPayer (Ui.text (T.newEntryPayerMultiple i18n))
                    ]
                , selected = Just data.payerMode
                , label = Ui.Input.labelHidden (T.newEntryPayerMode i18n)
                }

        payerContent =
            case data.payerMode of
                SinglePayer ->
                    [ memberDropdown i18n (T.newEntryPayerLabel i18n) InputPayer activeMembers data.payerId ]

                MultiPayer ->
                    let
                        payerMismatchError =
                            let
                                totalPayer =
                                    Dict.values data.payerAmounts
                                        |> List.filterMap parseAmountCents
                                        |> List.foldl (+) 0

                                totalAmount =
                                    Form.get .amount data.form |> Field.toMaybe |> Maybe.withDefault 0
                            in
                            if data.submitted && (Dict.isEmpty data.payerAmounts || totalPayer /= totalAmount) then
                                errorWhen True (T.newEntryPayerMismatch i18n)

                            else
                                Ui.none
                    in
                    List.map (payerRow data.payerAmounts) activeMembers ++ [ payerMismatchError ]
    in
    Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
        ([ Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.bold ]
            (Ui.text (T.newEntryPayerLabel i18n))
         , modeToggle
         ]
            ++ payerContent
        )


payerRow : Dict Member.Id String -> Member.ChainState -> Ui.Element Msg
payerRow payerAmounts member =
    let
        isSelected =
            Dict.member member.rootId payerAmounts

        checkLabel =
            Ui.Input.label ("payer-" ++ member.rootId) [] (Ui.text member.name)

        amountInput =
            if isSelected then
                Ui.Input.text [ Ui.width (Ui.px 80) ]
                    { onChange = InputPayerAmount member.rootId
                    , text = Maybe.withDefault "" (Dict.get member.rootId payerAmounts)
                    , placeholder = Just "0.00"
                    , label = Ui.Input.labelHidden member.name
                    }

            else
                Ui.none
    in
    Ui.row [ Ui.spacing Theme.spacing.sm ]
        [ Ui.Input.checkbox []
            { onChange = \_ -> TogglePayer member.rootId
            , icon = Nothing
            , checked = isSelected
            , label = checkLabel.id
            }
        , checkLabel.element
        , amountInput
        ]


beneficiariesField : I18n -> List Member.ChainState -> ModelData -> Ui.Element Msg
beneficiariesField i18n activeMembers data =
    let
        splitModeToggle =
            Ui.Input.chooseOne Ui.row
                [ Ui.spacing Theme.spacing.sm ]
                { onChange = InputSplitMode
                , options =
                    [ Ui.Input.option ShareSplit (Ui.text (T.newEntrySplitShares i18n))
                    , Ui.Input.option ExactSplit (Ui.text (T.newEntrySplitExact i18n))
                    ]
                , selected = Just data.splitMode
                , label = Ui.Input.labelHidden (T.newEntrySplitMode i18n)
                }

        exactMismatchError =
            case data.splitMode of
                ExactSplit ->
                    let
                        totalExact =
                            Dict.keys data.beneficiaries
                                |> List.filterMap (\mid -> Dict.get mid data.exactAmounts |> Maybe.andThen parseAmountCents)
                                |> List.foldl (+) 0

                        totalAmount =
                            Form.get .amount data.form |> Field.toMaybe |> Maybe.withDefault 0
                    in
                    if data.submitted && totalExact /= totalAmount then
                        errorWhen True (T.newEntryExactMismatch i18n)

                    else
                        Ui.none

                ShareSplit ->
                    Ui.none
    in
    Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
        (List.concat
            [ [ Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.bold ]
                    (Ui.text (T.newEntryBeneficiariesLabel i18n))
              , Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ]
                    (Ui.text (T.newEntryBeneficiariesHint i18n))
              , splitModeToggle
              ]
            , List.map (beneficiaryRow i18n data.splitMode data.beneficiaries data.exactAmounts) activeMembers
            , [ errorWhen (data.submitted && Dict.isEmpty data.beneficiaries) (T.newEntryNoBeneficiaries i18n)
              , exactMismatchError
              ]
            ]
        )


beneficiaryRow : I18n -> SplitMode -> Dict Member.Id Int -> Dict Member.Id String -> Member.ChainState -> Ui.Element Msg
beneficiaryRow i18n splitMode selectedBeneficiaries exactAmounts member =
    let
        checkLabel =
            Ui.Input.label ("beneficiary-" ++ member.rootId) [] (Ui.text member.name)

        isSelected =
            Dict.member member.rootId selectedBeneficiaries

        extraInput =
            if not isSelected then
                Ui.none

            else
                case splitMode of
                    ShareSplit ->
                        case Dict.get member.rootId selectedBeneficiaries of
                            Just shares ->
                                Ui.row [ Ui.spacing Theme.spacing.xs ]
                                    [ Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ]
                                        (Ui.text (T.newEntrySharesLabel i18n))
                                    , Ui.Input.text [ Ui.width (Ui.px 50) ]
                                        { onChange = InputBeneficiaryShares member.rootId
                                        , text = String.fromInt shares
                                        , placeholder = Nothing
                                        , label = Ui.Input.labelHidden (T.newEntrySharesLabel i18n)
                                        }
                                    ]

                            Nothing ->
                                Ui.none

                    ExactSplit ->
                        Ui.Input.text [ Ui.width (Ui.px 80) ]
                            { onChange = InputExactAmount member.rootId
                            , text = Maybe.withDefault "" (Dict.get member.rootId exactAmounts)
                            , placeholder = Just "0.00"
                            , label = Ui.Input.labelHidden (T.newEntrySplitExact i18n)
                            }
    in
    Ui.row [ Ui.spacing Theme.spacing.sm ]
        [ Ui.Input.checkbox []
            { onChange = \_ -> ToggleBeneficiary member.rootId
            , icon = Nothing
            , checked = isSelected
            , label = checkLabel.id
            }
        , checkLabel.element
        , extraInput
        ]


categoryField : I18n -> ModelData -> Ui.Element Msg
categoryField i18n data =
    Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.bold ]
            (Ui.text (T.newEntryCategoryLabel i18n))
        , Ui.Input.chooseOne Ui.column
            [ Ui.spacing Theme.spacing.xs ]
            { onChange = InputCategory
            , options =
                [ Ui.Input.option Nothing (Ui.text (T.newEntryCategoryNone i18n))
                , Ui.Input.option (Just Entry.Food) (Ui.text (T.categoryFood i18n))
                , Ui.Input.option (Just Entry.Transport) (Ui.text (T.categoryTransport i18n))
                , Ui.Input.option (Just Entry.Accommodation) (Ui.text (T.categoryAccommodation i18n))
                , Ui.Input.option (Just Entry.Entertainment) (Ui.text (T.categoryEntertainment i18n))
                , Ui.Input.option (Just Entry.Shopping) (Ui.text (T.categoryShopping i18n))
                , Ui.Input.option (Just Entry.Groceries) (Ui.text (T.categoryGroceries i18n))
                , Ui.Input.option (Just Entry.Utilities) (Ui.text (T.categoryUtilities i18n))
                , Ui.Input.option (Just Entry.Healthcare) (Ui.text (T.categoryHealthcare i18n))
                , Ui.Input.option (Just Entry.Other) (Ui.text (T.categoryOther i18n))
                ]
            , selected = Just data.category
            , label = Ui.Input.labelHidden (T.newEntryCategoryLabel i18n)
            }
        ]


notesField : I18n -> ModelData -> Ui.Element Msg
notesField i18n data =
    Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.bold ]
            (Ui.text (T.newEntryNotesLabel i18n))
        , Ui.Input.text [ Ui.width Ui.fill ]
            { onChange = InputNotes
            , text = data.notes
            , placeholder = Just (T.newEntryNotesPlaceholder i18n)
            , label = Ui.Input.labelHidden (T.newEntryNotesLabel i18n)
            }
        ]


memberDropdown : I18n -> String -> (Member.Id -> Msg) -> List Member.ChainState -> Member.Id -> Ui.Element Msg
memberDropdown _ label onChange activeMembers selectedId =
    Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.bold ]
            (Ui.text label)
        , Ui.Input.chooseOne Ui.column
            [ Ui.spacing Theme.spacing.xs ]
            { onChange = onChange
            , options =
                List.map
                    (\member ->
                        Ui.Input.option member.rootId (Ui.text member.name)
                    )
                    activeMembers
            , selected = Just selectedId
            , label = Ui.Input.labelHidden label
            }
        ]


submitButton : I18n -> Ui.Element Msg
submitButton i18n =
    Ui.el
        [ Ui.Input.button Submit
        , Ui.width Ui.fill
        , Ui.padding Theme.spacing.md
        , Ui.rounded Theme.rounding.md
        , Ui.background Theme.primary
        , Ui.Font.color Theme.white
        , Ui.Font.center
        , Ui.Font.bold
        , Ui.pointer
        ]
        (Ui.text (T.newEntrySubmit i18n))


fieldError : I18n -> Bool -> Field.Field a -> Ui.Element msg
fieldError i18n submitted field =
    if Field.isInvalid field && (submitted || Field.isDirty field) then
        Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.danger ]
            (Ui.text (T.fieldRequired i18n))

    else
        Ui.none


errorWhen : Bool -> String -> Ui.Element msg
errorWhen condition message =
    if condition then
        Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.danger ]
            (Ui.text message)

    else
        Ui.none


parseAmountCents : String -> Maybe Int
parseAmountCents s =
    String.toFloat (String.trim s)
        |> Maybe.map (\f -> round (f * 100))
        |> Maybe.andThen
            (\cents ->
                if cents >= 0 then
                    Just cents

                else
                    Nothing
            )


centsToDecimalString : Int -> String
centsToDecimalString cents =
    let
        whole =
            cents // 100

        frac =
            remainderBy 100 cents
    in
    String.fromInt whole ++ "." ++ String.padLeft 2 '0' (String.fromInt frac)


outputToKind : Currency -> Output -> Entry.Kind
outputToKind currency output =
    case output of
        ExpenseOutput data ->
            Entry.Expense
                { description = data.description
                , amount = data.amountCents
                , currency = currency
                , defaultCurrencyAmount = Nothing
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
                , currency = currency
                , defaultCurrencyAmount = Nothing
                , date = data.date
                , from = data.fromMemberId
                , to = data.toMemberId
                , notes = data.notes
                }
