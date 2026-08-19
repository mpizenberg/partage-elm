module ActivityPhrase exposing
    ( Amount
    , Phrase(..)
    , key
    , params
    , phrase
    , render
    , renderLine
    , samples
    , templates
    )

{-| The shared description of "what happened" behind both the activity feed
and push notifications. `phrase` reduces an activity `Detail` to a `Phrase`
plus an optional amount; `render` turns a `Phrase` into the localized verb
phrase that follows an actor name. The notification path sends `key` and
`params` over the wire and the service worker re-assembles the same sentence
from `templates` — derived from `render` applied to `samples`, so the wording
can never diverge between the two surfaces.

`samples` must construct every `Phrase` variant exactly once, with each
argument set to `{param}` for its name in `params`. The compiler cannot
enforce the list's completeness; a variant missing from it degrades that
event kind to the generic notification body while the feed stays correct.

-}

import Domain.Activity exposing (Detail(..))
import Domain.Currency exposing (Currency)
import Domain.Entry as Entry exposing (Kind(..))
import Domain.Member as Member
import Format
import Translations as T exposing (I18n)


type Phrase
    = Unknown
    | EntryAdded String
    | EntryModified String
    | EntryDeleted String
    | EntryUndeleted String
    | TransferAdded
    | TransferModified
    | IncomeAdded String
    | IncomeModified String
    | MemberCreated String
    | MemberCreatedVirtual String
    | MemberLinked String
    | MemberRenamed { oldName : String, newName : String }
    | MemberRetired String
    | MemberUnretired String
    | MemberMetadataUpdated String
    | GroupCreated
    | GroupMetadataUpdated
    | SettlementPreferencesUpdated String


type alias Amount =
    { cents : Int
    , currency : Currency
    }


phrase : Detail -> ( Phrase, Maybe Amount )
phrase detail =
    case detail of
        UnknownDetail ->
            ( Unknown, Nothing )

        EntryAddedDetail data ->
            case data.entry.kind of
                Expense exp ->
                    ( EntryAdded exp.description, Just (entryAmount data.entry) )

                Income inc ->
                    ( IncomeAdded inc.description, Just (entryAmount data.entry) )

                Transfer _ ->
                    ( TransferAdded, Just (entryAmount data.entry) )

        EntryModifiedDetail data ->
            case data.entry.kind of
                Expense exp ->
                    ( EntryModified exp.description, Just (entryAmount data.entry) )

                Income inc ->
                    ( IncomeModified inc.description, Just (entryAmount data.entry) )

                Transfer _ ->
                    ( TransferModified, Just (entryAmount data.entry) )

        TransferAddedDetail data ->
            ( TransferAdded, Just (entryAmount data.entry) )

        TransferModifiedDetail data ->
            ( TransferModified, Just (entryAmount data.entry) )

        EntryDeletedDetail data ->
            ( EntryDeleted data.entryDescription, Nothing )

        EntryUndeletedDetail data ->
            ( EntryUndeleted data.entryDescription, Nothing )

        MemberCreatedDetail data ->
            case data.memberType of
                Member.Real ->
                    ( MemberCreated data.name, Nothing )

                Member.Virtual ->
                    ( MemberCreatedVirtual data.name, Nothing )

        MemberLinkedDetail data ->
            ( MemberLinked data.name, Nothing )

        MemberRenamedDetail data ->
            ( MemberRenamed { oldName = data.oldName, newName = data.newName }, Nothing )

        MemberRetiredDetail data ->
            ( MemberRetired data.name, Nothing )

        MemberUnretiredDetail data ->
            ( MemberUnretired data.name, Nothing )

        MemberMetadataUpdatedDetail data ->
            ( MemberMetadataUpdated data.name, Nothing )

        GroupCreatedDetail _ ->
            ( GroupCreated, Nothing )

        GroupMetadataUpdatedDetail _ ->
            ( GroupMetadataUpdated, Nothing )

        SettlementPreferencesUpdatedDetail data ->
            ( SettlementPreferencesUpdated data.name, Nothing )


entryAmount : Entry.Entry -> Amount
entryAmount entry =
    case entry.kind of
        Expense data ->
            { cents = data.amount, currency = data.currency }

        Transfer data ->
            { cents = data.amount, currency = data.currency }

        Income data ->
            { cents = data.amount, currency = data.currency }


