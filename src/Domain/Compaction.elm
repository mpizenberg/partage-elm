module Domain.Compaction exposing (manifest)

{-| Consensus-gated log consolidation (spec §14.9).

A compaction proposal commits to the exact history up to a boundary event
via a manifest hash. This module builds the hash's canonical input; hashing
(SHA-256, lowercase hex) happens at the call site since it is effectful.

-}

import Domain.Event as Event
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
    takeThrough uptoEventId (Event.sortEvents events) []
        |> Maybe.map
            (\prefix ->
                { input =
                    List.reverse prefix
                        |> List.map (\envelope -> Encode.encode 0 envelope.raw ++ "\n")
                        |> String.concat
                , eventCount = List.length prefix
                }
            )


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
