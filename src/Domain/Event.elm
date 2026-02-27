module Domain.Event exposing (Envelope, GroupMetadataChange, Id, Payload(..), compareEnvelopes, encodeEnvelope, encodeGroupMetadataChange, encodePayload, envelopeDecoder, groupMetadataChangeDecoder, payloadDecoder, sortEvents)

{-| Event types and ordering for the event-sourced state machine.
-}

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
