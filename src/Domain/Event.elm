module Domain.Event exposing (Envelope, GroupMetadataChange, Id, Payload(..), buildEntryDeletedEvent, buildEntryModifiedEvent, buildEntryUndeletedEvent, buildExpenseEvent, buildGroupCreationEvents, buildMemberCreatedEvent, buildMemberMetadataUpdatedEvent, buildMemberRenamedEvent, buildMemberRetiredEvent, buildMemberUnretiredEvent, buildTransferEvent, compareEnvelopes, encodeEnvelope, encodeGroupMetadataChange, encodePayload, envelopeDecoder, groupMetadataChangeDecoder, payloadDecoder, sortEvents)

{-| Event types and ordering for the event-sourced state machine.
-}

import Domain.Currency exposing (Currency)
import Domain.Date as Date
import Domain.Entry as Entry exposing (Entry)
import Domain.Group as Group
import Domain.Member as Member
import Json.Decode as Decode
import Json.Encode as Encode
import Time


{-| Unique identifier for an event.
-}
type alias Id =
    String


{-| A timestamped event envelope wrapping a payload with authorship info.
-}
type alias Envelope =
    { id : Id
    , clientTimestamp : Time.Posix
    , triggeredBy : Member.Id
    , payload : Payload
    }


{-| All possible event types in the system.
-}
type Payload
    = MemberCreated { memberId : Member.Id, name : String, memberType : Member.Type, addedBy : Member.Id }
    | MemberRenamed { memberId : Member.Id, oldName : String, newName : String }
    | MemberRetired { memberId : Member.Id }
    | MemberUnretired { memberId : Member.Id }
    | MemberReplaced { previousId : Member.Id, newId : Member.Id }
    | MemberMetadataUpdated { memberId : Member.Id, metadata : Member.Metadata }
    | EntryAdded Entry
    | EntryModified Entry
    | EntryDeleted { rootId : Entry.Id }
    | EntryUndeleted { rootId : Entry.Id }
    | GroupMetadataUpdated GroupMetadataChange


{-| A partial update to group metadata. Nothing fields are left unchanged,
and `Maybe (Maybe String)` fields use the outer Maybe to indicate presence.
-}
type alias GroupMetadataChange =
    { name : Maybe String
    , subtitle : Maybe (Maybe String)
    , description : Maybe (Maybe String)
    , links : Maybe (List Group.Link)
    }


{-| Compare two envelopes by clientTimestamp, using event id as tiebreaker.
-}
compareEnvelopes : Envelope -> Envelope -> Order
compareEnvelopes a b =
    let
        ta =
            Time.posixToMillis a.clientTimestamp

        tb =
            Time.posixToMillis b.clientTimestamp
    in
    case compare ta tb of
        EQ ->
            compare a.id b.id

        order ->
            order


{-| Sort events in deterministic chronological order.
-}
sortEvents : List Envelope -> List Envelope
sortEvents =
    List.sortWith compareEnvelopes


{-| Build the events for creating a new group:
GroupMetadataUpdated + MemberCreated for the creator + MemberCreated for each virtual member.
The eventIds list must have length >= 2 + length of virtualMembers.
-}
buildGroupCreationEvents :
    { creatorId : Member.Id
    , groupName : String
    , creatorName : String
    , virtualMembers : List ( Member.Id, String )
    , eventIds : List Id
    , currentTime : Time.Posix
    }
    -> List Envelope
buildGroupCreationEvents config =
    let
        envelope eventId payload =
            { id = eventId
            , clientTimestamp = config.currentTime
            , triggeredBy = config.creatorId
            , payload = payload
            }
    in
    List.map2 envelope
        config.eventIds
        (GroupMetadataUpdated
            { name = Just config.groupName
            , subtitle = Nothing
            , description = Nothing
            , links = Nothing
            }
            :: MemberCreated
                { memberId = config.creatorId
                , name = config.creatorName
                , memberType = Member.Real
                , addedBy = config.creatorId
                }
            :: List.map
                (\( vmId, vmName ) ->
                    MemberCreated
                        { memberId = vmId
                        , name = vmName
                        , memberType = Member.Virtual
                        , addedBy = config.creatorId
                        }
                )
                config.virtualMembers
        )


{-| Build an expense entry event.
-}
buildExpenseEvent :
    { entryId : Entry.Id
    , eventId : Id
    , memberId : Member.Id
    , currentTime : Time.Posix
    , currency : Currency
    , payerId : Member.Id
    , beneficiaryIds : List Member.Id
    , description : String
    , amountCents : Int
    , category : Maybe Entry.Category
    , notes : Maybe String
    , date : Date.Date
    }
    -> Envelope
