# Storage Growth & Performance Report

Exploration of how to prevent unbounded storage growth and improve
performance, on the relay (server) side and the client (user) side.
Written against the 2026-07 codebase; follows up review finding 21
("server storage only ever grows"). Revised 2026-07-20 to incorporate
the compromised-member threat model (§3), which reshapes the deletion
and compaction designs.

## TL;DR

- Organic per-group growth is tiny (~1–2 MB/year for a *busy* group).
  The real growth drivers are **dead groups that are never deleted**,
  **duplicate records from sync-retry bugs**, and **abuse** (no quota).
  Those are all fixable with cheap, non-breaking server changes.
- **Threat model (§3): a compromised member must not be able to destroy
  or rewrite group history.** Read access is unpreventable (they hold
  the key), and the relay cannot tell members apart (shared bearer
  secret), so destructive relay operations must be *absent*,
  *consensus-gated via multi-signed events*, or at worst *detectable
  and healable* by honest members' full replicas. This kills the
  member-triggered delete route and adds a signature quorum to
  compaction.
- The only lever that caps growth for long-lived active groups is
  **compaction**. A *state-snapshot* scheme would be breaking and
  trust-damaging — rejected. A *log-consolidation* scheme (re-batch raw
  envelopes into a few large records) is **compatible with the existing
  pull/merge protocol** and preserves signatures, audit trail, and
  activity feed. Under §3 it is gated by a **multi-signed compaction
  manifest** (all involved authors, ≥50% floor) recorded in the log
  itself, and anchored for new joiners by an attestation carried in the
  invite link.
- On the client, storage is not the problem — **durability and replay
  cost** are. The app never calls `navigator.storage.persist()`, so the
  browser may evict the local event log (the actual system of record).
  Every group open replays the full log from scratch; spec §14.6
  promises a persisted computed-state cache that the code does not have.
- Guiding principle: **the relay is a cache; the clients are the system
  of record.** Every member holds the full log and the key, so honest
  members can restore a purged or truncated relay copy by re-pushing.
  This licenses an aggressive server retention policy — provided
  clients are made durable (persist + export nudges) and the protocol
  gains a cursor reset-and-heal flow. Under §3 the replicas do double
  duty: they are also what makes history destruction non-permanent.

## 1. Where bytes live today

**Server.** One row per pushed record: `{seq, group_id, actor_id, data,
compressed, created}` (`packages/relay/src/storage-do.js`,
`storage-sqlite.js`). `data` is a base64 AES-256-GCM blob containing a
gzip-compressed *batch* of one or more event envelopes (batch flush
every ~100 s, on explicit actions, and on reconnect). Records are
capped at 1 MB; pull is paginated at 200 records/page. There is no
delete route, no TTL, no quota, no vacuum. Cloudflare: one Durable
Object per group (billed for storage, requests, duration); self-host:
one SQLite file for all groups (WAL, never shrinks without VACUUM).

**Client.** IndexedDB, one row per event (`{id, groupId, env}` with the
raw envelope JSON stored verbatim for forward compatibility), plus
group summaries, keys, cursors, unpushed-id sets
(`src/Infra/Storage.elm`). Opening a group loads all rows and replays
from `GroupState.empty` (`src/Main.elm:814`); sync merges apply
incrementally with a conflict-triggered full rebuild
(`src/GroupOps.elm`).

## 2. Growth model — what actually grows

Order-of-magnitude estimate (unmeasured; see §8 on benchmarking): an
entry envelope with short wire keys is ~400–800 bytes of JSON;
encryption + base64 adds ~40%, gzip takes most of that back. Call it
**~0.5–1 KB per event on the server**. A group logging 1 000 entries a
year with edits lands around 1–2 MB/year. A typical group is far below
that. Honest usage will not fill anyone's disk for years.

What actually drives growth:

1. **Dead groups.** A group deleted on every client still occupies its
   rows (and its Durable Object) forever. This is the only driver that
   scales with *total groups ever created* rather than with activity.
