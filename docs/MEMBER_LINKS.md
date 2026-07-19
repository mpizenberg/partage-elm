# Member device links

Design record for the member-model re-architecture that replaced replacement
chains (`MemberReplaced`) with direct device→root links (`MemberLinked`).
The normative rules live in [SPECIFICATION.md §4](SPECIFICATION.md#4-member-management);
this document records the motivation and the reasoning behind the rules.

## Motivation

With replacement chains, a device that claimed the wrong member at join time
(issue #1) was stuck: replaced members were terminal, the claiming device was
welded into the chain, and there was no revert event. Fixing a wrong claim
required designing chain surgery.

Everything in the app — entries, balances, merges, retirement, metadata —
already referenced members by `rootId`. The chain existed only to (a) map
device keys to a root and (b) pick a "current member" by depth. A direct
`device → root` map covers both.

## Model

- A **root** is a person: created once by `MemberCreated`, identified forever
  by its `rootId`. Real roots carry the creating device's public key (their
  `rootId` is that key's hash); virtual roots have no key.
- A **link** is a device claim: `MemberLinked { rootId, deviceId, publicKey, seq }`
  asserts "this device acts as this root". A device has at most one effective
  link — its latest — so it can only ever point at one root.
- **Virtual vs. claimed is derived**: a root shows as virtual when it was
  created virtual and no device currently links to it. Claiming makes it real;
  re-linking away makes it virtual again. No terminal states.

## Link resolution

Per device, the winning link is the one with the highest
`(seq, timestamp, event id)` — compared in that order. Rationale:

- `seq` is a per-device monotonic counter (next = winner's seq + 1, or 0).
  It makes a device's own re-links robust to its clock jumping backwards,
  which client timestamps alone are not.
- Timestamp and event id only break ties between events a single device signed
  with the same seq (e.g. produced on divergent replicas of the same identity);
  event ids are unique, so the order is total and replay is deterministic
  regardless of arrival order.

Resolving an id to a root checks the device-link map first, then falls back to
root identity. Link precedence matters for the "joined as new, should have
claimed" case: the device's own root still exists (with its history), but the
device now acts as the link target. Moving *entries* off the abandoned root
remains the member-merge flow's job.

## Authorization and verification

- Only the device itself may link itself (`deviceId == triggeredBy`), exactly
  the self-assertion rule `MemberReplaced` had — the hijack surface is
  unchanged. The event is signature-verified against the device's own key
  (`deviceId` is the key's hash).
- Verification keys are collected from real roots (`MemberCreated`) and from
  links (`MemberLinked`). Re-linking never changes a device's key, so
  historical signatures stay valid.
- A link to an unknown root is ignored during replay (same as every other
  reference to a missing entity).

## UI flows

- **Join (invite link):** unchanged — claim a virtual member (primary), recover
  a real member, or join as new. Claiming emits `MemberLinked` instead of
  `MemberReplaced`.
- **Fix a wrong claim:** the member detail card in the Members tab offers
  "This is me", which emits a new link to that member. The previously claimed
  member is vacated automatically. Reversible by linking back.
