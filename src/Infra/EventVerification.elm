module Infra.EventVerification exposing (filterVerifiedEvents)

{-| Signature verification for event envelopes.

Collects public keys from the envelopes' "key" field and existing
GroupState, then verifies signatures. Events with invalid or unverifiable
signatures are silently dropped. GroupCreated events are exempt (genesis
events with no prior public key).

-}

import ConcurrentTask exposing (ConcurrentTask)
import Dict exposing (Dict)
import Domain.Event as Event exposing (Envelope, Payload(..))
import Domain.GroupState as GroupState
import Domain.Member as Member
import WebCrypto.Signature as Signature


{-| Verify signatures on a list of events and return only the valid ones.
Genesis events (GroupCreated) pass through without verification.
Events with missing public keys or invalid signatures are dropped.
-}
filterVerifiedEvents : GroupState.GroupState -> List Envelope -> ConcurrentTask x (List Envelope)
filterVerifiedEvents state events =
    let
        allKeys : Dict Member.Id String
        allKeys =
            List.foldl collectKeyFromEvent (collectKeysFromState state) events
    in
    List.map (verifyOne allKeys) events
        |> ConcurrentTask.batch
        |> ConcurrentTask.map (List.filterMap identity)


{-| Check if an event is a genesis event (GroupCreated), which is exempt
from signature verification.
-}
isGenesisEvent : Envelope -> Bool
isGenesisEvent envelope =
    case envelope.payload of
        GroupCreated _ ->
            True

        _ ->
            False


{-| Collect all known public keys from existing group state: real roots'
own keys plus the keys of linked devices.
-}
collectKeysFromState : GroupState.GroupState -> Dict Member.Id String
collectKeysFromState state =
    let
        insertKey : Member.Id -> String -> Dict Member.Id String -> Dict Member.Id String
        insertKey memberId publicKey acc =
            if publicKey /= "" then
                Dict.insert memberId publicKey acc

            else
                acc

        rootKeys : Dict Member.Id String
        rootKeys =
            Dict.foldl (\rootId member acc -> insertKey rootId member.publicKey acc)
                Dict.empty
                state.members
    in
    Dict.foldl (\deviceId link acc -> insertKey deviceId link.publicKey acc)
        rootKeys
        state.deviceLinks


{-| Collect the author's signing key introduced by an envelope ("key"
field). Envelope-level, so it works even when the payload is one this app
version cannot decode.
-}
collectKeyFromEvent : Envelope -> Dict Member.Id String -> Dict Member.Id String
collectKeyFromEvent envelope keys =
    case envelope.authorKey of
        Just publicKey ->
            if publicKey /= "" then
                Dict.insert envelope.triggeredBy publicKey keys

            else
                keys

        Nothing ->
            keys


{-| Verify a single envelope. Returns Just envelope if valid, Nothing if invalid.
Genesis events always pass. Verification errors are caught and treated as invalid.
-}
verifyOne : Dict Member.Id String -> Envelope -> ConcurrentTask x (Maybe Envelope)
verifyOne keys envelope =
    if isGenesisEvent envelope then
        ConcurrentTask.succeed (Just envelope)

    else
        case Dict.get envelope.triggeredBy keys of
            Nothing ->
                -- No public key available — drop the event
                ConcurrentTask.succeed Nothing

            Just publicKey ->
                Signature.verifyText publicKey envelope.signature (Event.canonicalize envelope)
                    |> ConcurrentTask.map
                        (\valid ->
                            if valid then
                                Just envelope

                            else
                                Nothing
                        )
                    |> ConcurrentTask.onError (\_ -> ConcurrentTask.succeed Nothing)
