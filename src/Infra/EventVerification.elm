module Infra.EventVerification exposing (filterVerifiedEvents)

{-| Signature verification for event envelopes.

Collects public keys from MemberCreated/MemberReplaced events and existing
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


{-| Collect all known public keys from existing group state members.
-}
collectKeysFromState : GroupState.GroupState -> Dict Member.Id String
collectKeysFromState state =
    Dict.foldl
        (\_ chain acc ->
            Dict.foldl
                (\memberId info innerAcc ->
                    if info.publicKey /= "" then
                        Dict.insert memberId info.publicKey innerAcc

                    else
                        innerAcc
                )
                acc
                chain.allMembers
        )
        Dict.empty
        state.members


{-| Extract public key from a MemberCreated or MemberReplaced event payload.
-}
collectKeyFromEvent : Envelope -> Dict Member.Id String -> Dict Member.Id String
collectKeyFromEvent envelope keys =
    case envelope.payload of
        MemberCreated data ->
            if data.publicKey /= "" then
                Dict.insert data.memberId data.publicKey keys

            else
                keys

        MemberReplaced data ->
            if data.publicKey /= "" then
                Dict.insert data.newId data.publicKey keys

            else
                keys

        _ ->
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
