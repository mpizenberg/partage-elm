# Storage Growth & Performance Report

Exploration of how to prevent unbounded storage growth and improve
performance, on the relay (server) side and the client (user) side.
Written against the 2026-07 codebase; follows up review finding 21
("server storage only ever grows").

## TL;DR

- Organic per-group growth is tiny (~1–2 MB/year for a *busy* group).
  The real growth drivers are **dead groups that are never deleted**,
  **duplicate records from sync-retry bugs**, and **abuse** (no quota).
  Those are all fixable with cheap, non-breaking server changes.
- The only lever that caps growth for long-lived active groups is
  **compaction**. A *state-snapshot* scheme would be breaking and
  trust-damaging — rejected. A *log-consolidation* scheme (re-batch raw
  envelopes into a few large records) turns out to be **compatible with
  the existing pull/merge protocol** and preserves signatures, audit
  trail, and activity feed. It should be designed-in now (one small
  protocol reservation) even if implemented later.
- On the client, storage is not the problem — **durability and replay
  cost** are. The app never calls `navigator.storage.persist()`, so the
  browser may evict the local event log (the actual system of record).
  Every group open replays the full log from scratch; spec §14.6
  promises a persisted computed-state cache that the code does not have.
- Guiding principle that falls out of the analysis: **the relay is a
  cache; the clients are the system of record.** Every member holds the
  full log and the key, so any member can restore a purged group by
  re-registering and re-pushing. This licenses an aggressive server
  retention policy — provided clients are made durable (persist +
  export nudges) and the protocol gains a cursor-reset signal.

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

Order-of-magnitude estimate (unmeasured; see §7 on benchmarking): an
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
   whole — this is what consolidation (§4) reclaims.

Client-side, the same organic curve applies against browser quotas
measured in gigabytes: local *space* is a non-issue for years. The
client problems are durability (§5) and time (§6), not bytes.

## 3. Server: cheap, non-breaking measures

Ordered by value/effort. All are additive protocol changes.

### 3.1 Idempotent append

Client sends a `recordId` (fresh UUID per batch) with each push; server
adds `UNIQUE(group_id, record_id)` and, on conflict, returns the
existing `seq` instead of inserting. This closes the storage side of
finding 11 and every future retry bug in one stroke: pushes become
retry-safe by construction instead of by careful client bookkeeping.
Old clients that omit the field keep today's behavior.

### 3.2 Group deletion route

`DELETE /api/groups/:id`, authenticated with the same bearer secret.
Zero-knowledge compatible (the server already knows the group exists).
Client UX must separate two intents that are conflated today:
"remove from this device" (existing local delete) vs. "delete the
server copy for everyone". Any key holder can invoke it — within the
trusted-group threat model, and mitigated by recoverability: every
member holds the full log, so a deleted group can be re-registered
(PoW + create, the same machinery that already registers groups created
offline on first push) and re-pushed. Note this and §3.3 do upgrade a
malicious member's power from "append spam" to "erase the relay copy";
accepted for the same reason we accept that they could already wreck
the group content — but see §3.5 for the cursor consequence.

### 3.3 Inactivity retention (TTL)

Track `last_access` per group (update at most once per day on any
authenticated request — one cheap conditional write). Purge groups idle
longer than a policy window (proposal: **12 months**). On Cloudflare,
deleting all DO storage drops that group's storage bill to zero; on
Node, pair periodic purges with `VACUUM` (or `auto_vacuum=INCREMENTAL`)
since SQLite files never shrink on their own.

The policy must be stated in the spec and surfaced in-app ("the relay
keeps idle groups for 12 months; any sync renews") *before* it is
enforced — it changes what users should expect from the relay and
motivates the client durability work in §5. Resurrection after a purge
is the same flow as after §3.2 deletion.

### 3.4 Per-group quota

Maintain `record_count` and `total_bytes` on the groups row (updated on
append/compact — no `SUM` scans). Reject appends over a generous cap
(proposal: 50 MB or 50 000 records) with a distinct error code the
client can surface ("group is full — compact or export"). With §3.1 and
§4 in place, honest groups should never hit it; the cap exists purely
to bound abuse. Complements the S3 relay-hardening items (PoW checked
in the worker before DO materialization, groupId shape validation,
throw on missing `POW_SECRET`).

### 3.5 Cursor-reset signal (protocol reservation — do this pre-launch)

Deletion (§3.2), TTL (§3.3), and any future re-registration create one
dangerous state: a re-created group starts `seq` back at 1, while
surviving clients hold cursors from the previous incarnation. `since=
<big cursor>` then returns nothing forever — silent permanent
desync. The fix is one additive rule: **when `since` exceeds the
group's current max seq, the pull response says so** (e.g.
`{resetCursor: true}`); the client resets its cursor to 0, re-pulls,
and dedups by event id (which the merge in `src/GroupOps.elm` already
does). Reserve this response field *now*, before launch, so every
deployed client handles resurrection correctly by the time any
delete/TTL feature ships. This is the only item in §3 with a deadline.

## 4. Server: compaction for long-lived groups

The only measure that bends the curve for *active* groups. Two designs
were considered; they differ radically in cost.