2. **Duplicate records.** Finding 11 (pull failure after successful
   push → re-push) and the S3 note about switching groups mid-sync
   (skipped `postSyncTasks` → cursor/unpushed not persisted) both
   re-push already-stored batches. Clients dedup by event id on pull,
   so the duplicates are invisible — and immortal — on the server.
3. **Abuse.** The bearer secret is derived from the group key, PoW
   gates only group *creation*, and there is no per-group quota: any
   key holder can append 1 MB records in a loop. Separately, on
   Cloudflare any unauthenticated request to a fresh group id
   materializes a billable DO (S3 relay-hardening note).
4. **Record fragmentation** (a size multiplier, not a driver): in
   trickle usage every entry flushes as its own record, so record count
   ≈ event count, and per-record gzip cannot exploit cross-event
   redundancy (repeated member ids, keys, JSON structure). One-by-one
   records compress far worse than the same history re-compressed as a
   whole — this is what consolidation (§5) reclaims.

Client-side, the same organic curve applies against browser quotas
measured in gigabytes: local *space* is a non-issue for years. The
client problems are durability (§6) and time (§7), not bytes.

## 3. Threat model: the compromised member

Assume any member's device — and therefore their signing key and the
group key — may fall into hostile hands. Read access is then
unpreventable: the attacker holds the group key, and key immutability
means there is no rotation. The line to defend is the **history**:
destroying or rewriting it must be impossible, or require member
consensus, or — where the relay's design makes prevention impossible —
be reliably detectable and healable by honest members.

**The constraint that shapes everything: the relay authenticates the
group, not the member.** The bearer secret is derived from the group
key, so every key holder looks identical to the server, and signatures
live inside encrypted blobs the server cannot read. Server-side
member-level authorization or quorum verification is therefore
impossible without per-member server identities — a membership-metadata
leak the zero-knowledge design deliberately avoids, rejected here for
the same reason. Consequence: **any destructive relay operation is
available to every key holder or to nobody.** That yields a three-rung
enforcement ladder, best first:

1. **Impossible** — don't ship the operation (no member-triggered
   delete route, §4.2).
2. **Consensus-gated, client-verified** — the operation is authorized
   by multi-signed events in the log; clients, not the server, verify
   the quorum (compaction, §5.2).
3. **Detect and heal** — for relay-level truncation that cannot be
   prevented (a bearer holder abusing the compact route, a hostile
   relay): honest members hold full replicas, notice missing events,
   and re-push them (§4.4).

**What already holds up.** The existing design is a strong baseline:

- Per-event signatures + key immutability mean a compromised member
  cannot forge other members' events or take over their identities;
  forged events are dropped at pull, join-fetch, and import time.
- The event vocabulary is append-only and non-destructive: entries are
  tombstoned and restorable (`EntryDeleted`/`EntryUndeleted`), members
  are retired, never erased (`MemberRetired`/`MemberUnretired`)
  (`src/Domain/Event.elm:65-76`). Content vandalism — junk entries,
  renames, mass tombstoning — remains possible, but it is signed,
  attributed in the activity feed, and reversible from the log. That is
  the model working as intended; this report defends the log itself.
- The merge never deletes: pulled data can only *add* to the local log
  (dedup by id, `src/GroupOps.elm`). No relay response can make a
  client discard events, so honest members' replicas are out of the
  attacker's reach entirely.

**Gaps the rest of this report must close:**

- *Healing is not implemented.* `unpushedIds` tracks only never-pushed
  events; re-pushing already-pushed events the relay has lost has no
  code path today. Rung 3 needs one (§4.4).
- *Joining is the weak moment.* A new joiner has no prior replica to
  compare against, so truncation is invisible to them. Their trust
  anchor must ride the invite link (§5.2).

## 4. Server: cheap, non-breaking measures

Ordered by value/effort. All are additive protocol changes.

