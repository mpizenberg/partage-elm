module Page.Group.NewEntry exposing (Config, EntryKind, Model, Msg, Output(..), SplitData, init, initFromEntry, initTransfer, outputToKind, update, view)

import Dict exposing (Dict)
import Domain.Currency as Currency exposing (Currency)
import Domain.Date exposing (Date)
import Domain.Entry as Entry
import Domain.Member as Member
import FeatherIcons
import Field
import Form
import Form.NewEntry as NewEntry exposing (Output)
import Format
import Html
import Html.Attributes
import Html.Events
import List.Extra
import Translations as T exposing (I18n)
import UI.Components
import UI.Theme as Theme
import Ui
import Ui.Anim as Anim
import Ui.Font
import Ui.Input
import Validation as V


{-| Whether the entry being created is an expense or a transfer.
-}
type EntryKind
    = ExpenseKind
    | TransferKind


type SplitMode
    = ShareSplit
    | ExactSplit


{-| How the expense is split among beneficiaries: by shares or exact amounts.
-}
type SplitData
    = ShareSplitData (List { memberId : Member.Id, shares : Int })
    | ExactSplitData (List { memberId : Member.Id, amount : Int })


{-| The validated output produced on successful form submission.
-}
type Output
    = ExpenseOutput
        { description : String
        , amountCents : Int
        , currency : Currency
        , defaultCurrencyAmount : Maybe Int
        , notes : Maybe String
        , payers : List Entry.Payer
        , split : SplitData
        , category : Maybe Entry.Category
        , date : Date
        }
    | TransferOutput
        { amountCents : Int
        , currency : Currency
        , defaultCurrencyAmount : Maybe Int
        , fromMemberId : Member.Id
        , toMemberId : Member.Id
        , notes : Maybe String
        , date : Date
        }


{-| Page model holding form state, split mode, payer mode, and related data.
-}
type Model
    = Model ModelData


type alias ModelData =
    { form : NewEntry.Form
    , submitted : Bool
    , isEditing : Bool
    , kind : EntryKind
    , kindLocked : Bool
    , payerAmounts : Dict Member.Id String
    , beneficiaries : Dict Member.Id Int
    , splitMode : SplitMode
    , exactAmounts : Dict Member.Id String
    , fromMemberId : Maybe Member.Id
    , toMemberId : Maybe Member.Id
    , category : Maybe Entry.Category
    , notes : String
    , currency : Currency
    , groupDefaultCurrency : Currency
    , defaultCurrencyAmount : String
    }


{-| Configuration needed to initialize the new entry form.
-}
type alias Config =
    { currentUserRootId : Member.Id
    , activeMembersRootIds : List Member.Id
    , today : Date
    , defaultCurrency : Currency
    }


{-| Messages produced by user interaction on the new entry form.
-}
type Msg
    = SelectEntryKind EntryKind
    | InputDescription String
    | InputAmount String
    | InputNotes String
    | TogglePayer Member.Id
    | InputPayerAmount Member.Id String
    | ToggleBeneficiary Member.Id
    | IncrementShares Member.Id
    | DecrementShares Member.Id
    | InputSplitMode SplitMode
    | InputExactAmount Member.Id String
    | CycleTransferRole Member.Id
    | InputCategory (Maybe Entry.Category)
    | InputCurrency Currency
    | InputDefaultCurrencyAmount String
    | InputDate String
    | Submit


{-| Initialize a blank new entry form using the given configuration.
-}
init : Config -> Model
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
        , category = Nothing
        , notes = ""
        , currency = config.defaultCurrency
        , groupDefaultCurrency = config.defaultCurrency
        , defaultCurrencyAmount = ""
        }


{-| Initialize as a transfer to a specific member with a pre-filled amount.
Used by the "Pay Them" button on balance cards.
-}
initTransfer : Config -> { toMemberId : Member.Id, amountCents : Int } -> Model
initTransfer config { toMemberId, amountCents } =
    let
        (Model data) =
            init config
    in
    Model
        { data
            | kind = TransferKind
            , kindLocked = True
            , fromMemberId = Just config.currentUserRootId
            , toMemberId = Just toMemberId
            , form = data.form |> NewEntry.initAmount amountCents
        }


