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

`authorKey` (wire field "key") is the author's signing public key,
present only on envelopes that introduce it: the author's own
MemberCreated or MemberLinked. Keeping it at the envelope level — part of
the frozen envelope contract rather than the evolvable payload — lets
signature verification learn keys even from payloads it cannot decode.

-}
type alias Envelope =
    { id : Id
    , clientTimestamp : Time.Posix
    , triggeredBy : Member.Id
    , version : Int
    , authorKey : Maybe String
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

`Unknown` is any payload this app version cannot decode — typically an
event authored by a newer version. The envelope still verifies and round
trips via its raw JSON; state computation ignores it. Never authored
locally.

`CompactionProposed` and `CompactionApproved` are the consensus gate for
log consolidation (spec §14.9): a proposal commits to the exact history up
to `uptoEventId` via `manifestHash` (see Domain.Compaction), and each
approval is a member's signed attestation that its own replica matches.
They carry no user-visible meaning: state computation and the activity
feed ignore them.

-}
type Payload
    = Unknown
    | MemberCreated { memberId : Member.Id, name : String, memberType : Member.Type, addedBy : Member.Id }
    | MemberRenamed { rootId : Member.Id, oldName : String, newName : String }
    | MemberRetired { rootId : Member.Id }
    | MemberUnretired { rootId : Member.Id }
    | MemberLinked { rootId : Member.Id, deviceId : Member.Id, seq : Int }
    | MemberMetadataUpdated { rootId : Member.Id, metadata : Member.Metadata }
    | EntryAdded Entry
    | EntryModified Entry
    | EntryDeleted { rootId : Entry.Id }
    | EntryUndeleted { rootId : Entry.Id }
    | GroupCreated { name : String, defaultCurrency : Currency }
    | GroupMetadataUpdated GroupMetadataChange
    | SettlementPreferencesUpdated { memberRootId : Member.Id, preferredRecipients : List Member.Id }
    | CompactionProposed { uptoEventId : Id, eventCount : Int, manifestHash : String }
    | CompactionApproved { proposalId : Id }


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


{-| Wrap a payload into an envelope authored by the given device.
The author's signing key is stamped on the envelope ("key" field) exactly
when the payload introduces it: the author's own MemberCreated or
MemberLinked.
-}
wrap : Id -> Time.Posix -> { id : Member.Id, publicKey : String } -> Payload -> String -> Envelope
wrap eventId clientTimestamp author payload signature =
    refreshRaw
        { id = eventId
        , clientTimestamp = clientTimestamp
        , triggeredBy = author.id
        , version = currentVersion
        , authorKey =
            if author.publicKey /= "" && introducesAuthorKey author.id payload then
                Just author.publicKey

            else
                Nothing
        , payload = payload
        , signature = signature
        , raw = Encode.null
        }


introducesAuthorKey : Member.Id -> Payload -> Bool
introducesAuthorKey authorId payload =
    case payload of
        MemberCreated data ->
            data.memberId == authorId

        MemberLinked data ->
            data.deviceId == authorId

        _ ->
            False


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
                ([ ( "id", Encode.string envelope.id )
                 , ( "ts", Encode.int (Time.posixToMillis envelope.clientTimestamp) )
                 , ( "by", Encode.string envelope.triggeredBy )
                 , ( "v", Encode.int envelope.version )
                 ]
                    ++ (case envelope.authorKey of
                            Just publicKey ->
                                [ ( "key", Encode.string publicKey ) ]

                            Nothing ->
                                []
                       )
                    ++ [ ( "p", encodePayload envelope.payload )
                       , ( "sig", Encode.string envelope.signature )
                       ]
                )
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
                Decode.map6
                    (\id ts by v key ( p, sig ) ->
                        { id = id
                        , clientTimestamp = ts
                        , triggeredBy = by
                        , version = v
                        , authorKey = key
                        , payload = p
                        , signature = sig
                        , raw = raw
                        }
                    )
                    (Decode.field "id" Decode.string)
                    (Decode.field "ts" (Decode.map Time.millisToPosix Decode.int))
                    (Decode.field "by" Decode.string)
                    (Decode.oneOf [ Decode.field "v" Decode.int, Decode.succeed 1 ])
                    (Decode.oneOf [ Decode.map Just (Decode.field "key" Decode.string), Decode.succeed Nothing ])
                    (Decode.map2 Tuple.pair
                        -- A payload that fails to decode (unknown type, or a
                        -- known type whose shape changed) becomes Unknown
                        -- instead of failing the envelope.
                        (Decode.field "p" (Decode.oneOf [ payloadDecoder, Decode.succeed Unknown ]))
                        (Decode.field "sig" Decode.string)
                    )
            )


{-| Encode a Payload as a tagged JSON object with a "type" discriminator.
-}
encodePayload : Payload -> Encode.Value
encodePayload payload =
    case payload of
        Unknown ->
            -- Never reached: Unknown is never authored locally, and received
            -- envelopes encode via their raw JSON, not via encodePayload.
            Encode.null

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

        MemberLinked data ->
            Encode.object
                [ ( "t", Encode.string "ml" )
                , ( "r", Encode.string data.rootId )
                , ( "d", Encode.string data.deviceId )
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

        CompactionProposed data ->
            Encode.object
                [ ( "t", Encode.string "cp" )
                , ( "u", Encode.string data.uptoEventId )
                , ( "n", Encode.int data.eventCount )
                , ( "h", Encode.string data.manifestHash )
                ]

        CompactionApproved data ->
            Encode.object
                [ ( "t", Encode.string "ca" )
                , ( "pid", Encode.string data.proposalId )
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

                    "ml" ->
                        Decode.map3
                            (\rid deviceId seq ->
                                MemberLinked
                                    { rootId = rid
                                    , deviceId = deviceId
                                    , seq = seq
                                    }
                            )
                            (Decode.field "r" Decode.string)
                            (Decode.field "d" Decode.string)
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

                    "cp" ->
                        Decode.map3
                            (\upto count hash ->
                                CompactionProposed
                                    { uptoEventId = upto
                                    , eventCount = count
                                    , manifestHash = hash
                                    }
                            )
                            (Decode.field "u" Decode.string)
                            (Decode.field "n" Decode.int)
                            (Decode.field "h" Decode.string)

                    "ca" ->
                        Decode.map (\pid -> CompactionApproved { proposalId = pid })
                            (Decode.field "pid" Decode.string)

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
