module Page.Group.ActivityTab exposing (view)

{-| Activity tab showing the group's event history with involvement markers
and expandable detail views.
-}

import Domain.Activity as Activity exposing (Activity, Detail(..), GroupMetadataSnapshot)
import Domain.Date as Date
import Domain.Entry as Entry exposing (Kind(..))
import Domain.Event as Event
import Domain.Member as Member
import Format
import Set exposing (Set)
import Time
import Translations as T exposing (I18n)
import UI.Theme as Theme
import Ui
import Ui.Events
import Ui.Font


type alias Config msg =
    { resolveName : Member.Id -> String
    , currentUserRootId : Member.Id
    , expandedActivities : Set Event.Id
    , onToggleExpanded : Event.Id -> msg
    }


view : I18n -> Config msg -> List Activity -> Ui.Element msg
view i18n config activities =
    Ui.column [ Ui.spacing Theme.spacing.md, Ui.width Ui.fill, Ui.paddingXY 0 Theme.spacing.md ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.lg, Ui.Font.bold ] (Ui.text (T.activityTabTitle i18n))
        , if List.isEmpty activities then
            Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ]
                (Ui.text (T.activityComingSoon i18n))

          else
            Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
                (List.map (activityItem i18n config) activities)
        ]


activityItem : I18n -> Config msg -> Activity -> Ui.Element msg
activityItem i18n config activity =
    let
        isInvolved =
            List.member config.currentUserRootId activity.involvedMembers

        isExpanded =
            Set.member activity.eventId config.expandedActivities

        innerAttrs =
            if isInvolved then
                [ Ui.borderWith { left = 3, top = 0, right = 0, bottom = 0 }
                , Ui.borderColor Theme.primary
                , Ui.paddingWith { left = Theme.spacing.sm, top = 0, right = 0, bottom = 0 }
                ]

            else
                [ Ui.paddingWith { left = Theme.spacing.sm + 3, top = 0, right = 0, bottom = 0 } ]
    in
    Ui.column
        [ Ui.width Ui.fill
        , Ui.borderWith { bottom = Theme.borderWidth.sm, top = 0, left = 0, right = 0 }
        , Ui.borderColor Theme.neutral200
        , Ui.paddingXY 0 Theme.spacing.xs
        , Ui.pointer
        , Ui.Events.onClick (config.onToggleExpanded activity.eventId)
        ]
        [ Ui.column
            ([ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ] ++ innerAttrs)
            [ summaryRow i18n config.resolveName activity
            , Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ]
                (Ui.text (formatTimestamp activity.timestamp))
            , if isExpanded then
                detailPanel i18n config.resolveName activity.detail

              else
                Ui.none
            ]
        ]


