module Page.Group.ActivityTab exposing (view)

{-| Activity tab showing the group's event history.
-}

import Domain.Activity as Activity exposing (Activity, Detail(..))
import Domain.Member as Member
import Format
import Time
import Translations as T exposing (I18n)
import UI.Theme as Theme
import Ui
import Ui.Font


view : I18n -> (Member.Id -> String) -> List Activity -> Ui.Element msg
view i18n resolveName activities =
    Ui.column [ Ui.spacing Theme.spacing.md, Ui.width Ui.fill, Ui.paddingXY 0 Theme.spacing.md ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.lg, Ui.Font.bold ] (Ui.text (T.activityTabTitle i18n))
        , if List.isEmpty activities then
            Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ]
                (Ui.text (T.activityComingSoon i18n))

          else
            Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
                (List.map (activityItem i18n resolveName) activities)
        ]


activityItem : I18n -> (Member.Id -> String) -> Activity -> Ui.Element msg
activityItem i18n resolveName activity =
    Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
        [ Ui.row [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
            [ Ui.el [ Ui.Font.bold, Ui.Font.size Theme.fontSize.sm ]
                (Ui.text (resolveName activity.actorId))
            , Ui.el [ Ui.Font.size Theme.fontSize.sm ]
                (Ui.text (detailText i18n activity.detail))
            ]
        , Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ]
            (Ui.text (formatTimestamp activity.timestamp))
        ]


detailText : I18n -> Detail -> String
detailText i18n detail =
    case detail of
        EntryAddedDetail data ->
            T.activityEntryAdded data.description i18n
                ++ " ("
                ++ Format.formatCentsWithCurrency data.amount data.currency
                ++ ")"

        EntryModifiedDetail data ->
            T.activityEntryModified data.description i18n
                ++ " ("
                ++ Format.formatCentsWithCurrency data.amount data.currency
                ++ ")"

        TransferAddedDetail data ->
            T.activityTransferAdded i18n
                ++ " ("
                ++ Format.formatCentsWithCurrency data.amount data.currency
                ++ ")"

        TransferModifiedDetail data ->
            T.activityTransferModified i18n
                ++ " ("
                ++ Format.formatCentsWithCurrency data.amount data.currency
                ++ ")"

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

        GroupMetadataUpdatedDetail ->
            T.activityGroupMetadataUpdated i18n


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
