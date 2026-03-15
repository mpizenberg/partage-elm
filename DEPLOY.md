# Deploying Partage on Dokploy

Partage consists of two services:

1. **Frontend** — Static Elm/JS app (built with Railpack)
2. **PocketBase** — Backend API (Docker image)

## 1. PocketBase Docker Image

Build and push the image by triggering the GitHub Actions workflow:

```sh
gh workflow run pocketbase.yml
```

This publishes `ghcr.io/mpizenberg/partage-elm/pocketbase:latest`.

> Before building, update `packages/pb_server/pb_hooks/timing.pb.js` to add your production origin to the `allowed` array.

### Dokploy service configuration

- **Image:** `ghcr.io/mpizenberg/partage-elm/pocketbase:latest`
- **Port:** 8090
- **Volume:** mount a persistent volume to `/pocketbase-data`
- **Environment variables:**

| Variable                    | Value                                   |
| --------------------------- | --------------------------------------- |
| `POCKETBASE_ADMIN_EMAIL`    | your admin email                        |
| `POCKETBASE_ADMIN_PASSWORD` | a secure password                       |
| `POCKETBASE_ADMIN_UPSERT`   | `true`                                  |
| `POCKETBASE_PORT_NUMBER`    | `8090`                                  |
| `POCKETBASE_WORKDIR`        | `/pocketbase-data`                      |
| `POCKETBASE_HOOK_DIR`       | `/pocketbase/pb_hooks`                  |
| `POW_SECRET`                | generate with `openssl rand -base64 32` |

### Set up collections

Once PocketBase is running, create the collections from your local machine:

```sh
cd packages/pb_server
PB_URL=https://your-pb-domain.com \
PB_ADMIN_EMAIL=your-admin@email.com \
PB_ADMIN_PASSWORD=your-password \
node setup-collections.js
```

### Reset the database from scratch

1. Stop the PocketBase container in Dokploy
2. Delete the persistent volume (or clear `/pocketbase-data/pb_data`)
3. Restart the container — a fresh DB is created automatically
4. Re-run `setup-collections.js` as above
5. On prod, alternatively manually erase the PocketBase tables, and import from an exported schema generated on your local PocketBase instance.

## 2. Frontend (Railpack)

The frontend is a static site built by `pnpm build:optimize` and served from `dist/`.

### Dokploy environment variables

| Variable                  | Value                                                           |
| ------------------------- | --------------------------------------------------------------- |
| `PB_URL`                  | URL of your deployed PocketBase (e.g. `https://pb.example.com`) |
| `RAILPACK_BUILD_CMD`      | `pnpm build:optimize`                                           |
| `RAILPACK_SPA_OUTPUT_DIR` | `dist`                                                          |

The `PB_URL` variable is injected at build time by esbuild into the JS bundle. When unset, it defaults to `http://127.0.0.1:8090` (local dev).
