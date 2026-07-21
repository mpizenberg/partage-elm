module Domain.MigrationCuration exposing (curateEvents)

{-| Drop events authored by excluded identities when re-homing a group during
migration (spec §11.7).

A group-key holder can inject validly-signed events — including as an existing
member, by self-linking a device (`MemberLinked` is not gated on the root's
consent, because self-linking is the device-recovery path). Such events pass
signature verification, so the re-key alone can't shed them; the migrator excises
them here by author. Excluding an author id removes everything it authored: a
self-created attacker member and its `MemberCreated`, or a grafted device and its
self-authored `MemberLinked`. What survives replays to a consistent state —
dangling modifications of a dropped entry are rejected on replay, reverting the
entry to its pre-attack form.

-}

import Domain.Event exposing (Envelope)
import Domain.Member as Member
import Set exposing (Set)


curateEvents : Set Member.Id -> List Envelope -> List Envelope
curateEvents excluded events =
    List.filter (\envelope -> not (Set.member envelope.triggeredBy excluded)) events
