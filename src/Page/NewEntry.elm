module Page.NewEntry exposing (Config, EntryKind(..), Model, Msg, Output(..), init, initFromEntry, update, view)

import Domain.Date as Date exposing (Date)
import Domain.Entry as Entry
import Domain.GroupState as GroupState
import Domain.Member as Member
import Field
import Form
import Form.NewEntry as NewEntry exposing (Output)
import Set exposing (Set)
import Translations as T exposing (I18n)
import UI.Theme as Theme
import Ui
import Ui.Font
import Ui.Input
import Validation as V


type EntryKind
    = ExpenseKind
    | TransferKind


type Output
    = ExpenseOutput
        { description : String
        , amountCents : Int
        , notes : Maybe String
        , payerId : Member.Id
        , beneficiaryIds : List Member.Id
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
    , payerId : Member.Id
    , beneficiaryIds : Set Member.Id
    , fromMemberId : Member.Id
    , toMemberId : Member.Id
    , category : Maybe Entry.Category
    , notes : String
    }


type alias Config =
    { currentUserRootId : Member.Id
    , activeMembers : List { id : Member.Id, rootId : Member.Id }
    , today : Date
    }


type Msg
    = InputDescription String
    | InputAmount String
    | InputNotes String
    | InputKind EntryKind
    | InputPayer Member.Id
    | ToggleBeneficiary Member.Id
    | InputFromMember Member.Id
    | InputToMember Member.Id
    | InputCategory (Maybe Entry.Category)
    | InputDate String
    | Submit


init : Config -> Model
init config =
    let
        allRootIds =
            List.map .rootId config.activeMembers

        ( from, to ) =
            case allRootIds of
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
        , payerId = config.currentUserRootId
        , beneficiaryIds = Set.fromList allRootIds
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
                beneficiaryMemberIds =
                    List.filterMap
                        (\b ->
                            case b of
                                Entry.ShareBeneficiary s ->
                                    Just s.memberId

                                Entry.ExactBeneficiary e ->
                                    Just e.memberId
                        )
                        data.beneficiaries

                payerId =
                    case data.payers of
                        p :: _ ->
                            p.memberId

                        [] ->
                            config.currentUserRootId
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
                , payerId = payerId
                , beneficiaryIds = Set.fromList beneficiaryMemberIds
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
                , payerId = config.currentUserRootId
                , beneficiaryIds = Set.fromList (List.map .rootId config.activeMembers)
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

        InputPayer memberId ->
            ( Model { data | payerId = memberId }, Nothing )

        ToggleBeneficiary memberId ->
            let
                newSet =
                    if Set.member memberId data.beneficiaryIds then
                        Set.remove memberId data.beneficiaryIds

                    else
                        Set.insert memberId data.beneficiaryIds
            in
            ( Model { data | beneficiaryIds = newSet }, Nothing )

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
            if Set.isEmpty data.beneficiaryIds then
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
                    (ExpenseOutput
                        { description = formOutput.description
                        , amountCents = formOutput.amountCents
                        , notes = notes
                        , payerId = data.payerId
                        , beneficiaryIds = Set.toList data.beneficiaryIds
                        , category = data.category
                        , date = formOutput.date
                        }
                    )
                )

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


view : I18n -> List GroupState.MemberState -> (Msg -> msg) -> Model -> Ui.Element msg
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


expenseFields : I18n -> List GroupState.MemberState -> ModelData -> List (Ui.Element Msg)
expenseFields i18n activeMembers data =
    [ descriptionField i18n data
    , amountField i18n data
    , dateField i18n data
    , payerField i18n activeMembers data
    , beneficiariesField i18n activeMembers data
    , categoryField i18n data
    , notesField i18n data
    ]


transferFields : I18n -> List GroupState.MemberState -> ModelData -> List (Ui.Element Msg)
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


payerField : I18n -> List GroupState.MemberState -> ModelData -> Ui.Element Msg
payerField i18n activeMembers data =
    memberDropdown i18n (T.newEntryPayerLabel i18n) InputPayer activeMembers data.payerId


beneficiariesField : I18n -> List GroupState.MemberState -> ModelData -> Ui.Element Msg
beneficiariesField i18n activeMembers data =
    Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
        (List.concat
            [ [ Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.bold ]
                    (Ui.text (T.newEntryBeneficiariesLabel i18n))
              , Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ]
                    (Ui.text (T.newEntryBeneficiariesHint i18n))
              ]
            , List.map (beneficiaryCheckbox data.beneficiaryIds) activeMembers
            , [ errorWhen (data.submitted && Set.isEmpty data.beneficiaryIds) (T.newEntryNoBeneficiaries i18n) ]
            ]
        )


beneficiaryCheckbox : Set Member.Id -> GroupState.MemberState -> Ui.Element Msg
beneficiaryCheckbox selectedIds member =
    let
        checkLabel =
            Ui.Input.label ("beneficiary-" ++ member.rootId) [] (Ui.text member.name)
    in
    Ui.row [ Ui.spacing Theme.spacing.sm ]
        [ Ui.Input.checkbox []
            { onChange = \_ -> ToggleBeneficiary member.rootId
            , icon = Nothing
            , checked = Set.member member.rootId selectedIds
            , label = checkLabel.id
            }
        , checkLabel.element
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


memberDropdown : I18n -> String -> (Member.Id -> Msg) -> List GroupState.MemberState -> Member.Id -> Ui.Element Msg
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
