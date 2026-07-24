# Deploying Partage

Partage is a static frontend plus a minimal relay backend ([`packages/relay`](../packages/relay)). The same relay core deploys either to Cloudflare Workers (hosted) or as a single self-hosted container — pick one.

In both setups the frontend and the API share one origin, so build the frontend with an **empty** `SERVER_URL` (the client then talks to its own origin):

```sh
SERVER_URL= pnpm build:optimize
```

**Push notifications are opt-in and separate.** They rely on an external web-push
service (the [elm-pwa](https://github.com/mpizenberg/elm-pwa) push server), not the
relay. Point the build at one with `PUSH_SERVER_URL`; leave it unset and the app
ships without push — the enable control and the per-group toggles are hidden.

```sh
SERVER_URL= PUSH_SERVER_URL=https://push.example.com pnpm build:optimize
```

> **Before a release:** CI covers Elm and relay logic but not browser/PWA behaviour. Run through [`RELEASE_CHECKLIST.md`](RELEASE_CHECKLIST.md) (a manual two-browser + one-installed-PWA pass) before tagging or deploying.

> **Migrating from the PocketBase deployment:** the relay starts with an empty database — there is no server-side data migration. Group members move a group by exporting it to JSON in the app and importing it again once the new instance is live.

## Option A: Cloudflare Workers

The Worker serves the API (one SQLite Durable Object per group, WebSockets hibernate while idle) and the frontend as static assets. This typically fits the free plan.

```sh
SERVER_URL= pnpm build:optimize
cd packages/relay
npx wrangler secret put POW_SECRET     # generate with: openssl rand -base64 32
npx wrangler deploy
```

`wrangler.jsonc` in `packages/relay` is the full configuration.

## Option B: Self-hosted container

One container, one volume. Works on any container host (Dokploy, Fly.io, a VPS with Docker).

```sh
SERVER_URL= pnpm build:optimize
docker build -t partage-relay -f packages/relay/Dockerfile .
docker run -d -p 8090:8090 -v partage-data:/data -e POW_SECRET="$(openssl rand -base64 32)" partage-relay
```

Configuration (all optional except `POW_SECRET`):

| Variable | Default | Description |
| --- | --- | --- |
| `POW_SECRET` | — (required) | HMAC secret for proof-of-work challenges. |
| `PORT` | `8090` | Listen port. |
| `RELAY_DB` | `/data/relay.db` | SQLite file path — mount a persistent volume there. |
| `STATIC_DIR` | `./static` | Frontend directory to serve; unset to serve the API only. |
| `ADMIN_SECRET` | — (unset) | Bearer secret for the operator dashboard ([below](#operator-dashboard-self-host)). Unset ⇒ the dashboard and its endpoint are absent (`404`). Generate like `POW_SECRET`. |
| `ADMIN_STORAGE_BUDGET_BYTES` | — (unset) | Optional. When set, the dashboard's storage-over-budget flag fires once total stored bytes exceed it. |

Put the container behind your TLS-terminating reverse proxy as usual. WebSocket upgrades on `/api/groups/*/ws` must be allowed.

### Operator dashboard (self-host)

Setting `ADMIN_SECRET` turns on a read-only surface for monitoring the deployment — capacity, growth, relay-observable abuse, per-group hot-lists, a pseudonymous users estimate, and a cost run-rate (see [Appendix C.7](SPECIFICATION.md#c7-operator-observability-self-host)):

- `GET /admin` — a self-contained page; enter the secret, which stays in the browser tab's session and is never persisted.
- `GET /api/admin/summary` — the JSON behind it, authenticated with `Authorization: Bearer $ADMIN_SECRET`.

Both are **absent (`404`) until `ADMIN_SECRET` is set** and live outside the per-group auth. They never return group content — only fleet **metadata** (group existence and sizes, opaque `groupId` hot-lists, abuse counters, a users estimate).

Serving them on the public origin behind TLS is fine **provided `ADMIN_SECRET` is a strong random value** (generate it like `POW_SECRET`). That secret is the primary control — compared in constant time — and the endpoint hardens itself against guessing: after **5 failed attempts an address is locked out for 15 minutes**. The lockout is per-IP and keyed off the reverse proxy's `X-Forwarded-For` (the setups above set it), so an attacker cannot lock the operator out, and a correct secret is never throttled.

If you would rather the metadata surface be unreachable from the internet as well, that is optional defense-in-depth: restrict `/admin` and `/api/admin/*` with an nginx `allow`/`deny` block on those paths, or reach them only over an SSH tunnel or a private overlay (e.g. Tailscale). Cloudflare parity is not yet implemented; the Worker never enables this endpoint.

CI builds and publishes this image on every push to `main` (`.github/workflows/relay-image.yml`): `ghcr.io/mpizenberg/partage-elm/relay`, tagged `latest` and with the commit sha.

### Dokku

Deploy the CI-built image rather than pushing git to Dokku (the Dockerfile needs a pre-built `dist/`, which is not in git). One-time setup on the VPS:

```sh
dokku apps:create partage
dokku config:set partage POW_SECRET="$(openssl rand -base64 32)"

# Persistent volume for the SQLite file (the image stores it at /data)
dokku storage:ensure-directory partage
dokku storage:mount partage /var/lib/dokku/data/storage/partage:/data

dokku domains:set partage partage.example.com

# If the ghcr.io package is private: dokku registry:login ghcr.io <user> <token>
```

Deploy by commit sha — `git:from-image` skips images whose tag it has already seen, so `latest` would not redeploy:

```sh
dokku git:from-image partage ghcr.io/mpizenberg/partage-elm/relay:<commit-sha>
```

After the first deploy, map the ports (Dokku defaults to exposing the Dockerfile's `EXPOSE 8090` as-is) and enable TLS:

```sh
dokku ports:set partage http:80:8090 https:443:8090
dokku letsencrypt:set partage email you@example.com
dokku letsencrypt:enable partage
```

Dokku's nginx passes WebSocket upgrades out of the box, but its 60 s `proxy_read_timeout` closes idle sockets (the relay does not ping). The client reconnects automatically, but you can avoid the churn:

```sh
dokku nginx:set partage proxy-read-timeout 1d
dokku proxy:build-config partage
```

Without a registry, stream a locally built image over SSH instead:

```sh
SERVER_URL= pnpm build:optimize
docker build -t partage-relay:latest -f packages/relay/Dockerfile .
docker image save partage-relay:latest | ssh dokku@your-vps git:load-image partage partage-relay:latest
```

### Operations and recovery (self-host)

Day-2 operations for the container. The relay stores only **encrypted** events and is a cache: every client keeps its own copy and re-pushes unacknowledged events when it reconnects, so clients recover the relay's recent state by syncing.

**Health.** `GET /health` returns `{"status":"ok"}` with no authentication. The image ships a Docker `HEALTHCHECK` that probes it; point any orchestrator liveness/readiness check at the same path. A single process over embedded SQLite is either serving or down, so liveness is also the readiness signal.

**Shutdown and restart.** On `SIGTERM`/`SIGINT` the relay stops accepting, closes the server, closes SQLite (checkpointing the WAL), and exits `0`; if that stalls it force-exits after 10 s. Give the orchestrator at least that long to stop — `docker stop --time=15`, or compose `stop_grace_period: 15s` — so the clean path wins. Restart or redeploy at any time; in-flight clients reconnect and resync.

**Backup.** SQLite runs in WAL mode, so a raw copy of `relay.db` while the relay is running can miss writes still in the `-wal` file. The simplest consistent snapshot uses the graceful shutdown above, which checkpoints the WAL, then copies the file (brief downtime; clients queue and resync):

```sh
docker stop <container>
docker run --rm -v partage-data:/data -v "$PWD:/backup" alpine \
  cp /data/relay.db "/backup/relay-$(date +%F).db"
docker start <container>
```

Event content stays encrypted in the backup. (For a hot backup with no downtime, run `sqlite3 /data/relay.db ".backup …"` — the `sqlite3` CLI is not in the image, so install it or use a sidecar.)

**Restore.** Stop the relay, replace the database, and delete any stale sidecar files so SQLite does not replay an old WAL onto the restored file:

```sh
docker stop <container>
docker run --rm -v partage-data:/data -v "$PWD:/backup" alpine sh -c \
  'cp /backup/relay-YYYY-MM-DD.db /data/relay.db && rm -f /data/relay.db-wal /data/relay.db-shm'
docker start <container>
```

Clients re-push anything newer than the snapshot on their next sync.

**Disk full.** When the volume fills, SQLite writes fail and appends are rejected with a server error; clients keep those events queued locally and retry on reconnect, so nothing is lost client-side. Relay growth is bounded — a per-group quota (50 MB / 50 000 records) plus purging of groups idle past the 12-month retention window ([§14.8](SPECIFICATION.md#148-relay-retention--storage-limits)) — and `ADMIN_STORAGE_BUDGET_BYTES` flags the [operator dashboard](#operator-dashboard-self-host) before you reach the limit. Recover by enlarging the volume or letting retention reclaim space; writes resume once there is room.

**Rollback.** Redeploy the previous image by commit sha against the same volume (`dokku git:from-image partage ghcr.io/mpizenberg/partage-elm/relay:<sha>`). The relay's SQLite schema is stable across releases; when a release notes a schema change, back up first.

## Separate frontend hosting

To host the frontend elsewhere (a static host, CDN, …), build it with `SERVER_URL` pointing at the relay instead:

```sh
SERVER_URL=https://relay.example.com pnpm build:optimize
```

The relay already answers cross-origin requests (permissive CORS), so no server-side change is needed.

Set `CANONICAL_ORIGIN` to your own domain so the built `canonical` and Open Graph tags identify your instance rather than the project site (the default). Link previews and search indexing then point at the host you actually serve:

```sh
SERVER_URL=https://relay.example.com CANONICAL_ORIGIN=https://partage.example.com pnpm build:optimize
```