summaryRow : I18n -> (Member.Id -> String) -> Activity -> Ui.Element msg
summaryRow i18n resolveName activity =
    Ui.row [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
        [ Ui.el [ Ui.Font.bold, Ui.Font.size Theme.fontSize.sm ]
            (Ui.text (resolveName activity.actorId))
        , Ui.el [ Ui.Font.size Theme.fontSize.sm ]
            (Ui.text (detailSummaryText i18n activity.detail))
        ]


detailSummaryText : I18n -> Detail -> String
detailSummaryText i18n detail =
    case detail of
        EntryAddedDetail data ->
            case data.entry.kind of
                Expense expData ->
                    T.activityEntryAdded expData.description i18n
                        ++ " ("
                        ++ Format.formatCentsWithCurrency expData.amount expData.currency
                        ++ ")"

                Transfer _ ->
                    -- Should not happen (TransferAddedDetail used instead)
                    T.activityTransferAdded i18n

        EntryModifiedDetail data ->
            case data.entry.kind of
                Expense expData ->
                    T.activityEntryModified expData.description i18n
                        ++ " ("
                        ++ Format.formatCentsWithCurrency expData.amount expData.currency
                        ++ ")"
                        ++ changesText i18n data.changes

                Transfer _ ->
                    T.activityTransferModified i18n

        TransferAddedDetail data ->
            case data.entry.kind of
                Transfer tData ->
                    T.activityTransferAdded i18n
                        ++ " ("
                        ++ Format.formatCentsWithCurrency tData.amount tData.currency
                        ++ ")"

                Expense _ ->
                    T.activityTransferAdded i18n

        TransferModifiedDetail data ->
            case data.entry.kind of
                Transfer tData ->
                    T.activityTransferModified i18n
                        ++ " ("
                        ++ Format.formatCentsWithCurrency tData.amount tData.currency
                        ++ ")"
                        ++ changesText i18n data.changes

                Expense _ ->
                    T.activityTransferModified i18n

        EntryDeletedDetail data ->
            T.activityEntryDeleted data.entryDescription i18n

        EntryUndeletedDetail data ->
            T.activityEntryUndeleted data.entryDescription i18n

        MemberCreatedDetail data ->
            case data.memberType of
                Member.Real ->
                    T.activityMemberCreated data.name i18n

                Member.Virtual ->
                    T.activityMemberCreatedVirtual data.name i18n

        MemberReplacedDetail data ->
            T.activityMemberReplaced data.name i18n

        MemberRenamedDetail data ->
            T.activityMemberRenamed { oldName = data.oldName, newName = data.newName } i18n

        MemberRetiredDetail data ->
            T.activityMemberRetired data.name i18n

        MemberUnretiredDetail data ->
            T.activityMemberUnretired data.name i18n

        MemberMetadataUpdatedDetail data ->
            T.activityMemberMetadataUpdated data.name i18n
                ++ changesText i18n data.updatedFields

        GroupMetadataUpdatedDetail data ->
            T.activityGroupMetadataUpdated i18n
                ++ changesText i18n data.changedFields


changesText : I18n -> List String -> String
changesText i18n fields =
    case fields of
        [] ->
            ""

        _ ->
            " — " ++ String.join ", " (List.map (translateField i18n) fields)


translateField : I18n -> String -> String
translateField i18n field =
    case field of
        "description" ->
            T.changeFieldDescription i18n

        "amount" ->
            T.changeFieldAmount i18n

        "date" ->
            T.changeFieldDate i18n

        "payers" ->
            T.changeFieldPayers i18n

        "beneficiaries" ->
            T.changeFieldBeneficiaries i18n

        "category" ->
            T.changeFieldCategory i18n

        "notes" ->
            T.changeFieldNotes i18n

        "from" ->
            T.changeFieldFrom i18n

        "to" ->
            T.changeFieldTo i18n

        "phone" ->
            T.changeFieldPhone i18n

        "email" ->
            T.changeFieldEmail i18n

        "payment" ->
            T.changeFieldPayment i18n

        "name" ->
            T.changeFieldName i18n

        "subtitle" ->
            T.changeFieldSubtitle i18n

        "links" ->
            T.changeFieldLinks i18n

        _ ->
            field



-- DETAIL PANELS


detailPanel : I18n -> (Member.Id -> String) -> Detail -> Ui.Element msg
detailPanel i18n resolveName detail =
    Ui.column
        [ Ui.spacing Theme.spacing.sm
        , Ui.width Ui.fill
        , Ui.paddingWith { top = Theme.spacing.sm, bottom = 0, left = Theme.spacing.md, right = 0 }
        , Ui.borderWith { left = Theme.borderWidth.sm, top = 0, right = 0, bottom = 0 }
        , Ui.borderColor Theme.neutral300
        ]
        (detailContent i18n resolveName detail)


detailContent : I18n -> (Member.Id -> String) -> Detail -> List (Ui.Element msg)
detailContent i18n resolveName detail =
    case detail of
        EntryAddedDetail data ->
            entryDetailRows i18n resolveName data.entry

        EntryModifiedDetail data ->
            entryDetailRows i18n resolveName data.entry

        TransferAddedDetail data ->
            entryDetailRows i18n resolveName data.entry

        TransferModifiedDetail data ->
            entryDetailRows i18n resolveName data.entry

        EntryDeletedDetail data ->
            case data.entry of
                Just entry ->
                    entryDetailRows i18n resolveName entry

                Nothing ->
                    [ detailRow (T.newEntryDescriptionLabel i18n) data.entryDescription ]

        EntryUndeletedDetail data ->
            case data.entry of
                Just entry ->
                    entryDetailRows i18n resolveName entry

                Nothing ->
                    [ detailRow (T.newEntryDescriptionLabel i18n) data.entryDescription ]

        MemberCreatedDetail data ->
            [ detailRow (T.changeFieldName i18n) data.name
            , detailRow (T.newEntryKindLabel i18n)
                (case data.memberType of
                    Member.Real ->
                        T.memberDetailTypeReal i18n

                    Member.Virtual ->
                        T.memberDetailTypeVirtual i18n
                )
            ]

        MemberReplacedDetail data ->
            [ detailRow (T.changeFieldName i18n) data.name ]

        MemberRenamedDetail data ->
            [ diffRow (T.changeFieldName i18n) data.oldName data.newName ]

        MemberRetiredDetail data ->
            [ detailRow (T.changeFieldName i18n) data.name ]

        MemberUnretiredDetail data ->
            [ detailRow (T.changeFieldName i18n) data.name ]

        MemberMetadataUpdatedDetail data ->
            memberMetadataDiffRows i18n data.oldMetadata data.newMetadata

        GroupMetadataUpdatedDetail data ->
            groupMetadataDiffRows i18n data.oldMeta data.newMeta


entryDetailRows : I18n -> (Member.Id -> String) -> Entry.Entry -> List (Ui.Element msg)
entryDetailRows i18n resolveName entry =
    case entry.kind of
        Expense data ->
            List.concat
                [ [ detailRow (T.newEntryDescriptionLabel i18n) data.description
                  , detailRow (T.entryDetailDate i18n) (Date.toString data.date)
                  , detailRow (T.newEntryAmountLabel i18n) (Format.formatCentsWithCurrency data.amount data.currency)
                  , detailRow (T.entryDetailPaidBy i18n) (payerNames resolveName data.payers)
                  , detailRow (T.entryDetailSplitAmong i18n) (beneficiaryNames resolveName data.beneficiaries)
                  ]
                , categoryRow i18n data.category
                , optionalRow (T.entryDetailNotes i18n) data.notes
                ]

        Transfer data ->
            List.concat
                [ [ detailRow (T.entryDetailDate i18n) (Date.toString data.date)
                  , detailRow (T.newEntryAmountLabel i18n) (Format.formatCentsWithCurrency data.amount data.currency)
                  , detailRow (T.entryDetailFrom i18n) (resolveName data.from)
                  , detailRow (T.entryDetailTo i18n) (resolveName data.to)
                  ]
                , optionalRow (T.entryDetailNotes i18n) data.notes
                ]


payerNames : (Member.Id -> String) -> List Entry.Payer -> String
payerNames resolveName payers =
    payers
        |> List.map (\p -> resolveName p.memberId)
        |> String.join ", "


beneficiaryNames : (Member.Id -> String) -> List Entry.Beneficiary -> String
beneficiaryNames resolveName beneficiaries =
    beneficiaries
        |> List.map
            (\b ->
                case b of
                    Entry.ShareBeneficiary data ->
                        resolveName data.memberId

                    Entry.ExactBeneficiary data ->
                        resolveName data.memberId
            )
        |> String.join ", "


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


optionalRow : String -> Maybe String -> List (Ui.Element msg)
optionalRow label maybeValue =
    case maybeValue of
        Just value ->
            [ detailRow label value ]

        Nothing ->
            []



-- DIFF HELPERS


memberMetadataDiffRows : I18n -> Member.Metadata -> Member.Metadata -> List (Ui.Element msg)
memberMetadataDiffRows i18n old new =
    List.filterMap identity
        [ maybeDiffRow (T.changeFieldPhone i18n) old.phone new.phone
        , maybeDiffRow (T.changeFieldEmail i18n) old.email new.email
        , maybeDiffRow (T.changeFieldNotes i18n) old.notes new.notes
        , paymentDiffRows i18n old.payment new.payment
        ]


paymentDiffRows : I18n -> Maybe Member.PaymentInfo -> Maybe Member.PaymentInfo -> Maybe (Ui.Element msg)
paymentDiffRows i18n oldPayment newPayment =
    if oldPayment == newPayment then
        Nothing

    else
        let
            old =
                Maybe.withDefault emptyPayment oldPayment

            new =
                Maybe.withDefault emptyPayment newPayment

            rows =
                List.filterMap identity
                    [ maybeDiffRow (T.memberMetadataIban i18n) old.iban new.iban
                    , maybeDiffRow (T.memberMetadataWero i18n) old.wero new.wero
                    , maybeDiffRow (T.memberMetadataLydia i18n) old.lydia new.lydia
                    , maybeDiffRow (T.memberMetadataRevolut i18n) old.revolut new.revolut
                    , maybeDiffRow (T.memberMetadataPaypal i18n) old.paypal new.paypal
                    , maybeDiffRow (T.memberMetadataVenmo i18n) old.venmo new.venmo
                    , maybeDiffRow (T.memberMetadataBtc i18n) old.btcAddress new.btcAddress
                    , maybeDiffRow (T.memberMetadataAda i18n) old.adaAddress new.adaAddress
                    ]
        in
        case rows of
            [] ->
                Nothing

            _ ->
                Just (Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ] rows)