{-| The localized verb phrase, without amount. Follows an actor name.
-}
render : I18n -> Phrase -> String
render i18n p =
    case p of
        Unknown ->
            T.activityUnknown i18n

        EntryAdded description ->
            T.activityEntryAdded description i18n

        EntryModified description ->
            T.activityEntryModified description i18n

        EntryDeleted description ->
            T.activityEntryDeleted description i18n

        EntryUndeleted description ->
            T.activityEntryUndeleted description i18n

        TransferAdded ->
            T.activityTransferAdded i18n

        TransferModified ->
            T.activityTransferModified i18n

        IncomeAdded description ->
            T.activityIncomeAdded description i18n

        IncomeModified description ->
            T.activityIncomeModified description i18n

        MemberCreated name ->
            T.activityMemberCreated name i18n

        MemberCreatedVirtual name ->
            T.activityMemberCreatedVirtual name i18n

        MemberLinked name ->
            T.activityMemberLinked name i18n

        MemberRenamed names ->
            T.activityMemberRenamed names i18n

        MemberRetired name ->
            T.activityMemberRetired name i18n

        MemberUnretired name ->
            T.activityMemberUnretired name i18n

        MemberMetadataUpdated name ->
            T.activityMemberMetadataUpdated name i18n

        GroupCreated ->
            T.activityGroupCreated i18n

        GroupMetadataUpdated ->
            T.activityGroupMetadataUpdated i18n

        SettlementPreferencesUpdated name ->
            T.activitySettlementPreferencesUpdated name i18n


{-| The localized phrase with its amount appended, e.g.
`added "Groceries" (€42.50)`.
-}
renderLine : I18n -> ( Phrase, Maybe Amount ) -> String
renderLine i18n ( p, maybeAmount ) =
    let
        text : String
        text =
            render i18n p
    in
    case maybeAmount of
        Nothing ->
            text

        Just amount ->
            T.activityAmountSuffix
                { text = text
                , amount = Format.formatCentsWithCurrency (T.currentLanguage i18n) amount.cents amount.currency
                }
                i18n


{-| The wire key for a phrase: the name of its Fluent message.
-}
key : Phrase -> String
key p =
    case p of
        Unknown ->
            "activityUnknown"

        EntryAdded _ ->
            "activityEntryAdded"

        EntryModified _ ->
            "activityEntryModified"

        EntryDeleted _ ->
            "activityEntryDeleted"

        EntryUndeleted _ ->
            "activityEntryUndeleted"

        TransferAdded ->
            "activityTransferAdded"

        TransferModified ->
            "activityTransferModified"

        IncomeAdded _ ->
            "activityIncomeAdded"

        IncomeModified _ ->
            "activityIncomeModified"

        MemberCreated _ ->
            "activityMemberCreated"

        MemberCreatedVirtual _ ->
            "activityMemberCreatedVirtual"

        MemberLinked _ ->
            "activityMemberLinked"

        MemberRenamed _ ->
            "activityMemberRenamed"

        MemberRetired _ ->
            "activityMemberRetired"

        MemberUnretired _ ->
            "activityMemberUnretired"

        MemberMetadataUpdated _ ->
            "activityMemberMetadataUpdated"

        GroupCreated ->
            "activityGroupCreated"

        GroupMetadataUpdated ->
            "activityGroupMetadataUpdated"

        SettlementPreferencesUpdated _ ->
            "activitySettlementPreferencesUpdated"


{-| The wire parameters for a phrase, named after the Fluent placeholders.
-}
params : Phrase -> List ( String, String )
params p =
    case p of
        Unknown ->
            []

        EntryAdded description ->
            [ ( "description", description ) ]

        EntryModified description ->
            [ ( "description", description ) ]

        EntryDeleted description ->
            [ ( "description", description ) ]

        EntryUndeleted description ->
            [ ( "description", description ) ]

        TransferAdded ->
            []

        TransferModified ->
            []

        IncomeAdded description ->
            [ ( "description", description ) ]

        IncomeModified description ->
            [ ( "description", description ) ]

        MemberCreated name ->
            [ ( "name", name ) ]

        MemberCreatedVirtual name ->
            [ ( "name", name ) ]

        MemberLinked name ->
            [ ( "name", name ) ]

        MemberRenamed names ->
            [ ( "oldName", names.oldName ), ( "newName", names.newName ) ]

        MemberRetired name ->
            [ ( "name", name ) ]

        MemberUnretired name ->
            [ ( "name", name ) ]

        MemberMetadataUpdated name ->
            [ ( "name", name ) ]

        GroupCreated ->
            []

        GroupMetadataUpdated ->
            []

        SettlementPreferencesUpdated name ->
            [ ( "name", name ) ]


{-| Every phrase variant once, with `{param}` placeholder arguments.
-}
samples : List Phrase
samples =
    [ Unknown
    , EntryAdded "{description}"
    , EntryModified "{description}"
    , EntryDeleted "{description}"
    , EntryUndeleted "{description}"
    , TransferAdded
    , TransferModified
    , IncomeAdded "{description}"
    , IncomeModified "{description}"
    , MemberCreated "{name}"
    , MemberCreatedVirtual "{name}"
    , MemberLinked "{name}"
    , MemberRenamed { oldName = "{oldName}", newName = "{newName}" }
    , MemberRetired "{name}"
    , MemberUnretired "{name}"
    , MemberMetadataUpdated "{name}"
    , GroupCreated
    , GroupMetadataUpdated
    , SettlementPreferencesUpdated "{name}"
    ]


{-| The notification templates: each phrase key mapped to its localized text
with `{param}` placeholders left in place for the service worker to fill.
-}
templates : I18n -> List ( String, String )
templates i18n =
    List.map (\p -> ( key p, render i18n p )) samples
