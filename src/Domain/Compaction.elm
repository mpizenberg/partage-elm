module Domain.Compaction exposing
    ( Executable
    , PendingApproval
    , chunkEnvelopes
    , executableProposal
    , manifest
    , pendingApprovals
    , proposalCooldownMs
    , proposalDraft
    , recordCountTrigger
    )

{-| Consensus-gated log consolidation (spec §14.9).

A compaction proposal commits to the exact history up to a boundary event
via a manifest hash. This module holds the pure policy: the hash's
canonical input, which proposals the local member still has to approve,
when a proposal has quorum, and when to make one. Hashing (SHA-256,
lowercase hex) happens at the call sites since it is effectful.

-}

import Domain.Event as Event
import Domain.Member as Member
import Json.Encode as Encode
import Set exposing (Set)
import Time


{-| Propose (and execute) only while the relay holds at least this many
records. A consolidated history is a handful of records, so any honest
group past this is worth compacting; anything below syncs in a few pages
anyway.
-}
recordCountTrigger : Int
recordCountTrigger =
    500


{-| Do not re-propose while a proposal younger than this exists: quorum
takes however long members take to sync, and duplicate proposals just
multiply approval traffic.
-}
proposalCooldownMs : Int
proposalCooldownMs =
    7 * 24 * 60 * 60 * 1000


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


{-| A quorumed proposal ready for execution, provided the executor's own
manifest hash matches `claimedHash` — an executor must never consolidate a
history its replica disagrees with. `prefix` is the manifested history to
re-pack, sorted oldest-first.
-}
type alias Executable =
    { proposalId : Event.Id
    , claimedHash : String
    , manifestInput : String
    , prefix : List Event.Envelope
    }


{-| The newest proposal whose quorum is visible in the log: strictly more
than half of the non-retired involved actors (authors of at least one
event in the compacted range, resolved to roots) have signed — the
proposal itself carrying the proposer's signature, each approval one
co-signature. Approvals from uninvolved members carry no quorum weight.
-}
executableProposal :
    { resolveRoot : Member.Id -> Maybe Member.Id, isRetired : Member.Id -> Bool }
    -> List Event.Envelope
    -> Maybe Executable
executableProposal { resolveRoot, isRetired } events =
    let
        approverRoots : Event.Id -> Member.Id -> Set Member.Id
        approverRoots proposalId proposerRoot =
            List.foldl
                (\envelope acc ->
                    case envelope.payload of
                        Event.CompactionApproved approval ->
                            if approval.proposalId == proposalId then
                                case resolveRoot envelope.triggeredBy of
                                    Just root ->
                                        Set.insert root acc

                                    Nothing ->
                                        acc

                            else
                                acc

                        _ ->
                            acc
                )
                (Set.singleton proposerRoot)
                events

        toExecutable : Event.Envelope -> { uptoEventId : Event.Id, eventCount : Int, manifestHash : String } -> Maybe Executable
        toExecutable envelope proposal =
            Maybe.map2 Tuple.pair
                (resolveRoot envelope.triggeredBy)
                (prefixThrough proposal.uptoEventId events)
                |> Maybe.andThen
                    (\( proposerRoot, prefix ) ->
                        let
                            involved : Set Member.Id
                            involved =
                                prefix
                                    |> List.filterMap (\e -> resolveRoot e.triggeredBy)
                                    |> List.filter (\root -> not (isRetired root))
                                    |> Set.fromList

                            signers : Int
                            signers =
                                Set.intersect (approverRoots envelope.id proposerRoot) involved
                                    |> Set.size
                        in
                        if List.length prefix == proposal.eventCount && 2 * signers > Set.size involved then
                            Just
                                { proposalId = envelope.id
                                , claimedHash = proposal.manifestHash
                                , manifestInput = manifestInput prefix
                                , prefix = prefix
                                }

                        else
                            Nothing
                    )
    in
    Event.sortEvents events
        |> List.reverse
        |> List.filterMap
            (\envelope ->
                case envelope.payload of
                    Event.CompactionProposed proposal ->
                        toExecutable envelope proposal

                    _ ->
                        Nothing
            )
        |> List.head


{-| The proposal to make when the relay is worth compacting: the full
local log as the manifested range. Nothing while a proposal younger than
the cooldown exists (quorum needs time; duplicates only add traffic) or
when the log is empty.
-}
proposalDraft : Time.Posix -> List Event.Envelope -> Maybe { uptoEventId : Event.Id, eventCount : Int, manifestInput : String }
proposalDraft now events =
    let
        newestProposalMs : Maybe Int
        newestProposalMs =
            events
                |> List.filterMap
                    (\envelope ->
                        case envelope.payload of
                            Event.CompactionProposed _ ->
                                Just (Time.posixToMillis envelope.clientTimestamp)

                            _ ->
                                Nothing
                    )
                |> List.maximum

        coolingDown : Bool
        coolingDown =
            case newestProposalMs of
                Just ms ->
                    Time.posixToMillis now - ms < proposalCooldownMs

                Nothing ->
                    False

        sorted : List Event.Envelope
        sorted =
            Event.sortEvents events
    in
    case ( coolingDown, List.reverse sorted ) of
        ( False, newest :: _ ) ->
            Just
                { uptoEventId = newest.id
                , eventCount = List.length sorted
                , manifestInput = manifestInput sorted
                }

        _ ->
            Nothing


{-| Pack envelopes into consolidation batches whose summed raw-JSON size
stays under `maxBytes` (an oversized single envelope gets its own batch).
Order is preserved.
-}
chunkEnvelopes : Int -> List Event.Envelope -> List (List Event.Envelope)
chunkEnvelopes maxBytes envelopes =
    let
        step : Event.Envelope -> { chunks : List (List Event.Envelope), current : List Event.Envelope, size : Int } -> { chunks : List (List Event.Envelope), current : List Event.Envelope, size : Int }
        step envelope acc =
            let
                envelopeSize : Int
                envelopeSize =
                    String.length (Encode.encode 0 envelope.raw)
            in
            if acc.size + envelopeSize > maxBytes && not (List.isEmpty acc.current) then
                { chunks = List.reverse acc.current :: acc.chunks, current = [ envelope ], size = envelopeSize }

            else
                { chunks = acc.chunks, current = envelope :: acc.current, size = acc.size + envelopeSize }

        final : { chunks : List (List Event.Envelope), current : List Event.Envelope, size : Int }
        final =
            List.foldl step { chunks = [], current = [], size = 0 } envelopes
    in
    if List.isEmpty final.current then
        List.reverse final.chunks

    else
        List.reverse (List.reverse final.current :: final.chunks)


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