{-| Initialize from an existing entry for editing.
-}
initFromEntry : Config -> Entry.Entry -> Model
initFromEntry config entry =
    case entry.kind of
        Entry.Expense data ->
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
                                        Just ( e.memberId, centsToDecimalString e.amount )

                                    _ ->
                                        Nothing
                            )
                            data.beneficiaries
                            |> Dict.fromList

                    else
                        Dict.empty

                payerAmountsDict : Dict Member.Id String
                payerAmountsDict =
                    List.map (\p -> ( p.memberId, centsToDecimalString p.amount )) data.payers
                        |> Dict.fromList
            in
            Model
                { form =
                    NewEntry.form
                        |> NewEntry.initDescription data.description
                        |> NewEntry.initAmount data.amount
                        |> NewEntry.initDate data.date
                , submitted = False
                , isEditing = True
                , kind = ExpenseKind
                , kindLocked = True
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
                , category = data.category
                , notes = Maybe.withDefault "" data.notes
                , currency = data.currency
                , groupDefaultCurrency = config.defaultCurrency
                , defaultCurrencyAmount =
                    case data.defaultCurrencyAmount of
                        Just amt ->
                            centsToDecimalString amt

                        Nothing ->
                            ""
                }

        Entry.Transfer data ->
            Model
                { form =
                    NewEntry.form
                        |> NewEntry.initAmount data.amount
                        |> NewEntry.initDate data.date
                , submitted = False
                , isEditing = True
                , kind = TransferKind
                , kindLocked = True
                , payerAmounts = Dict.singleton config.currentUserRootId ""
                , beneficiaries = Dict.fromList (List.map (\mid -> ( mid, 1 )) config.activeMembersRootIds)
                , splitMode = ShareSplit
                , exactAmounts = Dict.empty
                , fromMemberId = Just data.from
                , toMemberId = Just data.to
                , category = Nothing
                , notes = Maybe.withDefault "" data.notes
                , currency = data.currency
                , groupDefaultCurrency = config.defaultCurrency
                , defaultCurrencyAmount =
                    case data.defaultCurrencyAmount of
                        Just amt ->
                            centsToDecimalString amt

                        Nothing ->
                            ""
                }


{-| Handle form input and submission for expense or transfer entries.
-}
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
                -- Already From -> unset
                ( Model { data | fromMemberId = Nothing }, Nothing )

            else if data.toMemberId == Just memberId then
                -- Already To -> unset
                ( Model { data | toMemberId = Nothing }, Nothing )

            else if data.fromMemberId == Nothing then
                -- No From yet -> set as From
                ( Model { data | fromMemberId = Just memberId }, Nothing )

            else if data.toMemberId == Nothing then
                -- No To yet -> set as To
                ( Model { data | toMemberId = Just memberId }, Nothing )

            else
                -- Both set, leave unchanged
                ( Model data, Nothing )

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


submitExpense : ModelData -> ( Model, Maybe Output )
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
                                                    |> Maybe.andThen parseAmountCents
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
                                                    parseAmountCents s
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
                            case parseAmountCents (String.trim data.defaultCurrencyAmount) of
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


submitTransfer : ModelData -> ( Model, Maybe Output )
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
                            case parseAmountCents (String.trim data.defaultCurrencyAmount) of
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



-- VIEW


{-| Render the new entry form, adapting fields based on expense vs transfer mode.
-}
view : I18n -> List Member.ChainState -> (Msg -> msg) -> Model -> Ui.Element msg
view i18n activeMembers toMsg (Model data) =
    let
        content : Ui.Element Msg
        content =
            case data.kind of
                ExpenseKind ->
                    Ui.column [ Ui.spacing Theme.spacing.lg ] <|
                        expenseFields i18n activeMembers data

                TransferKind ->
                    Ui.column [ Ui.spacing Theme.spacing.lg ] <|
                        transferFields i18n activeMembers data

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


modeToggle : I18n -> EntryKind -> Ui.Element Msg
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


expenseFields : I18n -> List Member.ChainState -> ModelData -> List (Ui.Element Msg)
expenseFields i18n activeMembers data =
    [ descriptionField i18n data
    , amountCurrencyField i18n data
    , defaultCurrencyAmountField i18n data
    , dateField i18n data
    , payerField i18n activeMembers data
    , beneficiariesField i18n activeMembers data
    , categoryField i18n data
    , notesField i18n data
    ]


transferFields : I18n -> List Member.ChainState -> ModelData -> List (Ui.Element Msg)
transferFields i18n activeMembers data =
    [ amountCurrencyField i18n data
    , defaultCurrencyAmountField i18n data
    , dateField i18n data
    , transferMembersField i18n activeMembers data
    , notesField i18n data
    , transferSummary activeMembers data
    ]