emptyPayment : Member.PaymentInfo
emptyPayment =
    { iban = Nothing
    , wero = Nothing
    , lydia = Nothing
    , revolut = Nothing
    , paypal = Nothing
    , venmo = Nothing
    , btcAddress = Nothing
    , adaAddress = Nothing
    }


maybeDiffRow : String -> Maybe String -> Maybe String -> Maybe (Ui.Element msg)
maybeDiffRow label oldVal newVal =
    if oldVal == newVal then
        Nothing

    else
        Just (diffRow label (Maybe.withDefault "—" oldVal) (Maybe.withDefault "—" newVal))


groupMetadataDiffRows : I18n -> GroupMetadataSnapshot -> GroupMetadataSnapshot -> List (Ui.Element msg)
groupMetadataDiffRows i18n old new =
    List.filterMap identity
        [ if old.name /= new.name then
            Just (diffRow (T.changeFieldName i18n) old.name new.name)

          else
            Nothing
        , maybeDiffRow (T.changeFieldSubtitle i18n) old.subtitle new.subtitle
        , maybeDiffRow (T.groupSettingsDescription i18n) old.description new.description
        , if old.links /= new.links then
            Just (diffRow (T.changeFieldLinks i18n) (linksToString old.links) (linksToString new.links))

          else
            Nothing
        ]


