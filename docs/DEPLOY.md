# Deploying Partage

Partage is a static frontend plus a minimal relay backend ([`packages/relay`](../packages/relay)). The same relay core deploys either to Cloudflare Workers (hosted) or as a single self-hosted container — pick one.

In both setups the frontend and the API share one origin, so build the frontend with an **empty** `SERVER_URL` (the client then talks to its own origin):

```sh
SERVER_URL= pnpm build:optimize
```

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

Put the container behind your TLS-terminating reverse proxy as usual. WebSocket upgrades on `/api/groups/*/ws` must be allowed.

## Separate frontend hosting

To host the frontend elsewhere (a static host, CDN, …), build it with `SERVER_URL` pointing at the relay instead:

```sh
SERVER_URL=https://relay.example.com pnpm build:optimize
```

The relay already answers cross-origin requests (permissive CORS), so no server-side change is needed.