transferMembersField : I18n -> List Member.ChainState -> ModelData -> Ui.Element Msg
transferMembersField i18n activeMembers data =
    let
        memberRole : Member.Id -> Maybe String
        memberRole memberId =
            if data.fromMemberId == Just memberId then
                Just "From"

            else if data.toMemberId == Just memberId then
                Just "To"

            else
                Nothing

        missingSelection : Bool
        missingSelection =
            data.submitted && (data.fromMemberId == Nothing || data.toMemberId == Nothing)

        sameFromTo : Bool
        sameFromTo =
            data.submitted
                && data.fromMemberId
                /= Nothing
                && data.fromMemberId
                == data.toMemberId
    in
    formField { label = T.newEntryTransferLabel i18n, required = True }
        [ Ui.row [ Ui.spacing Theme.spacing.sm, Ui.wrap ]
            (List.map
                (\member ->
                    transferMemberBtn
                        { name = member.name
                        , initials = String.left 2 (String.toUpper member.name)
                        , role = memberRole member.rootId
                        , onPress = CycleTransferRole member.rootId
                        }
                )
                activeMembers
            )
        , errorWhen missingSelection (T.newEntrySelectBoth i18n)
        , errorWhen sameFromTo (T.newEntrySameFromTo i18n)
        ]


transferSummary : List Member.ChainState -> ModelData -> Ui.Element Msg
transferSummary activeMembers data =
    case ( data.fromMemberId, data.toMemberId ) of
        ( Just fromId, Just toId ) ->
            let
                amountCents : Int
                amountCents =
                    Form.get .amount data.form |> Field.toMaybe |> Maybe.withDefault 0

                amountText : String
                amountText =
                    Format.formatCentsWithCurrency amountCents data.currency

                memberSummary : Ui.Attribute Msg -> String -> Ui.Element Msg
                memberSummary alignAttr name =
                    Ui.el
                        [ Ui.Font.size Theme.font.lg
                        , Ui.Font.weight Theme.fontWeight.semibold
                        , Ui.width Ui.shrink
                        , alignAttr
                        ]
                        (Ui.text name)

                findName : Member.Id -> String
                findName mid =
                    activeMembers
                        |> List.Extra.find (\m -> m.rootId == mid)
                        |> Maybe.map .name
                        |> Maybe.withDefault "?"
            in
            Ui.row
                [ Ui.contentCenterX
                , Ui.contentBottom
                , Ui.spacing Theme.spacing.md
                , Ui.width Ui.shrink
                , Ui.centerX
                , Ui.Font.color Theme.base.textSubtle
                ]
                [ memberSummary Ui.alignRight (findName fromId)
                , Ui.column [ Ui.spacing Theme.spacing.xs, Ui.contentCenterX ]
                    [ Ui.el
                        [ Ui.Font.size Theme.font.sm
                        , Ui.Font.weight Theme.fontWeight.medium
                        ]
                        (Ui.text amountText)
                    , Ui.el [ Ui.centerX ]
                        (UI.Components.featherIcon 20 FeatherIcons.arrowRight)
                    ]
                , memberSummary Ui.alignLeft (findName toId)
                ]

        _ ->
            Ui.none


descriptionField : I18n -> ModelData -> Ui.Element Msg
descriptionField i18n data =
    let
        field : Field.Field String
        field =
            Form.get .description data.form
    in
    formField { label = T.newEntryDescriptionLabel i18n, required = True }
        [ Ui.Input.text [ Ui.width Ui.fill ]
            { onChange = InputDescription
            , text = Field.toRawString field
            , placeholder = Just (T.newEntryDescriptionPlaceholder i18n)
            , label = Ui.Input.labelHidden (T.newEntryDescriptionLabel i18n)
            }
        , formHint (T.newEntryDescriptionHint i18n)
        , fieldError i18n data.submitted field
        ]


amountCurrencyField : I18n -> ModelData -> Ui.Element Msg
amountCurrencyField i18n data =
    let
        field : Field.Field Int
        field =
            Form.get .amount data.form
    in
    formField { label = T.newEntryAmountLabel i18n, required = True }
        [ Ui.row [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill, Ui.contentCenterY ]
            [ Ui.Input.text [ Ui.width Ui.fill ]
                { onChange = InputAmount
                , text = Field.toRawString field
                , placeholder = Just (T.newEntryAmountPlaceholder i18n)
                , label = Ui.Input.labelHidden (T.newEntryAmountLabel i18n)
                }
            , currencySelect data.currency
            ]
        , formHint (T.newEntryAmountHint i18n)
        , fieldError i18n data.submitted field
        ]