### 4.1 Idempotent append

Client sends a `recordId` (fresh UUID per batch) with each push; server
adds `UNIQUE(group_id, record_id)` and, on conflict, returns the
existing `seq` instead of inserting. This closes the storage side of
finding 11 and every future retry bug in one stroke: pushes become
retry-safe by construction instead of by careful client bookkeeping.
Old clients that omit the field keep today's behavior.

### 4.2 No member-triggered deletion

An earlier draft proposed `DELETE /api/groups/:id` behind the bearer
secret. **Rejected under §3**: the server cannot tell members apart, so
the route hands every key holder — including a compromised one — a
one-request destroy button for the relay copy. Recoverability (honest
members re-push, §4.4) softens the blow but does not excuse the route:
recovery requires an honest member to sync, and anyone joining in the
gap gets nothing.

Dead-group cleanup comes from the inactivity TTL alone (§4.3), which no
single member can trigger. Client UX stays as it is today: "remove from
this device" is the only deletion a member gets; the relay copy dies by
unanimous neglect. If a true "delete for everyone" is ever wanted
(e.g. a privacy-motivated group dissolution), it must be consensus-
gated exactly like compaction — a multi-signed deletion manifest in the
log, verified by clients — and is out of scope here.

### 4.3 Inactivity retention (TTL)

Track `last_access` per group (update at most once per day on any
authenticated request — one cheap conditional write). Purge groups idle
longer than a policy window (proposal: **12 months**). On Cloudflare,
deleting all DO storage drops that group's storage bill to zero; on
Node, pair periodic purges with `VACUUM` (or `auto_vacuum=INCREMENTAL`)
since SQLite files never shrink on their own.

This is compatible with §3: a purge requires *every* member to stay
away for the whole window — any honest member's sync renews it — so a
compromised member cannot starve a live group into deletion; they can
only keep it alive. Resurrection after a purge is re-register (PoW +
create, the same machinery that already registers groups created
offline) followed by re-push.

The policy must be stated in the spec and surfaced in-app ("the relay
keeps idle groups for 12 months; any sync renews") *before* it is
enforced — it changes what users should expect from the relay and
motivates the client durability work in §6.

### 4.4 Cursor reset-and-heal (protocol reservation — do this pre-launch)

TTL purges (§4.3), resurrection, and compaction (§5.2) create one
dangerous state: a re-created group starts `seq` back at 1, while
surviving clients hold cursors from the previous incarnation.
`since=<big cursor>` then returns nothing forever — silent permanent
desync. The fix is one additive rule: **when `since` exceeds the
group's current max seq, the pull response says so** (e.g.
`{resetCursor: true}`); the client resets its cursor to 0, re-pulls,
and dedups by event id (which the merge in `src/GroupOps.elm` already
does). Reserve this response field *now*, before launch, so every
deployed client handles it by the time any TTL or compaction feature
ships. This is the only server item with a hard deadline.

**Heal** is the second half, and it is what makes §3's rung 3 real:
after a reset re-pull completes, the client diffs the relay's content
against its local log and **re-pushes every event the relay lacks**.
This needs a new code path — `unpushedIds` only tracks never-pushed
events (`src/GroupOps.elm`, `src/Infra/Storage.elm`), so the diff must
come from comparing the full local log against the re-pulled set. With
it, every honest member is a repair agent: relay truncation — a purge,
a botched resurrection, an unsanctioned compaction, a hostile relay —
converges back to full history as soon as one honest member syncs.

Note the safety asymmetry: the reset path is purely additive on the
client (the merge never deletes), so neither a malicious member nor a
malicious relay can use a forged `resetCursor` to make clients lose
data — the worst case is a redundant re-pull.

### 4.5 Per-group quota

