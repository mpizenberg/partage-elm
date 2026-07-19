# Fix review findings 2 and 3b — tolerant decoding and forward compatibility

Fixes two **[BREAKING]** findings from `plan/REVIEW_2026-07-19.md` that must
ship in the launch build:

- **Finding 2 (S0):** one undecodable event record permanently bricks a
  group's sync (batch decode fails wholesale, cursor never advances).
- **Finding 3b (S1):** no forward-compatibility mechanism — the first
  post-launch schema change breaks existing clients (unknown event type
  bricks sync; unknown field on a known type breaks the signature because
  `canonicalize` re-encodes the decoded payload).

## Chosen design (user-confirmed)

- **Unknown-payload variant:** events whose payload fails to decode become
  `Payload.Unknown`. The envelope still verifies (signatures are checked
  against the raw received JSON), persists raw in IndexedDB, and is ignored
  by state replay. After the app updates, the same stored raw JSON decodes
  normally — self-healing, offline, no data loss.
- **Raw-envelope passthrough:** `Envelope` carries the raw JSON it was
  decoded from; `encodeEnvelope` returns it verbatim, so unknown fields
  survive push, storage, and export. `canonicalize` re-encodes the raw
  envelope minus `sig`, so *envelope-level* field additions are also safe,
  not just payload-level ones.
- **Schema-version field:** envelopes carry `"v": 1` (absent = 1) for
  precise "update required" messaging later.
- **Surfacing:** a persistent banner in the group view while the loaded
  group contains Unknown events ("some changes need a newer app version").
  Undecryptable/garbage records are skipped with an ErrorLog entry only.

## Progress

1. Done — Envelope carries `version` + `raw`; encoding/storage/canonicalize
   go through raw; signatures verified against received bytes; tests added
   for unknown-field passthrough and canonical-shape stability.
2. Done — `Payload.Unknown` + `Activity.UnknownDetail` (activity feed shows
   a translated "can't display — update" line); pull skips and counts
   undecryptable records and undecodable envelopes (`PullResult.undecodable`)
   and logs the count to ErrorLog on sync success.

## Increments

1. **Raw envelope + version field.** `Envelope` gains `version : Int` and
   `raw : Encode.Value`. `envelopeDecoder` captures the raw value;
   `encodeEnvelope` returns it; `canonicalize` re-encodes raw minus `sig`
   (key order preserved via `Decode.keyValuePairs`); `wrap` and a new
   `withSignature` keep raw in sync for locally-authored events. Local
   events store as `{ id, groupId, env: <raw> }` in IndexedDB. Payload
   decoding stays strict in this increment.
2. **Unknown payload + tolerant pull.** `Payload` gains `Unknown`; a `"p"`
   that fails `payloadDecoder` decodes as `Unknown` instead of failing the
   envelope. Server pull becomes per-item tolerant: records that fail to
   decrypt and envelopes that fail shape decode are skipped and counted;
   `PullResult` carries the count; `Page.Group` logs it to ErrorLog. All
   `case` sites on `Payload` ignore `Unknown` (compiler-driven).
3. **Banner.** Group view shows a persistent translated notice while
   `loadedGroup.events` contains any `Unknown` payload.
4. **Docs.** Update `docs/SPECIFICATION.md` §signature/canonicalization and
   sync sections; mark findings 2 and 3b **[FIXED]** in the review doc.

## Decisions

- Unknown events appear in the activity feed as a generic translated
  "can't display — update the app" line (`Activity.UnknownDetail`) instead
  of being hidden. Hiding was rejected: `payloadToDetail` would need a
  bogus neutral value anyway, and feed visibility complements the banner.

- Any `"p"` decode failure becomes `Unknown` — including a *known* type
  whose fields fail to decode. Alternative (only unknown `"t"` tags) was
  rejected: a future version changing a known type's shape would otherwise
  still brick, and excluded-from-state is the right outcome either way.
- Undecryptable records are always skipped (with count + ErrorLog), even if
  every record in a pull fails. Alternative — hard-fail when all records
  fail, as a wrong-key guard — rejected: the group key is immutable after
  join (genesis decrypt would have failed at join time), and the guard
  would re-brick the single-garbage-record case the fix exists for.
- Envelope-shape failures (missing `id`/`ts`/`by`/`sig`) are skipped, not
  quarantined: without identity and ordering the event cannot be stored
  meaningfully. Envelope-level *additions* are covered by raw
  canonicalization; envelope-level breaking changes need a new `"v"`.
- Local events store shape changes to `{ id, groupId, env }` without
  migration. Pre-launch data at the old origin will fail to load; the
  re-launch is a clean break at a new origin (fresh IndexedDB).
- A member introduced by an event an old client can't decode (e.g. a future
  MemberCreated variant) has no public key on that client, so that member's
  *subsequent* events are dropped by verification until the app updates.
  Accepted: the banner covers the "update needed" state. Those dropped
  events are only recoverable via a full re-pull (the server retains
  everything); no automatic re-pull is wired up for this edge.