currencySelect : Currency -> Ui.Element Msg
currencySelect selected =
    Ui.html
        (Html.select
            [ Html.Events.onInput
                (\code ->
                    case Currency.currencyFromCode code of
                        Just c ->
                            InputCurrency c

                        Nothing ->
                            InputCurrency selected
                )
            , Html.Attributes.style "border" "none"
            , Html.Attributes.style "background" "transparent"
            , Html.Attributes.style "font" "inherit"
            , Html.Attributes.style "color" "inherit"
            ]
            (List.map
                (\c ->
                    Html.option
                        [ Html.Attributes.value (Currency.currencyCode c)
                        , Html.Attributes.selected (c == selected)
                        ]
                        [ Html.text (Currency.currencyCode c) ]
                )
                Currency.allCurrencies
            )
        )


defaultCurrencyAmountField : I18n -> ModelData -> Ui.Element Msg
defaultCurrencyAmountField i18n data =
    if data.currency == data.groupDefaultCurrency then
        Ui.none

    else
        let
            isEmpty : Bool
            isEmpty =
                String.isEmpty (String.trim data.defaultCurrencyAmount)

            isInvalid : Bool
            isInvalid =
                not isEmpty && parseAmountCents (String.trim data.defaultCurrencyAmount) == Nothing
        in
        formField { label = T.newEntryDefaultCurrencyAmountLabel (Currency.currencyCode data.groupDefaultCurrency) i18n, required = True }
            [ Ui.Input.text [ Ui.width Ui.fill ]
                { onChange = InputDefaultCurrencyAmount
                , text = data.defaultCurrencyAmount
                , placeholder = Just (T.newEntryAmountPlaceholder i18n)
                , label = Ui.Input.labelHidden (T.newEntryDefaultCurrencyAmountLabel (Currency.currencyCode data.groupDefaultCurrency) i18n)
                }
            , formHint (T.newEntryDefaultCurrencyAmountHint (Currency.currencyCode data.groupDefaultCurrency) i18n)
            , errorWhen (data.submitted && isEmpty) (T.fieldRequired i18n)
            , errorWhen (data.submitted && isInvalid) (T.fieldInvalidFormat i18n)
            ]


dateField : I18n -> ModelData -> Ui.Element Msg
dateField i18n data =
    let
        field : Field.Field Date
        field =
            Form.get .date data.form
    in
    formField { label = T.newEntryDateLabel i18n, required = True }
        [ Ui.Input.text [ Ui.width Ui.fill ]
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
                                    |> List.filterMap parseAmountCents
                                    |> List.sum

                            totalAmount : Int
                            totalAmount =
                                Form.get .amount data.form |> Field.toMaybe |> Maybe.withDefault 0
                        in
                        errorWhen (data.submitted && totalPayer /= totalAmount) (T.newEntryPayerMismatch i18n)

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
                            , Ui.text <| "(" ++ Currency.currencyCode data.currency ++ ")"
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
    formField { label = T.newEntryPayerLabel i18n, required = True }
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
         , errorWhen (data.submitted && Dict.isEmpty data.payerAmounts) (T.newEntryNoPayerError i18n)
         ]
            ++ payerAmountRows
        )


transferMemberBtn :
    { name : String
    , initials : String
    , role : Maybe String
    , onPress : msg
    }
    -> Ui.Element msg