Maintain `record_count` and `total_bytes` on the groups row (updated on
append/compact — no `SUM` scans). Reject appends over a generous cap
(proposal: 50 MB or 50 000 records) with a distinct error code the
client can surface ("group is full — compact or export"). With §4.1 and
§5 in place, honest groups should never hit it; the cap exists purely
to bound abuse. Complements the S3 relay-hardening items (PoW checked
in the worker before DO materialization, groupId shape validation,
throw on missing `POW_SECRET`).

§3 residual, accepted: a compromised member can fill the quota to block
honest appends — denial of service, not destruction. Spam is either
attributable (validly signed events name their author) or inert
(undecryptable/unverifiable records are dropped by every client and,
being absent from verified local logs, are squeezed out by the next
consensus compaction, §5.2). Honest members' local operation is
unaffected; only sync is blocked until the group compacts or moves.

## 5. Server: compaction for long-lived groups

The only measure that bends the curve for *active* groups. Two designs
were considered; they differ radically in cost.

### 5.1 Rejected: state snapshots

An encrypted materialized `GroupState` at seq N, with events ≤ N
dropped. Rejected because it (a) breaks the signature model — the
snapshot is signed only by the snapshotting member, making history
forgeable by one member: under §3 this is precisely the capability we
must not create; (b) erases the audit trail and activity feed for new
joiners, contradicting spec §8.4's immutability guarantee; (c) is a
breaking wire change — old clients would see an Unknown event and
silently show an empty group. Every problem finding 21 warned about,
confirmed.

### 5.2 Proposed: consensus-gated log consolidation

Re-batch, don't summarize. A client that holds the full verified log
authors consolidation records: the same raw envelopes (verbatim, per
§11.3b), sorted, packed into a few large batches (up to the existing
1 MB record cap), gzipped as a whole, encrypted with the same group
key. A new route applies it transactionally:

```
POST /api/groups/:id/compact   { uptoSeq, records: [...] }
```

The server, in one transaction: verifies `uptoSeq` ≤ current max seq,
deletes records with `seq ≤ uptoSeq`, appends the consolidation
records (they get fresh, *higher* seqs — AUTOINCREMENT never reuses).
Concurrent pushes are unaffected (their seqs are > `uptoSeq` or they
serialize after the transaction). If two members race to compact, the
loser's `uptoSeq` may now cover deleted rows — reject with 409, client
re-pulls and retries or gives up.

**Consensus gate (required by §3).** Because the compact route deletes
relay records, it is destruction-shaped, and the server cannot restrict
who calls it (§3). So authorization moves into the log, where clients
*can* verify it:

- Two new event types. `CompactionProposed { uptoEventId, eventCount,
  manifestHash }` — the manifest hash commits to the exact envelope
  contents of the sorted history up to the boundary (canonical form to
  be pinned down in the spec; hash envelope bytes, not just event ids,
  so an author cannot swap their own event's content behind a reused
  id). `CompactionApproved { proposalId }` — a co-signature. Both are
  ordinary signed events: replicated, auditable, and preserved verbatim
  by the consolidation they authorize.
- **Approval is computed, not asked.** An honest client, on sync,
  recomputes the manifest from its *own* local log and auto-signs an
  approval only on exact match. No UI, no human judgment — the
  signature attests "my replica agrees the history up to this boundary
  is exactly this". A compromised proposer who omits or alters anything
  gets no honest signatures, because no honest replica matches.
- **Quorum: every involved actor should co-sign — every member who
  authored at least one event in the compacted range — with a floor of
  strictly more than 50% of them** to keep retired members, lost
  devices, and long-offline users from blocking forever. The proposer's
  signature is always required. Whether the 50% denominator counts all
  involved actors or only non-retired ones is an open parameter to
  ratify in the spec (recommendation: non-retired ones).
- Only once the quorum is present in the log may any member call the
  compact route, and the consolidation records must contain the
  proposal and approval events themselves, so the authorization travels
  with the result.

Active groups reach quorum in days (approvals ride the ~100 s batch
flush of normal syncs); the compaction itself is not urgent, so the
latency is free.

