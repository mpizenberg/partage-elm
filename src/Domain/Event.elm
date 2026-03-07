module Domain.Event exposing (Envelope, GroupMetadataChange, Id, Payload(..), compareEnvelopes, createGroup, encodeEnvelope, encodeGroupMetadataChange, encodePayload, envelopeDecoder, groupMetadataChangeDecoder, payloadDecoder, sortEvents, wrap)

{-| Event types and ordering for the event-sourced state machine.
-}

import Domain.Currency as Currency exposing (Currency)
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
    | MemberRenamed { rootId : Member.Id, oldName : String, newName : String }
    | MemberRetired { rootId : Member.Id }
    | MemberUnretired { rootId : Member.Id }
    | MemberReplaced { rootId : Member.Id, previousId : Member.Id, newId : Member.Id }
    | MemberMetadataUpdated { rootId : Member.Id, metadata : Member.Metadata }
    | EntryAdded Entry
    | EntryModified Entry
    | EntryDeleted { rootId : Entry.Id }
    | EntryUndeleted { rootId : Entry.Id }
    | GroupCreated { name : String, defaultCurrency : Currency }
    | GroupMetadataUpdated GroupMetadataChange
    | SettlementPreferencesUpdated { memberRootId : Member.Id, preferredRecipients : List Member.Id }


{-| A partial update to group metadata. Nothing fields are left unchanged,
and `Maybe (Maybe String)` fields use the outer Maybe to indicate presence.
-}
type alias GroupMetadataChange =
    { name : Maybe String
    , subtitle : Maybe (Maybe String)
    , description : Maybe (Maybe String)
    , links : Maybe (List Group.Link)
    }


{-| Sort events in deterministic chronological order.
-}
sortEvents : List Envelope -> List Envelope
sortEvents =
    List.sortWith compareEnvelopes


{-| Compare two envelopes by clientTimestamp, using event id as tiebreaker.
-}
compareEnvelopes : Envelope -> Envelope -> Order
compareEnvelopes a b =
    let
        ta : Int
        ta =
            Time.posixToMillis a.clientTimestamp

        tb : Int
        tb =
            Time.posixToMillis b.clientTimestamp
    in
    case compare ta tb of
        EQ ->
            compare a.id b.id

        order ->
            order


{-| Wrap a payload into an envelope.
-}
wrap : Id -> Time.Posix -> Member.Id -> Payload -> Envelope
wrap eventId clientTimestamp triggeredBy payload =
    { id = eventId
    , clientTimestamp = clientTimestamp
    , triggeredBy = triggeredBy
    , payload = payload
    }


{-| Build the list of payloads for creating a new group:
GroupCreated + MemberCreated for the creator + MemberCreated for each virtual member.
-}
createGroup : { name : String, defaultCurrency : Currency, creator : ( Member.Id, String ), virtualMembers : List ( Member.Id, String ) } -> List Payload
createGroup { name, defaultCurrency, creator, virtualMembers } =
    let
        memberPayload : Member.Type -> ( Member.Id, String ) -> Payload
        memberPayload memberType ( memberId, memberName ) =
            MemberCreated
                { memberId = memberId
                , name = memberName
                , memberType = memberType
                , addedBy = Tuple.first creator
                }
    in
    GroupCreated { name = name, defaultCurrency = defaultCurrency }
        :: memberPayload Member.Real creator
        :: List.map (memberPayload Member.Virtual) virtualMembers


{-| Encode an Envelope as a JSON object.
-}
encodeEnvelope : Envelope -> Encode.Value
encodeEnvelope envelope =
    Encode.object
        [ ( "id", Encode.string envelope.id )
        , ( "ts", Encode.int (Time.posixToMillis envelope.clientTimestamp) )
        , ( "by", Encode.string envelope.triggeredBy )
        , ( "p", encodePayload envelope.payload )
        ]


{-| Decode an Envelope from JSON.
-}
envelopeDecoder : Decode.Decoder Envelope
envelopeDecoder =
    Decode.map4 Envelope
        (Decode.field "id" Decode.string)
        (Decode.field "ts" (Decode.map Time.millisToPosix Decode.int))
        (Decode.field "by" Decode.string)
        (Decode.field "p" payloadDecoder)


{-| Encode a Payload as a tagged JSON object with a "type" discriminator.
-}
encodePayload : Payload -> Encode.Value
encodePayload payload =
    case payload of
        MemberCreated data ->
            Encode.object
                [ ( "t", Encode.string "mc" )
                , ( "m", Encode.string data.memberId )
                , ( "n", Encode.string data.name )
                , ( "mt", Member.encodeType data.memberType )
                , ( "ab", Encode.string data.addedBy )
                ]

        MemberRenamed data ->
            Encode.object
                [ ( "t", Encode.string "mr" )
                , ( "r", Encode.string data.rootId )
                , ( "on", Encode.string data.oldName )
                , ( "nn", Encode.string data.newName )
                ]

        MemberRetired data ->
            Encode.object
                [ ( "t", Encode.string "mrt" )
                , ( "r", Encode.string data.rootId )
                ]

        MemberUnretired data ->
            Encode.object
                [ ( "t", Encode.string "mur" )
                , ( "r", Encode.string data.rootId )
                ]

        MemberReplaced data ->
            Encode.object
                [ ( "t", Encode.string "mrp" )
                , ( "r", Encode.string data.rootId )
                , ( "pi", Encode.string data.previousId )
                , ( "ni", Encode.string data.newId )
                ]

        MemberMetadataUpdated data ->
            Encode.object
                [ ( "t", Encode.string "mmu" )
                , ( "r", Encode.string data.rootId )
                , ( "md", Member.encodeMetadata data.metadata )
                ]

        EntryAdded entry ->
            Encode.object
                [ ( "t", Encode.string "ea" )
                , ( "e", Entry.encodeEntry entry )
                ]

        EntryModified entry ->
            Encode.object
                [ ( "t", Encode.string "em" )
                , ( "e", Entry.encodeEntry entry )
                ]

        EntryDeleted data ->
            Encode.object
                [ ( "t", Encode.string "ed" )
                , ( "r", Encode.string data.rootId )
                ]

        EntryUndeleted data ->
            Encode.object
                [ ( "t", Encode.string "eu" )
                , ( "r", Encode.string data.rootId )
                ]

        GroupCreated data ->
            Encode.object
                [ ( "t", Encode.string "gc" )
                , ( "n", Encode.string data.name )
                , ( "dc", Currency.encodeCurrency data.defaultCurrency )
                ]

        GroupMetadataUpdated change ->
            Encode.object
                [ ( "t", Encode.string "gmu" )
                , ( "c", encodeGroupMetadataChange change )
                ]

        SettlementPreferencesUpdated data ->
            Encode.object
                [ ( "t", Encode.string "spu" )
                , ( "mr", Encode.string data.memberRootId )
                , ( "pr", Encode.list Encode.string data.preferredRecipients )
                ]