buildExpenseEvent config =
    let
        entry =
            { meta = Entry.newMetadata config.entryId config.memberId config.currentTime
            , kind =
                Entry.Expense
                    { description = config.description
                    , amount = config.amountCents
                    , currency = config.currency
                    , defaultCurrencyAmount = Nothing
                    , date = config.date
                    , payers = [ { memberId = config.payerId, amount = config.amountCents } ]
                    , beneficiaries =
                        List.map
                            (\mid -> Entry.ShareBeneficiary { memberId = mid, shares = 1 })
                            config.beneficiaryIds
                    , category = config.category
                    , location = Nothing
                    , notes = config.notes
                    }
            }
    in
    { id = config.eventId
    , clientTimestamp = config.currentTime
    , triggeredBy = config.memberId
    , payload = EntryAdded entry
    }


{-| Build a transfer entry event.
-}
buildTransferEvent :
    { entryId : Entry.Id
    , eventId : Id
    , memberId : Member.Id
    , currentTime : Time.Posix
    , currency : Currency
    , fromMemberId : Member.Id
    , toMemberId : Member.Id
    , amountCents : Int
    , notes : Maybe String
    , date : Date.Date
    }
    -> Envelope
buildTransferEvent config =
    let
        entry =
            { meta = Entry.newMetadata config.entryId config.memberId config.currentTime
            , kind =
                Entry.Transfer
                    { amount = config.amountCents
                    , currency = config.currency
                    , defaultCurrencyAmount = Nothing
                    , date = config.date
                    , from = config.fromMemberId
                    , to = config.toMemberId
                    , notes = config.notes
                    }
            }
    in
    { id = config.eventId
    , clientTimestamp = config.currentTime
    , triggeredBy = config.memberId
    , payload = EntryAdded entry
    }


{-| Build an entry modification event, linking the new version to the previous one.
-}
buildEntryModifiedEvent :
    { newEntryId : Entry.Id
    , eventId : Id
    , memberId : Member.Id
    , currentTime : Time.Posix
    , previousEntry : Entry
    , newKind : Entry.Kind
    }
    -> Envelope
buildEntryModifiedEvent config =
    let
        entry =
            Entry.replace config.previousEntry.meta config.newEntryId config.newKind
    in
    { id = config.eventId
    , clientTimestamp = config.currentTime
    , triggeredBy = config.memberId
    , payload = EntryModified entry
    }


{-| Build an entry deletion event.
-}
buildEntryDeletedEvent :
    { eventId : Id
    , memberId : Member.Id
    , currentTime : Time.Posix
    , rootId : Entry.Id
    }
    -> Envelope
buildEntryDeletedEvent config =
    { id = config.eventId
    , clientTimestamp = config.currentTime
    , triggeredBy = config.memberId
    , payload = EntryDeleted { rootId = config.rootId }
    }


{-| Build an entry restoration event.
-}
buildEntryUndeletedEvent :
    { eventId : Id
    , memberId : Member.Id
    , currentTime : Time.Posix
    , rootId : Entry.Id
    }
    -> Envelope
buildEntryUndeletedEvent config =
    { id = config.eventId
    , clientTimestamp = config.currentTime
    , triggeredBy = config.memberId
    , payload = EntryUndeleted { rootId = config.rootId }
    }


{-| Build a member creation event.
-}
buildMemberCreatedEvent :
    { eventId : Id
    , memberId : Member.Id
    , currentTime : Time.Posix
    , newMemberId : Member.Id
    , name : String
    , memberType : Member.Type
    }
    -> Envelope
buildMemberCreatedEvent config =
    { id = config.eventId
    , clientTimestamp = config.currentTime
    , triggeredBy = config.memberId
    , payload =
        MemberCreated
            { memberId = config.newMemberId
            , name = config.name
            , memberType = config.memberType
            , addedBy = config.memberId
            }
    }


{-| Build a member rename event.
-}
buildMemberRenamedEvent :
    { eventId : Id
    , memberId : Member.Id
    , currentTime : Time.Posix
    , targetMemberId : Member.Id
    , oldName : String
    , newName : String
    }
    -> Envelope
buildMemberRenamedEvent config =
    { id = config.eventId
    , clientTimestamp = config.currentTime
    , triggeredBy = config.memberId
    , payload =
        MemberRenamed
            { memberId = config.targetMemberId
            , oldName = config.oldName
            , newName = config.newName
            }
    }