**Verification and enforcement.** The server never sees the quorum —
enforcement is client-side, per §3's ladder:

- *Existing members* need no protection: consolidation or its abuse
  never deletes anything locally, and an unsanctioned compaction that
  dropped events is undone by the first honest member's heal re-push
  (§4.4).
- *New joiners* verify the received history against the latest
  compaction manifest in it: recompute the hash over the received
  pre-boundary envelopes, check the quorum signatures (signer keys are
  in the log; envelope-level key introduction per §11.3 keeps them
  available). Mismatch or missing quorum → treat the history as
  untrusted and say so.
- The joiner's blind spot — a truncator would omit the manifest too,
  and a joiner cannot distinguish "truncated" from "never compacted" —
  is closed by the **invite attestation**: the invite link fragment
  (today `/join/:groupId#key`, `src/Route.elm`) additionally carries
  the inviter's current head attestation (latest event count + manifest
  or head hash — a few dozen URL characters). The joiner requires the
  fetched history to reach it. An attestation from the attacker proves
  nothing, but an inviter is trusted by the joiner by construction —
  that trust is what an invitation *is*.

Why this is *not* a breaking change:

- **Record shape is unchanged.** Records are already multi-event
  batches; a consolidation record is just a big batch. Old clients
  decrypt and decode it with zero new code.
- **Cursors survive.** New seqs are strictly greater than all old seqs,
  so no live cursor exceeds max seq. A client whose cursor predates
  `uptoSeq` re-pulls history it already has, and the existing
  dedup-by-event-id merge drops it — one-time bandwidth cost, no
  correctness cost.
- **Nothing about replay changes.** Same envelopes, same signatures,
  same sort order, same state, same activity feed. The proposal and
  approval events are unknown types to old clients, which store them
  verbatim and skip them (§11.3b) — they affect no state.
- The invite-fragment extension does need a **pre-launch format
  reservation**: today the join flow treats the entire fragment as the
  key (`src/Route.elm:70`), so a fragment like `key.attestation` would
  break old joiners' key parsing. Define the fragment grammar now as
  `key[.extra]` (parsers split on the separator and ignore the tail)
  so attestations can be added later without breaking deployed clients.

What it buys: record count collapses from ~event-count to ~history-size
/ 1 MB, whole-history gzip exploits cross-event redundancy (estimated
5–10×, to be measured), joins go from ⌈records/200⌉ sequential pages to
a handful, and §4.5's byte quota becomes reachable only by abuse.

When to compact: client-side heuristic on sync — e.g. when pull
metadata (add `recordCount` to the pull response, additive) shows
records ≫ what the local history would consolidate to. Any member may
propose; quorum gates execution; the 409 rule serializes racers.

Ship it after §4.1 (idempotency makes compact-then-crash-then-retry
trivial) and behind the §4.4 reservation and a spec section covering
the quorum rule and manifest canonical form.

## 6. Client: durability before size

The analyses in §3 and §4 lean on "clients are the system of record" —
honest replicas are both the backup *and* the tamper resistance: every
durable honest copy is a check on history rewriting. Today that record
is evictable:

- **`navigator.storage.persist()` is never requested** (only
  `estimate()` is used, `public/index.js:155`). Under storage pressure
  the browser may silently wipe IndexedDB — combined with a server TTL
  purge, that is real data loss; combined with §3, fewer replicas means
  weaker healing. Request persistence at first group creation/join;
  surface the denied case in the About/usage screen.
- **Export is the offline backup** and already exists; once a retention
  policy is announced (§4.3), nudge archival exports for long-idle
  groups ("this group hasn't synced in 10 months — download a backup").
- Local *pruning* of the event log was considered and rejected: the log
  is the audit trail, the activity feed, and now the healing source
  (§4.4); local space is a non-issue (§2); and divergent local pruning
  would complicate export/merge for zero user-visible benefit.

## 7. Performance

### 7.1 Client: group open (the everyday path)

