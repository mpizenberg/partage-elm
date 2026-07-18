# Plan: Replace PocketBase with a minimal portable relay

Implements §10 of `plan/BACKEND_REPORT.md`: a purpose-built, zero-knowledge event relay (portable Hono core + two thin adapters: self-host Node/SQLite and Cloudflare Workers/Durable Objects), replacing `packages/pb_server/` and the vendored `vendor/elm-pocketbase/` client package.

## Progress

- Increment 1 done: `packages/relay/` — Hono core (4 HTTP routes), PoW ported from `auth.pb.js`, `node:sqlite` storage, Node entrypoint, 23 `node:test` tests green, curl smoke OK. WS is increment 2.
- Increment 2 done: WS live updates in the Node adapter (`src/node-server.js` via `@hono/node-ws`, broadcast `{seq}` per group; `server.js` is now a thin CLI wrapper). 28 tests green.
- Increment 3 done: client swapped to the relay. `Server.elm` rewritten on `ConcurrentTask.Http` (no auth round-trip), integer cursors end to end, WS glue + `onServerEvent` port in `index.js`, `vendor/elm-pocketbase` deleted, `PB_URL`→`SERVER_URL`, `pnpm dev` runs the relay. Compiles; 171 elm-tests, elm-review, full build + relay-served smoke all green. **Not yet verified in a real browser** (create group → sync → live update between two tabs) — do this before increment 5 ships.

## Decisions

