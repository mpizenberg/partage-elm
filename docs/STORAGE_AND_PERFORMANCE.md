# Storage & Performance

How Partage keeps storage bounded and the two hot paths fast, and why that
lets it run on a free or near-free budget. The normative rules live in
[SPECIFICATION.md](SPECIFICATION.md) — retention and quotas in
[§14.8](SPECIFICATION.md#148-relay-retention--storage-limits), compaction in
[§14.9](SPECIFICATION.md#149-log-consolidation-compaction), the threat model
they answer to in [§11.7](SPECIFICATION.md#117-compromised-member-threat-model).
This document is the rationale and the numbers behind them.

## Guiding principle

**The relay is a cache; the clients are the system of record.** Every member
holds the full event log and the group key, so an honest member can restore a
purged or truncated relay copy by re-pushing. Storage on the relay is therefore
a *cost to bound*, never data to protect — which licenses an aggressive
retention policy the moment clients are made durable ([§14.1](SPECIFICATION.md#141-local-first-architecture)).

## The budget it has to fit

Partage is meant to be hostable for near-zero cost: one Cloudflare Worker
(one SQLite Durable Object per group, WebSockets hibernating while idle — this
typically fits the free plan), or a single self-hosted container with one
SQLite file. Both bill for stored bytes, requests, and compute. So the design
must keep *aggregate* storage and request volume inside those limits
indefinitely — not just today, but after years of accumulated groups.

## What honest usage costs

Order of magnitude: an entry envelope with short wire keys is ~400–800 bytes
of JSON; encryption + base64 adds ~40%, gzip takes most of it back — call it
**~0.5–1 KB per event on the relay**. A group logging 1000 entries a year
with edits lands around **1–2 MB/year**; a typical group sits well below that.
Client-side, IndexedDB quotas are measured in gigabytes, so local *space* is a
non-issue for years. Honest usage never threatens the budget.

## What actually grows — and the lever for each

The cost drivers are not organic usage; they are failure modes:

| Driver | Why it grows | Lever |
|---|---|---|
| **Dead groups** | A group deleted on every client still occupies its rows (and its Durable Object) forever. The one driver that scales with *total groups ever created*, not activity. | **Inactivity TTL** ([§14.8](SPECIFICATION.md#148-relay-retention--storage-limits)): purge groups idle past the retention window (12 months). A purge needs *every* member absent, so no single member can starve a live group. |
| **Duplicate records** | A push whose response is lost, or a group switched mid-sync, re-pushes an already-stored batch. Clients dedup on pull, so duplicates are invisible — and immortal — on the relay. | **Idempotent append** ([§14.3](SPECIFICATION.md#143-synchronization)): each push carries a content-derived `recordId` (`UNIQUE(group_id, record_id)`); a replay returns the existing `seq` instead of inserting. |
| **Abuse** | The bearer secret is derived from the group key and there is no natural per-group quota: any key holder can append 1 MB records in a loop. | **Absolute quota** (50 MB / 50 000 records) + **monthly rate cap** (~5 MB/group/month) ([§14.8](SPECIFICATION.md#148-relay-retention--storage-limits)). The quota bounds total damage; the rate cap bounds its *speed*, buying months of detection time. Honest groups sit orders of magnitude below both. |
| **Record fragmentation** | In trickle usage every entry flushes as its own record, so record count ≈ event count and per-record gzip can't exploit cross-event redundancy (repeated ids, keys, JSON shape). A compression multiplier, not a driver. | **Compaction** (below). |

## Compaction: the only lever for long-lived active groups

A busy group that never goes idle is the one case the TTL can't help. Compaction
([§14.9](SPECIFICATION.md#149-log-consolidation-compaction)) **re-batches, never
summarizes**: a member holding the full verified log re-packs the same raw
envelopes — verbatim — sorted, into large batches (each bounded to 512 KiB of
plaintext, the same bound normal push flushes use, so the encrypted record stays
under the relay's 1 MB cap), gzipped as a whole. Record count collapses from
~event-count to ~history-size, whole-history gzip exploits the cross-event
redundancy per-record gzip couldn't, and joins shrink from ⌈records/200⌉
sequential pages to a handful.

State snapshots were rejected for this: they would be signed by one member
(forgeable history), erase the audit trail, and break the wire format. Because
deleting relay records is destruction-shaped and the relay cannot tell members
apart, compaction is **consensus-gated in the log** and verified by clients, not
the server — the mechanism, quorum, and manifest form are specified in
[§14.9](SPECIFICATION.md#149-log-consolidation-compaction).

## Durability: what makes aggressive retention safe

The retention policy only works because honest replicas survive. The browser may
silently evict IndexedDB under storage pressure — combined with a TTL purge,
that is real data loss. So the app calls `navigator.storage.persist()` once at
first group creation/join and surfaces the result on the About screen
([§14.1](SPECIFICATION.md#141-local-first-architecture)). Export is the offline
backup; once retention is announced, long-idle groups get an archival-export
nudge. Local log *pruning* is deliberately not done: the log is the audit trail,
the activity feed, and the healing source, and local space is a non-issue.

## Performance: the two hot paths

**Group open (the everyday path).** Every open reads all event rows,
JSON-decodes each envelope, and replays from scratch. On-device measurement at
10k–50k events showed this stays within interactive budget, so a persisted
materialized-state cache is **not** warranted
([§14.6](SPECIFICATION.md#146-incremental-sync-optimization)) — it would remain a
fallback-guarded optimization only if replay time ever regresses. The sync fast
path (incremental apply, conflict-triggered rebuild) already avoids replay on
the common case.

**First join (the first-impression path).** A join fetches ⌈records/200⌉
*sequential* pages, decrypts and de-gzips each record, then verifies every
signature — WebCrypto ECDSA verify is ~0.1–1 ms each, so this dominates at large
histories (multi-second for 10k events), not replay. Compaction is the lever:
fewer round trips and better compression at the same verify cost. If
verification still dominates, chunk it behind a progress indicator rather than
weakening it.

**Relay.** Cap pull pages by bytes as well as by 200 records (a 1 MB record cap
alone lets a page reach 200 MB). Indexes are already right (`events(group_id,
seq)` on Node, per-group DB keyed by `seq` on Cloudflare); DO WebSockets
hibernate; `VACUUM` (or `auto_vacuum=INCREMENTAL`) reclaims space after purges,
since SQLite files never shrink on their own.

## Measuring, not guessing

Every timing figure here is an estimate until measured on real data. The
per-group **diagnostics page** ([§19](SPECIFICATION.md#193-screen-descriptions),
developer-mode only) is the instrument: event count and per-type histogram,
plaintext vs. stored size, whole-log recompression (exactly what compaction
would reclaim), sync/quota state, storage-persistence status, and a live timed
replay and full-log verify. Only the client can compute any of it — the relay
sees ciphertext.

## Keeping the budget observable

The per-user cost estimate on the About screen
([§18.2](SPECIFICATION.md#182-cost-estimation)) and the operator dashboard's
run-rate ([Appendix C.7](SPECIFICATION.md#c7-operator-observability-self-host))
turn the budget into a number the user and the operator can watch. The levers
above are what keep that number inside the free tier as groups accumulate.