transferMemberBtn config =
    let
        ( borderClr, backgroundColor, avatarColor ) =
            case config.role of
                Just "From" ->
                    ( Theme.success.solid, Theme.success.bg, UI.Components.AvatarAccent )

                Just "To" ->
                    ( Theme.warning.solid, Theme.warning.bg, UI.Components.AvatarRed )

                _ ->
                    ( Theme.base.solid, Theme.base.bg, UI.Components.AvatarNeutral )
    in
    Ui.row
        [ Ui.Input.button config.onPress
        , Ui.width Ui.shrink
        , Ui.paddingWith { top = 0, bottom = 0, left = 0, right = Theme.spacing.sm }
        , Ui.rounded Theme.radius.xxxl
        , Ui.border Theme.border
        , Ui.spacing Theme.spacing.sm
        , Ui.contentCenterY
        , Ui.pointer
        , Anim.transition (Anim.ms 200)
            [ Anim.borderColor borderClr
            , Anim.backgroundColor backgroundColor
            ]
        ]
        [ UI.Components.avatar avatarColor config.initials
        , case config.role of
            Just role ->
                Ui.el
                    [ Ui.alignRight
                    , Ui.Font.size Theme.font.md
                    , Ui.Font.weight Theme.fontWeight.semibold
                    , Ui.Font.color borderClr
                    ]
                    (Ui.text <| String.toUpper role ++ ":")

            Nothing ->
                Ui.none
        , Ui.el [ Ui.Font.weight Theme.fontWeight.medium ]
            (Ui.text config.name)
        ]


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
                                |> List.filterMap (\mid -> Dict.get mid data.exactAmounts |> Maybe.andThen parseAmountCents)
                                |> List.sum

                        totalAmount : Int
                        totalAmount =
                            Form.get .amount data.form |> Field.toMaybe |> Maybe.withDefault 0
                    in
                    errorWhen (data.submitted && totalExact /= totalAmount) (T.newEntryExactMismatch i18n)

                ShareSplit ->
                    Ui.none

        headerRow : Ui.Element Msg
        headerRow =
            Ui.row [ Ui.width Ui.fill, Ui.contentCenterY ]
                [ fieldTitle (T.newEntryBeneficiariesLabel i18n) True
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
        , formHint (T.newEntryBeneficiariesHint i18n)
        , Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
            (List.map (beneficiaryRow data) activeMembers)
        , errorWhen (data.submitted && Dict.isEmpty data.beneficiaries) (T.newEntryNoBeneficiaries i18n)
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
                                (Ui.text (Currency.currencyCode data.currency))
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
    formField { label = T.newEntryCategoryLabel i18n, required = False }
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


notesField : I18n -> ModelData -> Ui.Element Msg
notesField i18n data =
    formField { label = T.newEntryNotesLabel i18n, required = False }
        [ Ui.Input.text [ Ui.width Ui.fill ]
            { onChange = InputNotes
            , text = data.notes
            , placeholder = Just (T.newEntryNotesPlaceholder i18n)
            , label = Ui.Input.labelHidden (T.newEntryNotesLabel i18n)
            }
        ]



-- FORM COMPONENTS


formField : { label : String, required : Bool } -> List (Ui.Element msg) -> Ui.Element msg
formField config children =
    Ui.column [ Ui.width Ui.fill, Ui.spacing Theme.spacing.xs ]
        (fieldTitle config.label config.required :: children)


fieldTitle : String -> Bool -> Ui.Element msg
fieldTitle label required =
    Ui.row [ Ui.spacing Theme.spacing.xs, Ui.width Ui.shrink ]
        [ Ui.el
            [ Ui.Font.size Theme.font.sm
            , Ui.Font.weight Theme.fontWeight.semibold
            , Ui.Font.color Theme.base.textSubtle
            ]
            (Ui.text label)
        , if required then
            Ui.el [ Ui.Font.color Theme.primary.solid, Ui.Font.size Theme.font.sm ] (Ui.text "*")

          else
            Ui.none
        ]


formHint : String -> Ui.Element msg
formHint text =
    Ui.el [ Ui.Font.size Theme.font.sm, Ui.Font.color Theme.base.textSubtle ]
        (Ui.text text)


fieldError : I18n -> Bool -> Field.Field a -> Ui.Element msg
fieldError i18n submitted field =
    if Field.isInvalid field && (submitted || Field.isDirty field) then
        let
            message : String
            message =
                case Field.firstError field of
                    Just err ->
                        Field.errorToString
                            { onBlank = T.fieldRequired i18n
                            , onSyntaxError = \_ -> T.fieldInvalidFormat i18n
                            , onValidationError = \_ -> T.fieldInvalidFormat i18n
                            }
                            err

                    Nothing ->
                        T.fieldRequired i18n
        in
        Ui.el [ Ui.Font.size Theme.font.sm, Ui.Font.color Theme.danger.text ]
            (Ui.text message)

    else
        Ui.none


errorWhen : Bool -> String -> Ui.Element msg
errorWhen condition message =
    if condition then
        Ui.el [ Ui.Font.size Theme.font.sm, Ui.Font.color Theme.danger.text ]
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
        whole : Int
        whole =
            cents // 100

        frac : Int
        frac =
            remainderBy 100 cents
    in
    String.fromInt whole ++ "." ++ String.padLeft 2 '0' (String.fromInt frac)


{-| Convert a validated Output into an Entry.Kind for storage.
-}
outputToKind : Output -> Entry.Kind
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
