# Partage Backend — Architecture Report

*Analysis date: 2026-07-02. Sources: `packages/pb_server/`, `src/Infra/`, `src/Domain/Event.elm`, `src/GroupOps.elm`, `public/index.js`, `docs/SPECIFICATION.md` (Appendix C), `docs/DEPLOY.md`.*

## 1. Executive summary

Partage's "backend" is deliberately minimal: a **stock PocketBase instance acting as a zero-knowledge relay** for end-to-end-encrypted event logs. It contains **no application logic whatsoever** — no knowledge of expenses, members, balances, or currencies. All business logic, cryptography, and state computation live in the Elm/JS client. The server's entire job is:

1. **Store and serve opaque encrypted blobs** (the group event log), append-only.
2. **Enforce tenant isolation** (a group credential can only touch its own group's rows).
3. **Rate-limit group creation** via a proof-of-work challenge.
4. **Stream new events in real time** over PocketBase's built-in WebSocket subscriptions.

A second, independent backend service — an **external web-push relay** (`https://push.dokploy.zidev.ovh`, shared with the elm-pwa example project) — handles push notifications. It is not part of this repository.

## 2. Components

| Component | Where | Role |
|---|---|---|
| PocketBase server | `packages/pb_server/` | Encrypted event relay over SQLite (Go binary, v0.26.x) |
| PoW + validation hooks | `packages/pb_server/pb_hooks/auth.pb.js` | Anti-spam on group creation; user→group referential check |
| Timing hook | `packages/pb_server/pb_hooks/timing.pb.js` | `Timing-Allow-Origin` header so the client can measure transfer sizes |
| Schema script | `packages/pb_server/setup-collections.js` | Idempotent source of truth for collections (migrations are gitignored) |
| Client sync layer | `src/Infra/Server.elm` (+ vendored `elm-pocketbase`) | Auth, push/pull of encrypted event batches, realtime subscription |
| Crypto layer | `src/Infra/Crypto.elm`, `Identity.elm`, `EventVerification.elm`, `Compression.elm` | AES-256-GCM encryption, ECDSA P-256 signing/verification, password derivation |
| Push relay (external) | `src/Infra/PushServer.elm` → `push.dokploy.zidev.ovh` | Topic-based web push (VAPID), no auth |

## 3. Database schema (3 collections)

The server database is intentionally tiny. Defined in `setup-collections.js`:

### `users` (auth collection) — one account **per group**, not per person
| Field | Notes |
|---|---|
| `username` | `group_{groupId}`, unique, sole login identity field |
| `password` | Derived by clients from the group key (see §5) |
| `groupId` | Unique — enforces one account per group |
| `email` | Optional, unused in practice |

Password auth only (no OAuth2/MFA/OTP); 7-day auth tokens.

### `groups` — one record per group
| Field | Notes |
|---|---|
| `id` | The group identifier used everywhere (equals `users.groupId`) |
| `createdBy` | Public-key hash of the creator (plaintext) |
| `powChallenge` | The solved PoW challenge, unique index → prevents challenge reuse |
| `created` | Auto timestamp |

### `events` — the append-only encrypted event log (where all app data lives)
| Field | Notes |
|---|---|
| `groupId` | Routing/access-control only |
| `actorId` | Public-key hash of the pusher (plaintext) |
| `eventData` | JSON string `{ciphertext, iv}` — base64 AES-256-GCM blob, **max 1 MB**, may contain a *batch* of many application events |
| `compressed` | Whether the plaintext was gzipped before encryption |
| `created` | Auto timestamp — used by clients purely as a **sync cursor** |

## 4. Access control

| Collection | List/View | Create | Update | Delete |
|---|---|---|---|---|
| `users` | Own record only | Public, hook validates `groupId` exists | Never | Never (admin only) |
| `groups` | `auth.groupId = id` | Public, hook validates PoW | Never (immutable) | Never |
| `events` | `auth.groupId = groupId` | `auth.groupId = groupId` | Never (append-only) | Never |

No API path can ever update or delete a record — the event log is immutable by construction. Realtime subscriptions are gated by the same list/view rules.

## 5. Authentication model — "the group key is the credential"

There are no user accounts in the traditional sense. Each group has one shared server account:

1. Clients generate a random AES-256 group key at group creation.
2. The PocketBase password is **deterministically derived** from it: `Base64URL(SHA-256(Base64(groupKey)))` (`src/Infra/Crypto.elm`).
3. The account username is `group_{groupId}`; clients call `auth-with-password` and get a 7-day JWT.

Consequence: **anyone holding the group key** (i.e., anyone who received an invite link) can both decrypt the data and authenticate to the relay. Server auth is group-level tenant isolation, not user identity. Individual identity/authenticity is handled *inside* the encrypted payload via ECDSA P-256 signatures (see §7).

### Proof-of-work gate on group creation
Group creation is public but rate-limited by a stateless PoW scheme (`pb_hooks/auth.pb.js`):

- `GET /api/pow/challenge` returns `{challenge, timestamp, difficulty: 18, signature}` where `signature = HMAC-SHA256(challenge:timestamp:difficulty, POW_SECRET)`. The server stores nothing.
- The client brute-forces a `solution` such that `SHA-256(challenge + solution)` has 18 leading zero **bits**.
- On `POST /api/collections/groups/records`, the hook recomputes the HMAC, checks a 10-minute TTL, verifies the leading-zero-bits condition, and stamps the challenge onto the record — the unique index on `powChallenge` blocks replay.

A second hook on `users` creation verifies the referenced `groupId` actually exists.

## 6. Sync protocol

The client (`src/Infra/Server.elm`, orchestrated by `src/GroupOps.elm` and `src/Page/Group.elm`) implements a local-first sync cycle:

**Push.** All locally-created, not-yet-pushed events (tracked in the IndexedDB `unpushedIds` store) are bundled into one JSON array, gzip-compressed (kept only if ≤70% of original size), AES-256-GCM encrypted with the group key, and written as a **single** `events` record. Batching is triggered on user actions, on a ~100 s timer, and when coming back online.

**Pull.** Paginated `GET` on `events` filtered by `groupId="…" && created>"<cursor>"`, sorted `+created`, 200 per page. The cursor (PocketBase's `created` timestamp of the last record) is persisted per group in IndexedDB. Each record is decrypted/decompressed back into a list of event envelopes.

**Realtime.** The client subscribes to the `events` collection over PocketBase's WebSocket (`/api/realtime`). An incoming record doesn't get decrypted inline — it simply triggers a normal authenticated pull.

**Full cycle** (`authenticateAndSync`): authenticate → push unpushed batch → fire-and-forget push notifications to affected members (§8) → pull since cursor.

### Event envelopes and ordering
Each application event is an envelope `{id, clientTimestamp, triggeredBy, payload, signature}` with 13 payload types (`GroupCreated`, `EntryAdded/Modified/Deleted/Undeleted`, `MemberCreated/Renamed/Retired/Unretired/Replaced/MetadataUpdated`, `GroupMetadataUpdated`, `SettlementPreferencesUpdated`). Wire keys are shortened (`ts`, `by`, `p`, `sig`) to reduce payload size.

Ordering is by **client wall-clock timestamp, tiebroken by event ID** (UUID v7, itself time-ordered). The server plays no role in ordering — its `created` timestamp is only a download cursor. All clients sort the decrypted log with the same comparison function and replay it deterministically; invalid events are silently ignored during replay, so every client converges to identical state.

An incremental fast path (`GroupOps.applySyncResult`) applies new events directly when they don't conflict (order-dependent pairs on the same entity: rename/rename, retire/replace, modify/delete on the same entry, etc.); otherwise it rebuilds the full state from scratch.

## 7. Cryptography — what the server can and cannot see

Two-layer model:

- **Encryption (confidentiality):** one AES-256-GCM symmetric key per group, shared by all members, distributed **only through the invite-link URL fragment** (`/join/<groupId>#<base64url-key>`) — the fragment never reaches any server. Keys live in IndexedDB.
- **Signatures (authenticity):** each user has a locally generated ECDSA P-256 keypair; the SHA-256 hash of the public key is their stable member/actor ID. Every event is signed over a canonical JSON form; public keys travel *inside* encrypted `MemberCreated`/`MemberReplaced` payloads, and clients verify every pulled event's signature, silently dropping forgeries. This defends against a group member impersonating another member — not against the server (which sees only ciphertext anyway).

**Server-visible plaintext:** record IDs and timestamps, `groupId`, `actorId` (a key hash), the `compressed` flag, blob sizes/frequency, and which group accounts connect. **Everything else** — names, amounts, currencies, group names, even the signatures — is inside the encrypted blob.

## 8. Push notifications (separate service)

Push is handled by an external topic-based relay at `push.dokploy.zidev.ovh` (`src/Infra/PushServer.elm`), unauthenticated:

- `GET /vapid-public-key` at startup; the browser push subscription is registered per topic `"{groupId}-{memberRootId}"` via `POST/DELETE /subscriptions`.
- After a successful event push, the **client** (not the PocketBase server) computes affected members from the events, excludes the actor, and calls `POST /topics/{topic}/notify` for each with `{title, body, tag, icon, legacy: true, data: {url, key, name}}`.
- Localization happens in the **service worker**: notification payloads carry a template key (e.g. `expense_added`) and the SW substitutes localized templates stored in IndexedDB.

Note: notification metadata (group name as title, actor display name, event kind) is sent to the push relay in **plaintext** — a deliberate trade-off, distinct from the zero-knowledge PocketBase relay.

## 9. Deployment & operations

- **Docker image:** `FROM adrianmusante/pocketbase:latest` + copied `pb_hooks`, published as `ghcr.io/mpizenberg/partage-elm/pocketbase:latest` via GitHub Actions; deployed on Dokploy (port 8090, persistent volume at `/pocketbase-data`).
- **Configuration:** `POCKETBASE_ADMIN_EMAIL/PASSWORD/UPSERT`, `POW_SECRET` (must be overridden — the code ships a placeholder default), hook dir, workdir. The frontend gets the backend URL via a build-time `PB_URL` env var injected by esbuild (defaults to `http://127.0.0.1:8090`).
- **Schema management:** run `node setup-collections.js` against the live instance with admin credentials (idempotent). `clear-database.js` is a dev-only reset.
- **No retention/cleanup:** there are no cron jobs; events accumulate forever (append-only). The only bound is the 1 MB per-record limit.

## 10. Suggested changes: replace PocketBase with a minimal portable relay

*Goals: mainstream cloud compatibility (Cloudflare), easy self-hosting, keep live updates, and be as light as possible. The conclusion of the analysis above is that Partage uses a tiny fraction of PocketBase — 3 collections, 4 effective endpoints, append-only writes — and the hooks/rules/setup script exist mostly to constrain a general-purpose backend down to that surface. A purpose-built relay is smaller than the constraints.*

### 10.1 Shape: portable core + two thin adapters

Write the relay as a small web-standard HTTP app (e.g. [Hono](https://hono.dev), which runs unchanged on Cloudflare Workers, Node, Bun, and Deno). All platform-specific behavior hides behind one small storage/realtime interface:

| Layer | Cloudflare (hosted instance) | Self-host |
|---|---|---|
| HTTP + routing | Worker (Hono) | Node/Bun process (same Hono app) |
| Storage | Durable Object SQLite, **one DO per group** (`idFromName(groupId)`) | One SQLite file (`better-sqlite3` / Bun's built-in driver) |
| Live updates | WebSocket on the group's DO (hibernation API — idle connections are free) | `ws` package, in-process topic map keyed by groupId |
| Static frontend | Workers static assets (same origin as API) | Same process serves `dist/` |
| Deployment | `wrangler deploy` | **One container, one volume** — simpler than today's two services |

The protocol surface is small enough (~5 routes) that maintaining two adapters is a contained cost, and it keeps the door open to any other host (Fly, a VPS, etc.) — the self-host adapter *is* the generic server.

### 10.2 Proposed API

| Method | Route | Notes |
|---|---|---|
| `GET` | `/api/pow/challenge` | Unchanged: stateless HMAC-signed challenge. |
| `POST` | `/api/groups` | Create group. Body: PoW solution + `createdBy` + auth verifier (see below). |
| `GET` | `/api/groups/:id/events?since=<seq>` | Pull. Returns events with `seq > since`, paginated. |
| `POST` | `/api/groups/:id/events` | Push one encrypted batch record (append-only). |
| `WS` | `/api/groups/:id/ws` | Live updates: server pushes new records (or just their `seq`) to connected clients of that group. |

**SQLite schema** (per-group table in the DO; same tables + a `group_id` column in the self-host single file):

```sql
CREATE TABLE meta   (key TEXT PRIMARY KEY, value TEXT);        -- created_by, auth_verifier, pow_challenge
CREATE TABLE events (seq        INTEGER PRIMARY KEY AUTOINCREMENT,
                     actor_id   TEXT NOT NULL,
                     data       TEXT NOT NULL,                 -- same ≤1 MB encrypted batched blob
                     compressed INTEGER NOT NULL,
                     created    TEXT NOT NULL);
```

### 10.3 What each PocketBase mechanism becomes

| Today | Replacement |
|---|---|
| `users` collection, password auth, 7-day JWT | No accounts. Client sends `Authorization: Bearer <derived-secret>` (same key derivation as today); the server stores only `SHA-256(secret)` as a verifier, set at group creation. Constant-time compare per request. No sessions, no refresh. |
| Access rules (`auth.groupId = groupId`) | Structural: on Cloudflare each DO holds exactly one group's data; on self-host the verifier check scopes every query to one `group_id`. |
| PoW hook (`auth.pb.js`) | Kept nearly verbatim — it is pure WebCrypto and runs identically on Workers and Node, with zero external dependencies (deliberately preferred over Turnstile, which would break self-hosting). Replay protection via unique constraint on the stored challenge. |
| `created`-timestamp sync cursor | Server-assigned integer `seq` (auto-increment, race-free since writes serialize per group). Client stores an int instead of a timestamp string. |
| `/api/realtime` (PocketBase SSE/WS) | The group WebSocket. Client behavior unchanged: a notification triggers a normal authenticated pull from its cursor. |
| Hooks, `setup-collections.js`, migrations, admin account, Docker+Dokploy volume | Deleted. Schema is created by the server itself on first use (`CREATE TABLE IF NOT EXISTS`). |
| `timing.pb.js` CORS header hook | Obsolete on Cloudflare (same origin); trivial middleware on self-host. |

**Unchanged by design:** the client's entire crypto layer — AES-256-GCM group key, ECDSA P-256 signatures, batching/compression, deterministic replay — and therefore the zero-knowledge property. The server (either adapter) sees exactly what PocketBase sees today: `groupId`, `actorId`, ciphertext, sizes, timings.

### 10.4 Client-side impact

- Replace the vendored `elm-pocketbase` package with a much smaller HTTP/WS module in `src/Infra/Server.elm` (~5 endpoints; the `authenticateAndSync` orchestration in `GroupOps` keeps its shape, minus the auth round-trip).
- Change the persisted sync cursor (`syncCursors` store) from a timestamp string to an integer `seq`.
- Everything else — IndexedDB layout, event envelopes, ordering, conflict resolution, `unpushedIds` — is untouched.

### 10.5 Push notifications

What the push component does: store browser push subscriptions per topic (`{groupId}-{memberRootId}`) and, on request, send a Web Push message — an HTTP POST to the browser vendor's push service (FCM, Mozilla, Apple), authenticated with a VAPID ES256-signed JWT, payload encrypted to the subscriber's browser (RFC 8291). One constraint shapes the design: the server cannot read events, so **only the sending client knows which members are affected** — recipient computation and send-triggering stay client-side in every design. Two viable options:

**Option A (target) — fold push into the relay server itself**, replacing the shared external relay at `push.dokploy.zidev.ovh`:

- A `subscriptions` table next to the group data (DO / SQLite), keyed by the existing topic format; subscribe/unsubscribe routes plus `POST /api/groups/:id/notify`, all **authenticated with the group bearer secret** (today's notify endpoint is unauthenticated — anyone who guesses a topic string can notify that member).
- Sending: the `web-push` package on Node; a Workers-compatible WebCrypto implementation of VAPID + RFC 8291 on Cloudflare (ES256 and the ECDH/HKDF primitives are all available).
- VAPID keys become instance configuration (env/secrets), so each self-hosted instance has its own.
- Removes the third-party dependency (essential for self-hosting) and keeps notification metadata — group name, actor display name, event kind, currently sent in plaintext to a shared server — within the operator's own instance.

This can ship as a phase 2; the external relay keeps working in the meantime.

**Option B (later hardening) — fully zero-knowledge push.** In option A the relay still sees notification content in plaintext before encrypting it to the browser. To close that: distribute each member's push subscription (endpoint + keys) *inside the encrypted event log*, and have the **sending client** perform the RFC 8291 payload encryption itself — the server then only VAPID-signs and forwards an opaque blob, seeing endpoint URLs but no content. This matches Partage's zero-knowledge philosophy, but costs real complexity: RFC 8291 in the client, subscription churn propagating through the event log, stale-subscription cleanup. Since in option A the relay operator is the user themselves (or their group's host), the remaining trust gap is small — document as a possible phase 3, don't build now.

### 10.6 Trade-offs and open points

- **Two adapters to maintain** instead of zero backend code. Mitigated by the tiny interface; the self-host adapter doubles as the reference implementation.
- **Durable Objects are Cloudflare-proprietary.** Contained: only the hosted instance's adapter uses them, and the protocol is trivial to reimplement (as the spec's Appendix C anticipates).
- **Rate limiting beyond group creation** (event-push flooding by a key holder) is unhandled today and would remain so; a per-group budget in the DO / a middleware counter is easy to add later if needed.
- **No data migration:** the new relay launches as a from-scratch domain; existing PocketBase groups are not carried over. (Users who want to move a group can already do so via the client's full-group JSON export/import.)
- **Costs:** the hosted instance likely fits Cloudflare's free plan (SQLite DOs included; hibernated WebSockets cost nothing while idle); self-host cost is one small container.

## 11. Observations & potential gaps (current architecture)

1. **Invite link = full credential.** Possessing the URL fragment grants decryption *and* write access to the relay. This is by design (trusted groups), but there is no key rotation: `setup-collections.js`'s header comment describes a key-rotation/fanout scheme (`keyVersion`, `recipient`, …) that **does not exist** in the actual schema or hooks.
2. **Clock-skew sensitivity.** Ordering uses client wall-clock timestamps; a device with a skewed clock can (deterministically, but surprisingly) win or lose last-writer-wins conflicts.
3. **Unbounded storage growth.** Append-only with no compaction or retention; long-lived groups grow forever, and initial sync always replays the full history.
4. **Push relay privacy.** Group names and actor display names leak in plaintext to the shared push server, and its `/topics/{topic}/notify` endpoint appears unauthenticated — anyone knowing a topic string (`groupId-memberRootId`) could send notifications to that member.
5. **`POW_SECRET` default.** A hardcoded fallback secret exists in `auth.pb.js`; production must set the env var (documented in `.env.example` and `DEPLOY.md`).
6. **Difficulty is hardcoded** (18 bits) in the hook; the challenge endpoint signs it, so it can't be downgraded by clients, but tuning requires a redeploy.