{-| Decode a Payload from a tagged JSON object.
-}
payloadDecoder : Decode.Decoder Payload
payloadDecoder =
    Decode.field "t" Decode.string
        |> Decode.andThen
            (\t ->
                case t of
                    "mc" ->
                        Decode.map4
                            (\mid name mt addedBy ->
                                MemberCreated
                                    { memberId = mid
                                    , name = name
                                    , memberType = mt
                                    , addedBy = addedBy
                                    }
                            )
                            (Decode.field "m" Decode.string)
                            (Decode.field "n" Decode.string)
                            (Decode.field "mt" Member.typeDecoder)
                            (Decode.field "ab" Decode.string)

                    "mr" ->
                        Decode.map3
                            (\rid oldN newN ->
                                MemberRenamed
                                    { rootId = rid
                                    , oldName = oldN
                                    , newName = newN
                                    }
                            )
                            (Decode.field "r" Decode.string)
                            (Decode.field "on" Decode.string)
                            (Decode.field "nn" Decode.string)

                    "mrt" ->
                        Decode.map (\rid -> MemberRetired { rootId = rid })
                            (Decode.field "r" Decode.string)

                    "mur" ->
                        Decode.map (\rid -> MemberUnretired { rootId = rid })
                            (Decode.field "r" Decode.string)

                    "mrp" ->
                        Decode.map3
                            (\rid prevId newId ->
                                MemberReplaced
                                    { rootId = rid
                                    , previousId = prevId
                                    , newId = newId
                                    }
                            )
                            (Decode.field "r" Decode.string)
                            (Decode.field "pi" Decode.string)
                            (Decode.field "ni" Decode.string)

                    "mmu" ->
                        Decode.map2
                            (\rid meta ->
                                MemberMetadataUpdated
                                    { rootId = rid
                                    , metadata = meta
                                    }
                            )
                            (Decode.field "r" Decode.string)
                            (Decode.field "md" Member.metadataDecoder)

                    "ea" ->
                        Decode.map EntryAdded
                            (Decode.field "e" Entry.entryDecoder)

                    "em" ->
                        Decode.map EntryModified
                            (Decode.field "e" Entry.entryDecoder)

                    "ed" ->
                        Decode.map (\rid -> EntryDeleted { rootId = rid })
                            (Decode.field "r" Decode.string)

                    "eu" ->
                        Decode.map (\rid -> EntryUndeleted { rootId = rid })
                            (Decode.field "r" Decode.string)

                    "gc" ->
                        Decode.map2
                            (\n c -> GroupCreated { name = n, defaultCurrency = c })
                            (Decode.field "n" Decode.string)
                            (Decode.field "dc" Currency.currencyDecoder)

                    "gmu" ->
                        Decode.map GroupMetadataUpdated
                            (Decode.field "c" groupMetadataChangeDecoder)

                    "spu" ->
                        Decode.map2
                            (\rid prefs ->
                                SettlementPreferencesUpdated
                                    { memberRootId = rid
                                    , preferredRecipients = prefs
                                    }
                            )
                            (Decode.field "mr" Decode.string)
                            (Decode.field "pr" (Decode.list Decode.string))

                    _ ->
                        Decode.fail ("Unknown payload type: " ++ t)
            )


{-| Encode a GroupMetadataChange as a JSON object, omitting unchanged fields.
-}
encodeGroupMetadataChange : GroupMetadataChange -> Encode.Value
encodeGroupMetadataChange change =
    Encode.object
        (List.filterMap identity
            [ Maybe.map (\v -> ( "n", Encode.string v )) change.name
            , Maybe.map (encodeMaybeString "sub") change.subtitle
            , Maybe.map (encodeMaybeString "desc") change.description
            , Maybe.map (\links -> ( "lk", Encode.list Group.encodeLink links )) change.links
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


{-| Decode a GroupMetadataChange from JSON.
-}
groupMetadataChangeDecoder : Decode.Decoder GroupMetadataChange
groupMetadataChangeDecoder =
    Decode.map4 GroupMetadataChange
        (Decode.maybe (Decode.field "n" Decode.string))
        (maybeFieldAsDoubleMaybe "sub")
        (maybeFieldAsDoubleMaybe "desc")
        (Decode.maybe (Decode.field "lk" (Decode.list Group.linkDecoder)))


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
