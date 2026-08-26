module Infra.Handoff exposing
    ( Destination
    , GroupHandoff
    , Payload
    , Plan
    , decoder
    , encode
    , fromString
    , merge
    )

{-| The profile one Partage installation hands to another: what cannot be
rebuilt from a relay (the identity and the group keys) plus the light state
that makes the destination feel like home. Event history is deliberately
absent — the destination pulls it from its own relay.

Today's transport is the domain migration (source app → destination app);
the payload and merge rules are transport-agnostic so a future
device-to-device transfer reuses them as-is.

-}

import Domain.Group as Group
import Domain.Member as Member
import Infra.Identity as Identity exposing (Identity)
import Json.Decode as Decode
import Json.Encode as Encode
import Set exposing (Set)


format : String
format =
    "partage-handoff-v1"


{-| One group's transferable state: its summary and its encryption key
(exported form, as stored in the key store).
-}
type alias GroupHandoff =
    { summary : Group.Summary
    , key : String
    }


type alias Payload =
    { identity : Identity
    , groups : List GroupHandoff
    , selfProfile : Member.Metadata
    , language : Maybe String
    , lastSeenChangelog : Maybe String
    }


encode : Payload -> Encode.Value
encode payload =
    Encode.object
        [ ( "format", Encode.string format )
        , ( "identity", Identity.encode payload.identity )
        , ( "groups"
          , Encode.list
                (\g ->
                    Encode.object
                        [ ( "summary", Group.encodeSummary g.summary )
                        , ( "key", Encode.string g.key )
                        ]
                )
                payload.groups
          )
        , ( "selfProfile", Member.encodeMetadata payload.selfProfile )
        , ( "language", maybeEncode Encode.string payload.language )
        , ( "lastSeenChangelog", maybeEncode Encode.string payload.lastSeenChangelog )
        ]


decoder : Decode.Decoder Payload
decoder =
    Decode.field "format" Decode.string
        |> Decode.andThen
            (\fmt ->
                if fmt == format then
                    Decode.map5 Payload
                        (Decode.field "identity" Identity.decoder)
                        (Decode.field "groups"
                            (Decode.list
                                (Decode.map2 GroupHandoff
                                    (Decode.field "summary" Group.summaryDecoder)
                                    (Decode.field "key" Decode.string)
                                )
                            )
                        )
                        (Decode.field "selfProfile" Member.metadataDecoder)
                        (Decode.field "language" (Decode.nullable Decode.string))
                        (Decode.field "lastSeenChangelog" (Decode.nullable Decode.string))

                else
                    Decode.fail ("Unknown format: " ++ fmt)
            )


{-| Parse a payload from raw text (a paste code, a message body). Tolerates
surrounding whitespace, which pasting tends to add.
-}
fromString : String -> Result String Payload
fromString raw =
    Decode.decodeString decoder (String.trim raw)
        |> Result.mapError (\_ -> "Unrecognized handoff payload")


{-| What the receiving installation already holds, reduced to what the merge
rules depend on.
-}
type alias Destination =
    { identity : Maybe Identity
    , existingGroupIds : Set Group.Id
    }


{-| The resolved outcome of receiving a payload. `identity` is what the
destination must store. `adopted` means the incoming identity replaced the
local one, so the incoming profile and settings apply too (`selfProfile`
is `Just` exactly then); otherwise the destination keeps its own identity —
extended with the incoming device ids so imported groups suggest the right
member to re-link as — and its own profile and settings.
-}
type alias Plan =
    { identity : Identity
    , adopted : Bool
    , groupsToAdd : List GroupHandoff
    , skippedGroupIds : List Group.Id
    , selfProfile : Maybe Member.Metadata
    , language : Maybe String
    , lastSeenChangelog : Maybe String
    }


{-| Merge rules. A destination with zero groups adopts the incoming identity
outright: an identity that never touched a group is referenced nowhere, so
replacing it loses nothing. A destination with groups is an installation in
its own right — it keeps its identity and only gains the groups it lacks.
Running the same payload twice converges: the second run skips every group
and appends no new device ids.
-}
merge : Payload -> Destination -> Plan
merge payload destination =
    let
        ( groupsToAdd, skippedGroups ) =
            List.partition
                (\g -> not (Set.member g.summary.id destination.existingGroupIds))
                payload.groups

        skippedGroupIds : List Group.Id
        skippedGroupIds =
            List.map (.summary >> .id) skippedGroups

        adopting : Bool
        adopting =
            Set.isEmpty destination.existingGroupIds
    in
    case ( adopting, destination.identity ) of
        ( False, Just own ) ->
            { identity =
                { own
                    | previousDeviceIds =
                        appendNewDeviceIds own
                            (payload.identity.publicKeyHash :: payload.identity.previousDeviceIds)
                }
            , adopted = False
            , groupsToAdd = groupsToAdd
            , skippedGroupIds = skippedGroupIds
            , selfProfile = Nothing
            , language = Nothing
            , lastSeenChangelog = Nothing
            }

        _ ->
            { identity = payload.identity
            , adopted = True
            , groupsToAdd = groupsToAdd
            , skippedGroupIds = skippedGroupIds
            , selfProfile = Just payload.selfProfile
            , language = payload.language
            , lastSeenChangelog = payload.lastSeenChangelog
            }


{-| Append incoming device ids that the identity does not already know as
itself or a predecessor, preserving order.
-}
appendNewDeviceIds : Identity -> List String -> List String
appendNewDeviceIds own incoming =
    let
        known : Set String
        known =
            Set.fromList (own.publicKeyHash :: own.previousDeviceIds)
    in
    own.previousDeviceIds
        ++ List.filter (\id -> not (Set.member id known)) (dedupe incoming)


dedupe : List String -> List String
dedupe ids =
    List.foldl
        (\id ( seen, acc ) ->
            if Set.member id seen then
                ( seen, acc )

            else
                ( Set.insert id seen, id :: acc )
        )
        ( Set.empty, [] )
        ids
        |> Tuple.second
        |> List.reverse


maybeEncode : (a -> Encode.Value) -> Maybe a -> Encode.Value
maybeEncode enc maybe =
    Maybe.map enc maybe |> Maybe.withDefault Encode.null