{-| Build a member retirement event.
-}
buildMemberRetiredEvent :
    { eventId : Id
    , memberId : Member.Id
    , currentTime : Time.Posix
    , targetMemberId : Member.Id
    }
    -> Envelope
buildMemberRetiredEvent config =
    { id = config.eventId
    , clientTimestamp = config.currentTime
    , triggeredBy = config.memberId
    , payload = MemberRetired { memberId = config.targetMemberId }
    }


{-| Build a member reactivation event.
-}
buildMemberUnretiredEvent :
    { eventId : Id
    , memberId : Member.Id
    , currentTime : Time.Posix
    , targetMemberId : Member.Id
    }
    -> Envelope
buildMemberUnretiredEvent config =
    { id = config.eventId
    , clientTimestamp = config.currentTime
    , triggeredBy = config.memberId
    , payload = MemberUnretired { memberId = config.targetMemberId }
    }


{-| Build a member metadata update event.
-}
buildMemberMetadataUpdatedEvent :
    { eventId : Id
    , memberId : Member.Id
    , currentTime : Time.Posix
    , targetMemberId : Member.Id
    , metadata : Member.Metadata
    }
    -> Envelope
buildMemberMetadataUpdatedEvent config =
    { id = config.eventId
    , clientTimestamp = config.currentTime
    , triggeredBy = config.memberId
    , payload =
        MemberMetadataUpdated
            { memberId = config.targetMemberId
            , metadata = config.metadata
            }
    }


encodeEnvelope : Envelope -> Encode.Value
encodeEnvelope envelope =
    Encode.object
        [ ( "id", Encode.string envelope.id )
        , ( "clientTimestamp", Encode.int (Time.posixToMillis envelope.clientTimestamp) )
        , ( "triggeredBy", Encode.string envelope.triggeredBy )
        , ( "payload", encodePayload envelope.payload )
        ]


envelopeDecoder : Decode.Decoder Envelope
envelopeDecoder =
    Decode.map4 Envelope
        (Decode.field "id" Decode.string)
        (Decode.field "clientTimestamp" (Decode.map Time.millisToPosix Decode.int))
        (Decode.field "triggeredBy" Decode.string)
        (Decode.field "payload" payloadDecoder)


encodePayload : Payload -> Encode.Value
encodePayload payload =
    case payload of
        MemberCreated data ->
            Encode.object
                [ ( "type", Encode.string "MemberCreated" )
                , ( "memberId", Encode.string data.memberId )
                , ( "name", Encode.string data.name )
                , ( "memberType", Member.encodeType data.memberType )
                , ( "addedBy", Encode.string data.addedBy )
                ]

        MemberRenamed data ->
            Encode.object
                [ ( "type", Encode.string "MemberRenamed" )
                , ( "memberId", Encode.string data.memberId )
                , ( "oldName", Encode.string data.oldName )
                , ( "newName", Encode.string data.newName )
                ]

        MemberRetired data ->
            Encode.object
                [ ( "type", Encode.string "MemberRetired" )
                , ( "memberId", Encode.string data.memberId )
                ]

        MemberUnretired data ->
            Encode.object
                [ ( "type", Encode.string "MemberUnretired" )
                , ( "memberId", Encode.string data.memberId )
                ]

        MemberReplaced data ->
            Encode.object
                [ ( "type", Encode.string "MemberReplaced" )
                , ( "previousId", Encode.string data.previousId )
                , ( "newId", Encode.string data.newId )
                ]

        MemberMetadataUpdated data ->
            Encode.object
                [ ( "type", Encode.string "MemberMetadataUpdated" )
                , ( "memberId", Encode.string data.memberId )
                , ( "metadata", Member.encodeMetadata data.metadata )
                ]

        EntryAdded entry ->
            Encode.object
                [ ( "type", Encode.string "EntryAdded" )
                , ( "entry", Entry.encodeEntry entry )
                ]

        EntryModified entry ->
            Encode.object
                [ ( "type", Encode.string "EntryModified" )
                , ( "entry", Entry.encodeEntry entry )
                ]

        EntryDeleted data ->
            Encode.object
                [ ( "type", Encode.string "EntryDeleted" )
                , ( "rootId", Encode.string data.rootId )
                ]

        EntryUndeleted data ->
            Encode.object
                [ ( "type", Encode.string "EntryUndeleted" )
                , ( "rootId", Encode.string data.rootId )
                ]

        GroupMetadataUpdated change ->
            Encode.object
                [ ( "type", Encode.string "GroupMetadataUpdated" )
                , ( "change", encodeGroupMetadataChange change )
                ]