- **Increment ordering: client swap before the Cloudflare adapter.** Alternative: build both adapters first and share conformance tests. Chosen so the whole app runs end-to-end against the Node adapter early — protocol mistakes surface before the second adapter exists. Reversible at no cost (just reorder work).
- **Push notifications (report §10.5 Option A) are out of scope for this plan.** The external relay at `push.dokploy.zidev.ovh` keeps working unchanged; folding push into the relay is a follow-up plan. This matches the report's "ship as phase 2".
- **Cutover is a fresh domain, no data migration** (per report §10.6). Existing PocketBase groups are not carried over; users move groups via the existing full-group JSON export/import. The old PocketBase instance stays up during a transition window.
- **Relay keeps default port 8090** (PocketBase's port), so the client's default dev URL and the esbuild define's fallback keep working. Alternative: a fresh port, rejected as pointless churn.
- **Auth verifier format: `base64url(SHA-256(utf8(secret)))`, computed client-side** and sent in the group-creation body — the server never receives the raw secret at creation. Requests then present `Bearer <secret>`; the server hashes and constant-time-compares.
- **Conflict responses are 409** (duplicate group, reused PoW challenge) where PocketBase returned generic 400s. The client only branches on success/failure, so this is a safe improvement; noted in case increment 3 finds client code matching on status codes.
- **CORS + `Timing-Allow-Origin` middleware lives in the portable core**, not the Node adapter — replaces `timing.pb.js` and PocketBase's built-in CORS for the cross-origin dev setup; on same-origin deploys it's harmless.
- **Self-host schema uses a `groups` table** (id, created_by, auth_verifier, pow_challenge unique, created) instead of the report §10.2 `meta` key/value sketch — that sketch fits the per-group DO; a relational table is the natural shape for the shared single file. The DO adapter (increment 4) may still use `meta`.
- **`node:sqlite` with a Node ≥ 22.5 requirement** (user-confirmed).
- **WebSocket auth via `?auth=<secret>` query parameter.** The browser WebSocket API cannot set an Authorization header; the alternative (smuggling the secret through `Sec-WebSocket-Protocol`) has inconsistent server-side support across the two adapters. The secret is the derived relay credential, not the group key, so a URL leak (e.g. server logs) exposes ciphertext access, never decryption. Revisit if either adapter grows first-class subprotocol handling.
- **The PocketBase client-init round-trip is deleted, not replaced** — `PocketBase.init` never touched the network, so the `pbClient : Maybe Client` gate only marked task completion. The server URL now flows straight from flags; the join flow triggers directly at init-complete, and the pbClient-ready race (group loaded before client init → sync never triggered) disappears. Consequence: no startup "server unavailable" toast; connectivity errors surface per-operation instead.
- **Legacy sync cursors (PocketBase timestamp strings) decode as "never synced"** rather than being migrated. Safe because the relay is a fresh domain: the pull restarts from seq 0 and `applySyncResult` dedupes by event id.
- **`subscribeToGroup` failures are swallowed in `postSyncTasks`** (previously the subscription was `expectNoErrors` by construction) — the WS is best-effort; the JS side reconnects with capped exponential backoff and dedupes by group.
- **Renamed `IdGen.pbId` → `IdGen.groupId`** — the 15-char alphanumeric format stays (invite-URL-friendly), only the PocketBase-named identity died with the backend.
- **`seq` is strictly monotonic per group but not dense** — the self-host adapter uses one global autoincrement across groups, while the DO adapter will have per-group counters. The client cursor contract is therefore "opaque monotonic integer, resume with `since=<last seen>`", nothing more. Increment 3 must not assume `seq` counts a group's events. Alternative: `better-sqlite3` for older-Node support, rejected to keep the self-host adapter dependency-free. If the baseline ever needs lowering, the swap is one file behind the storage interface.

## Context (from BACKEND_REPORT.md §10)

The server is a zero-knowledge relay: ~5 routes, append-only encrypted blobs, PoW-gated group creation, live-update notifications. Everything else (crypto, ordering, replay, batching) is client-side and **must not change**.

Target API:

| Method | Route | Notes |
|---|---|---|
| `GET`  | `/api/pow/challenge` | Stateless HMAC-signed challenge (ported near-verbatim from `pb_hooks/auth.pb.js`) |
| `POST` | `/api/groups` | Create group: PoW solution + `createdBy` + auth verifier `SHA-256(secret)` |
| `GET`  | `/api/groups/:id/events?since=<seq>` | Pull events with `seq > since`, paginated |
| `POST` | `/api/groups/:id/events` | Append one encrypted batch record (≤1 MB) |
| `WS`   | `/api/groups/:id/ws` | Server notifies connected clients of new records; client reacts with a normal pull |

Auth: no accounts. `Authorization: Bearer <derived-secret>` where the secret is today's derived password (`Base64URL(SHA-256(Base64(groupKey)))`, `src/Infra/Crypto.elm`); server stores only its SHA-256 hash, constant-time compare per request. Sync cursor becomes a server-assigned integer `seq` instead of a `created` timestamp string.

## Increments

### 1. Relay core + Node self-host adapter (HTTP only)

New package `packages/relay/`:

- `src/app.js` — Hono app with the four HTTP routes above, written against a small storage interface (`createGroup`, `getGroupMeta`, `appendEvent → seq`, `listEventsSince`), platform-agnostic (WebCrypto only, no Node APIs).
- `src/pow.js` — PoW challenge issue/verify ported from `packages/pb_server/pb_hooks/auth.pb.js` (HMAC-SHA256 signature, 10-min TTL, 18 leading zero bits, replay blocked by unique constraint on the stored challenge). Must accept solutions produced by the existing client `WebCrypto.ProofOfWork` — do not change the challenge/solution wire format.
- `src/storage-sqlite.js` — single-file SQLite (`node:sqlite`; declare `"engines": {"node": ">=22.5"}` in the package), schema from report §10.2 (`groups` meta + `events` with `group_id` column, `CREATE TABLE IF NOT EXISTS` on boot).
- `src/server.js` — Node entrypoint: serve the Hono app, serve `dist/` static files.
- Tests (`node:test`, in-process via `app.request()`): PoW round-trip, group creation + replay rejection, bearer auth (wrong secret → 401, cross-group → 403), append/pull with `seq` cursor, 1 MB body limit, pagination.

Config: `POW_SECRET` env var, no default in production mode (fail fast if unset — closes report §11.5).

**Verify:** `node --test` green; manual `curl` smoke against a local run.

### 2. Live updates (WebSocket) in the Node adapter

- Add the `WS /api/groups/:id/ws` route: bearer-authenticated upgrade, in-process topic map keyed by `groupId`; on successful event append, broadcast `{seq}` to that group's sockets.
- Extend the storage/notify interface so the append path signals the broadcaster (keeps the core adapter-agnostic for increment 4's DO version).
- Test with `ws` client in `node:test`: connect, push from a second "client", receive the seq notification; unauthorized upgrade rejected.

**Verify:** tests green.

### 3. Client swap: talk to the relay instead of PocketBase

The visible API of `src/Infra/Server.elm` (`ServerContext`, `SyncData`, `SyncResult`, `authenticateAndSync`, `createGroupOnServer`, `subscribeToGroup`, …) keeps its shape so `src/GroupOps.elm` / `src/Page/Group.elm` change minimally.

- Rewrite `src/Infra/Server.elm` internals on plain `ConcurrentTask.Http` calls to the 4 HTTP routes; drop the auth round-trip (bearer secret computed from the group key, same derivation as today's password — attach per request, no JWT/session).
- WebSocket subscription: replace `PocketBase.Realtime` with a small JS-side task/port in `public/index.js` (open/close per group, deliver `{groupId}` notifications to Elm); client behavior unchanged — a notification triggers a normal pull.
- Sync cursor: change `syncCursors` handling in `src/Infra/Storage.elm` (`saveSyncCursor`/`loadGroup` around lines 259–290) and the `PullResult` type from `String` timestamp to `Int` seq. No IndexedDB migration needed (fresh server domain — old cursors are meaningless; a decode fallback treats any non-int as "no cursor").
- `public/index.js`: remove `createPocketBaseTasks` import/registration; register the new HTTP+WS tasks.
- Build define: rename `__PB_URL__`/`PB_URL` to `__SERVER_URL__`/`SERVER_URL` in `package.json` esbuild scripts and `public/index.js` (same default `http://127.0.0.1:8090` → relay's dev port).
- Delete `vendor/elm-pocketbase/` and its entry in `elm.json` (swap rule — same diff).
- `pnpm dev`: replace `pnpm -F pb_server serve --dev` with the relay's dev command.

**Verify:** `elm-test`, `elm-review`, then manual end-to-end against the local Node relay: create group, add expense on two browser profiles, live update arrives, offline → reconnect sync, join via invite link.

### 4. Cloudflare adapter

- `packages/relay/src/worker.js` + `wrangler.jsonc`: Worker routes requests to one Durable Object per group (`idFromName(groupId)`); the DO hosts the same Hono core with a DO-SQLite implementation of the storage interface (per-group tables, no `group_id` column) and WebSockets via the hibernation API. `POW_SECRET` as a Worker secret. Frontend served as Workers static assets (same origin).
- Reuse increment 1–2's route tests against the Worker via `@cloudflare/vitest-pool-workers` (or miniflare) so both adapters pass one conformance suite.

**Verify:** conformance suite green on both adapters; `wrangler dev` manual smoke with the built frontend.

### 5. Cleanup, docs, deploy

- Delete `packages/pb_server/` entirely (hooks, migrations, setup/clear scripts, Dockerfile) and the pb_server GitHub Actions image publish job.
- Self-host packaging: one Dockerfile in `packages/relay/` (single container, one volume for the SQLite file, serves API + `dist/`).
- Rewrite `docs/DEPLOY.md` for both targets (`wrangler deploy` / container); update `.env.example`; update `docs/SPECIFICATION.md` Appendix C and `CLAUDE.md`/`README` mentions of PocketBase.
- Note the cutover explicitly in DEPLOY.md: new instance starts empty; existing groups move via JSON export/import.

**Verify:** fresh clone → `pnpm build` + container run works; grep for `pocketbase`/`PB_URL` returns nothing outside `plan/`.

## Out of scope (follow-ups, per the report)

- **Push relay fold-in** (§10.5 Option A): subscriptions table + authenticated notify routes on the relay, replacing `push.dokploy.zidev.ovh`. Separate plan.
- **Zero-knowledge push** (§10.5 Option B), key rotation, log compaction, per-group push rate limiting (§10.6/§11) — documented gaps, not built now.

## Open questions (defaults chosen, flag at increment boundaries if wrong)

- Package/server name: `packages/relay/` — rename freely before increment 1 lands.
- Whether the hosted instance should live on the existing domain or a new one (affects only DEPLOY.md wording and the transition window).
