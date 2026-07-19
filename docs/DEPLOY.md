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

## Separate frontend hosting

To host the frontend elsewhere (a static host, CDN, …), build it with `SERVER_URL` pointing at the relay instead:

```sh
SERVER_URL=https://relay.example.com pnpm build:optimize
```

The relay already answers cross-origin requests (permissive CORS), so no server-side change is needed.