payloadDecoder : Decode.Decoder Payload
payloadDecoder =
    Decode.field "type" Decode.string
        |> Decode.andThen
            (\t ->
                case t of
                    "MemberCreated" ->
                        Decode.map4
                            (\mid name mt addedBy ->
                                MemberCreated
                                    { memberId = mid
                                    , name = name
                                    , memberType = mt
                                    , addedBy = addedBy
                                    }
                            )
                            (Decode.field "memberId" Decode.string)
                            (Decode.field "name" Decode.string)
                            (Decode.field "memberType" Member.typeDecoder)
                            (Decode.field "addedBy" Decode.string)

                    "MemberRenamed" ->
                        Decode.map3
                            (\mid oldN newN ->
                                MemberRenamed
                                    { memberId = mid
                                    , oldName = oldN
                                    , newName = newN
                                    }
                            )
                            (Decode.field "memberId" Decode.string)
                            (Decode.field "oldName" Decode.string)
                            (Decode.field "newName" Decode.string)

                    "MemberRetired" ->
                        Decode.map (\mid -> MemberRetired { memberId = mid })
                            (Decode.field "memberId" Decode.string)

                    "MemberUnretired" ->
                        Decode.map (\mid -> MemberUnretired { memberId = mid })
                            (Decode.field "memberId" Decode.string)

                    "MemberReplaced" ->
                        Decode.map2
                            (\prevId newId ->
                                MemberReplaced
                                    { previousId = prevId
                                    , newId = newId
                                    }
                            )
                            (Decode.field "previousId" Decode.string)
                            (Decode.field "newId" Decode.string)

                    "MemberMetadataUpdated" ->
                        Decode.map2
                            (\mid meta ->
                                MemberMetadataUpdated
                                    { memberId = mid
                                    , metadata = meta
                                    }
                            )
                            (Decode.field "memberId" Decode.string)
                            (Decode.field "metadata" Member.metadataDecoder)

                    "EntryAdded" ->
                        Decode.map EntryAdded
                            (Decode.field "entry" Entry.entryDecoder)

                    "EntryModified" ->
                        Decode.map EntryModified
                            (Decode.field "entry" Entry.entryDecoder)

                    "EntryDeleted" ->
                        Decode.map (\rid -> EntryDeleted { rootId = rid })
                            (Decode.field "rootId" Decode.string)

                    "EntryUndeleted" ->
                        Decode.map (\rid -> EntryUndeleted { rootId = rid })
                            (Decode.field "rootId" Decode.string)

                    "GroupMetadataUpdated" ->
                        Decode.map GroupMetadataUpdated
                            (Decode.field "change" groupMetadataChangeDecoder)

                    _ ->
                        Decode.fail ("Unknown payload type: " ++ t)
            )


encodeGroupMetadataChange : GroupMetadataChange -> Encode.Value
encodeGroupMetadataChange change =
    Encode.object
        (List.filterMap identity
            [ Maybe.map (\v -> ( "name", Encode.string v )) change.name
            , Maybe.map (encodeMaybeString "subtitle") change.subtitle
            , Maybe.map (encodeMaybeString "description") change.description
            , Maybe.map (\links -> ( "links", Encode.list Group.encodeLink links )) change.links
            ]
        )


{-| Encode the inner Maybe String: Nothing becomes null, Just s becomes a string.
-}
encodeMaybeString : String -> Maybe String -> ( String, Encode.Value )
encodeMaybeString fieldName maybeValue =
    case maybeValue of
        Nothing ->
            ( fieldName, Encode.null )

        Just s ->
            ( fieldName, Encode.string s )


groupMetadataChangeDecoder : Decode.Decoder GroupMetadataChange
groupMetadataChangeDecoder =
    Decode.map4 GroupMetadataChange
        (Decode.maybe (Decode.field "name" Decode.string))
        (maybeFieldAsDoubleMaybe "subtitle")
        (maybeFieldAsDoubleMaybe "description")
        (Decode.maybe (Decode.field "links" (Decode.list Group.linkDecoder)))


{-| Decode a field that may be absent (Nothing), null (Just Nothing),
or a string (Just (Just s)).
-}
maybeFieldAsDoubleMaybe : String -> Decode.Decoder (Maybe (Maybe String))
maybeFieldAsDoubleMaybe fieldName =
    Decode.maybe
        (Decode.field fieldName
            (Decode.oneOf
                [ Decode.null Nothing
                , Decode.map Just Decode.string
                ]
            )
        )