Every group open reads all event rows, JSON-decodes each envelope, and
replays from scratch (`src/Main.elm:814`). At 10k events this is likely
hundreds of ms of IDB reads + decode + sort + fold — noticeable, not
fatal, and linear in history. Two mitigations, in order:

1. **Persist the materialized state** keyed by a log fingerprint (count
   + max sort key, or last event id): on open, load state + verify
   fingerprint; on mismatch or decode failure, fall back to full
   replay. The cache is pure derived data — always safe to discard.
   Note: **spec §14.6 already claims this exists; the code does not do
   it.** Either implement it or fix the spec — today the spec
   over-promises. Cost: encoders/decoders for `GroupState` including
   activities; moderate, mechanical.
2. Store/load events pre-sorted to skip the `sortEvents` pass on load —
   only worth it if measurement (§8) shows the sort matters; the merge
   path already maintains sorted order in memory.

The sync fast path (incremental apply with conflict-triggered rebuild,
`src/GroupOps.elm:600-660`) is already the right design; no change.

### 7.2 Client: first join (the first-impression path)

Join fetches ⌈records/200⌉ *sequential* pages, decrypts and
de-gzips each record, verifies every signature (WebCrypto ECDSA verify
is ~0.1–1 ms each → multi-second for 10k events), then replays.
Consolidation (§5.2) is the big lever: few round trips, better
compression, same verify cost. Its manifest check adds one hash pass
over the received envelopes plus a handful of signature checks —
negligible next to per-event verification. If verification dominates
after that, chunk it with a progress indicator rather than weakening
it.

### 7.3 Server

- **Byte-based page limit.** 200 records/page with a 1 MB record cap
  means a page can theoretically reach 200 MB. Cap pages at ~2–4 MB of
  payload as well as 200 records. Additive; matters more once
  consolidation makes big records common.
- Indexes are already right (`events(group_id, seq)` on Node; per-group
  DB with `seq` PK on Cloudflare). DO WebSockets already hibernate.
- `VACUUM` after purges on Node (§4.3); DO storage shrinks on delete by
  itself.
- Base64-in-JSON inflates transfer ~33%; a binary endpoint (CBOR/raw)
  was considered and rejected as not worth a second wire format at
  these sizes.

## 8. Measure before optimizing

All client timing figures above are estimates. Before implementing
§7.1: generate a synthetic 10k–50k event group (a small script through
the existing event codecs), and time (a) IDB load, (b) decode, (c)
sort+replay, (d) join verify, on a mid-range phone. This decides
whether the state cache is a launch-window task or a someday task, and
gives the §4.5 quota numbers an empirical basis.

## 9. Recommended sequence

Pre-launch (small, and they gate everything else):
1. **§4.4 cursor-reset reservation** — the one server field that must
   precede any deployed client population.
2. **§5.2 invite-fragment grammar** (`key[.extra]`) — same logic on the
   client side: deployed parsers must tolerate the attestation before
   it can ever be sent.
3. **§4.1 idempotent append** — also closes finding 11's storage leak.
4. **Spec updates**: the §3 threat model and enforcement ladder,
   retention-policy contract (§4.3), compaction design with quorum rule
   and manifest canonical form (§5.2), fix or implement §14.6's
   state-cache claim.
5. **§6 `navigator.storage.persist()`** — one small JS + UX change.

Post-launch, safe at any time, in value order:
6. §4.3 TTL purge + resurrection flow.
7. §4.4 heal re-push (diff local log vs. relay on reset).
8. §4.5 quota enforcement (+ S3 relay hardening batch).
9. §5.2 consensus consolidation: proposal/approval events, auto-sign on
   sync, compact route, joiner manifest verification, invite
   attestation.
10. §7.1 client state cache, informed by §8 measurements.

Explicitly rejected: state snapshots (§5.1), a member-triggered delete
route (§4.2), per-member server identities (§3 — membership-metadata
leak), local log pruning (§6), binary wire format (§7.3).
