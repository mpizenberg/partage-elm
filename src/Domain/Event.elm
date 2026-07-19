module Domain.Event exposing (Envelope, GroupMetadataChange, Id, Payload(..), canonicalize, compareEnvelopes, createGroup, encodeEnvelope, encodeGroupMetadataChange, encodePayload, envelopeDecoder, groupMetadataChangeDecoder, payloadDecoder, sortEvents, withSignature, wrap)

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

`raw` is the envelope's authoritative JSON: the exact value received from
the wire (or produced locally at signing time). Encoding, storage, and
signature verification all go through `raw`, so fields added by newer app
versions survive round trips through clients that don't understand them.

-}
type alias Envelope =
    { id : Id
    , clientTimestamp : Time.Posix
    , triggeredBy : Member.Id
    , version : Int
    , payload : Payload
    , signature : String
    , raw : Encode.Value
    }


{-| Schema version stamped on locally-authored envelopes ("v" field).
Envelopes without the field are read as version 1.
-}
currentVersion : Int
currentVersion =
    1


{-| All possible event types in the system.
-}
type Payload
    = MemberCreated { memberId : Member.Id, name : String, memberType : Member.Type, addedBy : Member.Id, publicKey : String }
    | MemberRenamed { rootId : Member.Id, oldName : String, newName : String }
    | MemberRetired { rootId : Member.Id }
    | MemberUnretired { rootId : Member.Id }
    | MemberLinked { rootId : Member.Id, deviceId : Member.Id, publicKey : String, seq : Int }
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
wrap : Id -> Time.Posix -> Member.Id -> Payload -> String -> Envelope
wrap eventId clientTimestamp triggeredBy payload signature =
    refreshRaw
        { id = eventId
        , clientTimestamp = clientTimestamp
        , triggeredBy = triggeredBy
        , version = currentVersion
        , payload = payload
        , signature = signature
        , raw = Encode.null
        }


{-| Set the signature on a locally-authored envelope, keeping `raw` in sync.
-}
withSignature : String -> Envelope -> Envelope
withSignature signature envelope =
    refreshRaw { envelope | signature = signature }


{-| Rebuild `raw` from the decoded fields. Only valid for locally-authored
envelopes — on a received envelope this would discard unknown fields.
-}
refreshRaw : Envelope -> Envelope
refreshRaw envelope =
    { envelope
        | raw =
            Encode.object
                [ ( "id", Encode.string envelope.id )
                , ( "ts", Encode.int (Time.posixToMillis envelope.clientTimestamp) )
                , ( "by", Encode.string envelope.triggeredBy )
                , ( "v", Encode.int envelope.version )
                , ( "p", encodePayload envelope.payload )
                , ( "sig", Encode.string envelope.signature )
                ]
    }


{-| Build the list of payloads for creating a new group:
GroupCreated + MemberCreated for the creator + MemberCreated for each virtual member.
-}
createGroup : { name : String, defaultCurrency : Currency, creator : ( Member.Id, String ), virtualMembers : List ( Member.Id, String ), publicKey : String } -> List Payload
createGroup { name, defaultCurrency, creator, virtualMembers, publicKey } =
    let
        memberPayload : Member.Type -> String -> ( Member.Id, String ) -> Payload
        memberPayload memberType pk ( memberId, memberName ) =
            MemberCreated
                { memberId = memberId
                , name = memberName
                , memberType = memberType
                , addedBy = Tuple.first creator
                , publicKey = pk
                }
    in
    GroupCreated { name = name, defaultCurrency = defaultCurrency }
        :: memberPayload Member.Real publicKey creator
        :: List.map (memberPayload Member.Virtual "") virtualMembers


{-| Encode an Envelope as a JSON object — the raw value it was decoded
from (or built from at signing time), so unknown fields pass through.
-}
encodeEnvelope : Envelope -> Encode.Value
encodeEnvelope envelope =
    envelope.raw


{-| Decode an Envelope from JSON, keeping the raw value.
-}
envelopeDecoder : Decode.Decoder Envelope
envelopeDecoder =
    Decode.value
        |> Decode.andThen
            (\raw ->
                Decode.map5
                    (\id ts by v ( p, sig ) ->
                        { id = id
                        , clientTimestamp = ts
                        , triggeredBy = by
                        , version = v
                        , payload = p
                        , signature = sig
                        , raw = raw
                        }
                    )
                    (Decode.field "id" Decode.string)
                    (Decode.field "ts" (Decode.map Time.millisToPosix Decode.int))
                    (Decode.field "by" Decode.string)
                    (Decode.oneOf [ Decode.field "v" Decode.int, Decode.succeed 1 ])
                    (Decode.map2 Tuple.pair
                        (Decode.field "p" payloadDecoder)
                        (Decode.field "sig" Decode.string)
                    )
            )


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
                , ( "pk", Encode.string data.publicKey )
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

        MemberLinked data ->
            Encode.object
                [ ( "t", Encode.string "ml" )
                , ( "r", Encode.string data.rootId )
                , ( "d", Encode.string data.deviceId )
                , ( "pk", Encode.string data.publicKey )
                , ( "sq", Encode.int data.seq )
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
                        Decode.map5
                            (\mid name mt addedBy pk ->
                                MemberCreated
                                    { memberId = mid
                                    , name = name
                                    , memberType = mt
                                    , addedBy = addedBy
                                    , publicKey = pk
                                    }
                            )
                            (Decode.field "m" Decode.string)
                            (Decode.field "n" Decode.string)
                            (Decode.field "mt" Member.typeDecoder)
                            (Decode.field "ab" Decode.string)
                            (Decode.field "pk" Decode.string)

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

                    "ml" ->
                        Decode.map4
                            (\rid deviceId pk seq ->
                                MemberLinked
                                    { rootId = rid
                                    , deviceId = deviceId
                                    , publicKey = pk
                                    , seq = seq
                                    }
                            )
                            (Decode.field "r" Decode.string)
                            (Decode.field "d" Decode.string)
                            (Decode.field "pk" Decode.string)
                            (Decode.field "sq" Decode.int)

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


{-| Produce the canonical string representation of an envelope for signing:
the raw envelope JSON with the "sig" field removed, other fields kept in
their received order. Working from `raw` rather than re-encoding the
decoded payload keeps signatures valid on events carrying fields this
app version doesn't know about.
-}
canonicalize : Envelope -> String
canonicalize envelope =
    case Decode.decodeValue (Decode.keyValuePairs Decode.value) envelope.raw of
        Ok fields ->
            fields
                |> List.filter (\( key, _ ) -> key /= "sig")
                |> Encode.object
                |> Encode.encode 0

        Err _ ->
            -- Unreachable: raw is always a JSON object. An empty canonical
            -- string can never match a signature, which is the safe failure.
            ""