### 4.1 Rejected: state snapshots

An encrypted materialized `GroupState` at seq N, with events ≤ N
dropped. Rejected because it (a) breaks the signature model — the
snapshot is signed only by the snapshotting member, making history
forgeable by one member, a large step down from per-event signatures;
(b) erases the audit trail and activity feed for new joiners,
contradicting spec §8.4's immutability guarantee; (c) is a breaking
wire change — old clients would see an Unknown event and silently show
an empty group. Every problem finding 21 warned about, confirmed.

### 4.2 Proposed: log consolidation

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
  same sort order, same state, same activity feed. Signature
  verification of every event still happens on every client.

What it buys: record count collapses from ~event-count to ~history-size
/ 1 MB, whole-history gzip exploits cross-event redundancy (estimated
5–10×, to be measured), joins go from ⌈records/200⌉ sequential pages to
a handful, and §3.4's byte quota becomes reachable only by abuse.

Trust caveat (accepted, must be documented in spec §11.3's residual
list): a malicious compactor can *omit* events. Forged events still
fail signature checks, but omission means new joiners see less history
than existing members — permanent divergence for them. Existing
members are untouched (compaction never deletes anything locally).
This is the same power §3.2 already grants (erase the relay copy), so
compaction adds no *new* trust assumption beyond the delete route.

When to compact: client-side heuristic on sync — e.g. when pull
metadata (add `recordCount` to the pull response, additive) shows
records ≫ what the local history would consolidate to. Any member may
do it; the 409 rule serializes racers.

Even with §4.2 being wire-compatible, ship it behind the §3.5
reservation and a spec section, and after §3.1 (idempotency makes the
compact-then-crash-then-retry story trivial).

## 5. Client: durability before size

The analysis in §3 leans on "clients are the system of record". Today
that record is evictable:

- **`navigator.storage.persist()` is never requested** (only
  `estimate()` is used, `public/index.js:155`). Under storage pressure
  the browser may silently wipe IndexedDB — combined with a server TTL
  purge, that is real data loss. Request persistence at first group
  creation/join; surface the denied case in the About/usage screen.
- **Export is the offline backup** and already exists; once a retention
  policy is announced (§3.3), nudge archival exports for long-idle
  groups ("this group hasn't synced in 10 months — download a backup").
- Local *pruning* of the event log was considered and rejected: the log
  is the audit trail and activity feed, local space is a non-issue
  (§2), and divergent local pruning would complicate export/merge for
  zero user-visible benefit.

## 6. Performance

### 6.1 Client: group open (the everyday path)

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
   only worth it if measurement (§7) shows the sort matters; the merge
   path already maintains sorted order in memory.

The sync fast path (incremental apply with conflict-triggered rebuild,
`src/GroupOps.elm:600-660`) is already the right design; no change.

### 6.2 Client: first join (the first-impression path)

Join fetches ⌈records/200⌉ *sequential* pages, decrypts and
de-gzips each record, verifies every signature (WebCrypto ECDSA verify
is ~0.1–1 ms each → multi-second for 10k events), then replays.
Consolidation (§4.2) is the big lever: few round trips, better
compression, same verify cost. If verification dominates after that,
chunk it with a progress indicator rather than weakening it.

### 6.3 Server

- **Byte-based page limit.** 200 records/page with a 1 MB record cap
  means a page can theoretically reach 200 MB. Cap pages at ~2–4 MB of
  payload as well as 200 records. Additive; matters more once
  consolidation makes big records common.
- Indexes are already right (`events(group_id, seq)` on Node; per-group
  DB with `seq` PK on Cloudflare). DO WebSockets already hibernate.
- `VACUUM` after purges on Node (§3.3); DO storage shrinks on delete by
  itself.
- Base64-in-JSON inflates transfer ~33%; a binary endpoint (CBOR/raw)
  was considered and rejected as not worth a second wire format at
  these sizes.

## 7. Measure before optimizing

All client timing figures above are estimates. Before implementing
§6.1: generate a synthetic 10k–50k event group (a small script through
the existing event codecs), and time (a) IDB load, (b) decode, (c)
sort+replay, (d) join verify, on a mid-range phone. This decides
whether the state cache is a launch-window task or a someday task, and
gives the §3.4 quota numbers an empirical basis.

## 8. Recommended sequence

Pre-launch (small, and they gate everything else):
1. **§3.5 cursor-reset reservation** — the one item that must precede
   any deployed client population.
2. **§3.1 idempotent append** — also closes finding 11's storage leak.
3. **Spec updates**: retention-policy contract (§3.3), compaction
   design + trust caveat (§4.2), fix or implement §14.6's state-cache
   claim.
4. **§5 `navigator.storage.persist()`** — one small JS + UX change.

Post-launch, safe at any time, in value order:
5. §3.2 delete route + "delete server copy" UX.
6. §3.3 TTL purge + resurrection flow.
7. §3.4 quota enforcement (+ S3 relay hardening batch).
8. §4.2 log consolidation.
9. §6.1 client state cache, informed by §7 measurements.

Explicitly rejected: state snapshots (§4.1), local log pruning (§5),
binary wire format (§6.3).
