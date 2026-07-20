module Domain.Compaction exposing (PendingApproval, manifest, pendingApprovals)

{-| Consensus-gated log consolidation (spec §14.9).

A compaction proposal commits to the exact history up to a boundary event
via a manifest hash. This module builds the hash's canonical input and
decides which proposals the local member still has to approve; hashing
(SHA-256, lowercase hex) happens at the call site since it is effectful.

-}

import Domain.Event as Event
import Domain.Member as Member
import Json.Encode as Encode


{-| The canonical manifest input for the history up to and including
`uptoEventId`: each envelope's raw JSON (as received, not re-encoded)
followed by a `\n`, concatenated in deterministic sort order. Hashing
envelope bytes rather than event ids prevents an author from swapping an
event's content behind a reused id.

Nothing when `uptoEventId` is not in the log — a proposal with an unknown
boundary can never be verified, so it can never be approved.

-}
manifest : Event.Id -> List Event.Envelope -> Maybe { input : String, eventCount : Int }
manifest uptoEventId events =
    prefixThrough uptoEventId events
        |> Maybe.map
            (\prefix ->
                { input = manifestInput prefix
                , eventCount = List.length prefix
                }
            )


{-| A proposal awaiting the local member's signature: sign an approval
exactly when SHA-256 of `manifestInput` equals `claimedHash`.
-}
type alias PendingApproval =
    { proposalId : Event.Id
    , claimedHash : String
    , manifestInput : String
    }


{-| The proposals the member `myRoot` still has to check and approve on
sync. A proposal qualifies when all of these hold:

  - it was authored by someone else (the proposal itself carries the
    proposer's required signature);
  - no approval by any of `myRoot`'s devices is in the log yet;
  - `myRoot` is an involved actor — author of at least one event in the
    compacted range — since only involved actors count toward quorum;
  - the boundary exists locally and the claimed event count matches.

The manifest hash itself is checked by the caller. `resolveRoot` maps an
event author (device or root id) to its root member.

-}
pendingApprovals : (Member.Id -> Maybe Member.Id) -> Member.Id -> List Event.Envelope -> List PendingApproval
pendingApprovals resolveRoot myRoot events =
    let
        isMine : Event.Envelope -> Bool
        isMine envelope =
            resolveRoot envelope.triggeredBy == Just myRoot

        approvedByMe : Event.Id -> Bool
        approvedByMe proposalId =
            List.any
                (\envelope ->
                    case envelope.payload of
                        Event.CompactionApproved approval ->
                            approval.proposalId == proposalId && isMine envelope

                        _ ->
                            False
                )
                events

        toPending : Event.Envelope -> { uptoEventId : Event.Id, eventCount : Int, manifestHash : String } -> Maybe PendingApproval
        toPending envelope proposal =
            if isMine envelope || approvedByMe envelope.id then
                Nothing

            else
                prefixThrough proposal.uptoEventId events
                    |> Maybe.andThen
                        (\prefix ->
                            if List.length prefix == proposal.eventCount && List.any isMine prefix then
                                Just
                                    { proposalId = envelope.id
                                    , claimedHash = proposal.manifestHash
                                    , manifestInput = manifestInput prefix
                                    }

                            else
                                Nothing
                        )
    in
    List.filterMap
        (\envelope ->
            case envelope.payload of
                Event.CompactionProposed proposal ->
                    toPending envelope proposal

                _ ->
                    Nothing
        )
        events


{-| The sorted (oldest-first) prefix through the boundary id; Nothing when
the boundary is absent.
-}
prefixThrough : Event.Id -> List Event.Envelope -> Maybe (List Event.Envelope)
prefixThrough boundaryId events =
    takeThrough boundaryId (Event.sortEvents events) []
        |> Maybe.map List.reverse


manifestInput : List Event.Envelope -> String
manifestInput prefix =
    prefix
        |> List.map (\envelope -> Encode.encode 0 envelope.raw ++ "\n")
        |> String.concat


{-| The prefix through the boundary id, accumulated newest-first;
Nothing when the boundary is absent.
-}
takeThrough : Event.Id -> List Event.Envelope -> List Event.Envelope -> Maybe (List Event.Envelope)
takeThrough boundaryId remaining acc =
    case remaining of
        [] ->
            Nothing

        envelope :: rest ->
            if envelope.id == boundaryId then
                Just (envelope :: acc)

            else
                takeThrough boundaryId rest (envelope :: acc)
