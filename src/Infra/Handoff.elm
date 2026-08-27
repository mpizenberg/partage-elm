module Infra.Handoff exposing
    ( Destination
    , GroupHandoff
    , Payload
    , Plan
    , encode
    , fromString
    , merge
    )

{-| The profile one Partage installation hands to another: what no relay can
rebuild (identity, group keys) plus light settings. History stays out — the
destination pulls it from its own relay. Transport-agnostic, so a future
device-to-device transfer reuses it as-is.
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


{-| What the destination must store. Adoption carries everything that belongs
to replacing the local identity; keeping the local identity has no adoption
data.
-}
type alias Plan =
    { identity : Identity
    , adoption :
        Maybe
            { selfProfile : Member.Metadata
            , language : Maybe String
            , lastSeenChangelog : Maybe String
            }
    , groupsToAdd : List GroupHandoff
    , skippedGroupIds : List Group.Id
    }


{-| A destination with zero groups adopts the incoming identity: its own is
referenced nowhere, so replacing it loses nothing. One with groups is an
installation in its own right and only gains the groups it lacks. Re-running
the same payload converges.
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
            , adoption = Nothing
            , groupsToAdd = groupsToAdd
            , skippedGroupIds = skippedGroupIds
            }

        _ ->
            { identity = payload.identity
            , adoption =
                Just
                    { selfProfile = payload.selfProfile
                    , language = payload.language
                    , lastSeenChangelog = payload.lastSeenChangelog
                    }
            , groupsToAdd = groupsToAdd
            , skippedGroupIds = skippedGroupIds
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