linksToString : List { label : String, url : String } -> String
linksToString links =
    case links of
        [] ->
            "—"

        _ ->
            links
                |> List.map (\l -> l.label ++ " (" ++ l.url ++ ")")
                |> String.join ", "



-- ROW HELPERS


detailRow : String -> String -> Ui.Element msg
detailRow label value =
    Ui.column [ Ui.spacing 2, Ui.width Ui.fill ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ] (Ui.text label)
        , Ui.el [ Ui.Font.size Theme.fontSize.sm ] (Ui.text value)
        ]


diffRow : String -> String -> String -> Ui.Element msg
diffRow label oldValue newValue =
    Ui.column [ Ui.spacing 2, Ui.width Ui.fill ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ] (Ui.text label)
        , Ui.row [ Ui.spacing Theme.spacing.sm ]
            [ Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.danger, Ui.Font.strike ]
                (Ui.text oldValue)
            , Ui.el [ Ui.Font.size Theme.fontSize.sm ] (Ui.text "→")
            , Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.success ]
                (Ui.text newValue)
            ]
        ]



-- TIMESTAMP


formatTimestamp : Time.Posix -> String
formatTimestamp posix =
    let
        year =
            String.fromInt (Time.toYear Time.utc posix)

        month =
            String.padLeft 2 '0' (String.fromInt (monthToInt (Time.toMonth Time.utc posix)))

        day =
            String.padLeft 2 '0' (String.fromInt (Time.toDay Time.utc posix))

        hour =
            String.padLeft 2 '0' (String.fromInt (Time.toHour Time.utc posix))

        minute =
            String.padLeft 2 '0' (String.fromInt (Time.toMinute Time.utc posix))
    in
    year ++ "-" ++ month ++ "-" ++ day ++ " " ++ hour ++ ":" ++ minute


monthToInt : Time.Month -> Int
monthToInt month =
    case month of
        Time.Jan ->
            1

        Time.Feb ->
            2

        Time.Mar ->
            3

        Time.Apr ->
            4

        Time.May ->
            5

        Time.Jun ->
            6

        Time.Jul ->
            7

        Time.Aug ->
            8

        Time.Sep ->
            9

        Time.Oct ->
            10

        Time.Nov ->
            11

        Time.Dec ->
            12
