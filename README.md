<p align="center">
  <img src="public/icon.svg" alt="Partage logo" width="128" height="128">
</p>

<h1 align="center">Partage</h1>

Partage is a fully encrypted, local-first bill-splitting application for trusted groups (friends, family, roommates). It runs as an installable Progressive Web App and works offline.

- **Privacy-first.** All sensitive data is end-to-end encrypted in the browser. The server only relays ciphertext.
- **Local-first.** Data is stored in IndexedDB and synced opportunistically when online.
- **No accounts.** Identity is a locally-generated ECDSA P-256 keypair. No email, no password.
- **Immutable audit trail.** Entries are versioned via an event log; modifications and deletions preserve history.
- **Deterministic convergence.** Concurrent edits across devices replay into identical state.

## Features

- Expenses, transfers, and income with arbitrary payer/beneficiary splits
- Multi-currency entries with per-group default currency
- Stable settlement plan (anchored balances + post-anchor transfers)
- Member claiming, aliases, and merging
- Virtual members for people who haven't joined
- Activity feed and per-member audit log
- Entry search, filtering, sorting, CSV export, and Splitwise import
- Read-only mode for archived or imported groups, with a rejoin flow
- Push notifications and PWA install (Android, iOS, desktop)
- Internationalization (English and French for now)

See [`docs/SPECIFICATION.md`](docs/SPECIFICATION.md) for the canonical feature spec.

## Architecture

| Layer | Technology |
|---|---|
| Frontend | [Elm](https://elm-lang.org) 0.19.1, `elm-ui`, `elm-concurrent-task` |
| Crypto | Web Crypto API (AES-256-GCM, ECDSA P-256, SHA-256) |
| Local storage | IndexedDB |
| Backend | Minimal zero-knowledge Node.js relay ([Hono](https://hono.dev) over SQLite) |
| Build | `elm-watch`, `esbuild`, `travelm-agency` (i18n) |

The relay backend lives in [`packages/relay`](packages/relay). It stores only encrypted blobs and signed metadata — it cannot decrypt anything. Its Hono application keeps Fetch-style HTTP and injected-storage boundaries, while the Node.js/WebSocket transport and SQLite lifecycle stay outside; a future platform port can therefore implement the [relay contract](docs/SPECIFICATION.md#relay-implementation-contract) without retaining dormant adapters today.

`Page.Group.EntriesTab` and `Page.Group.ActivityTab` intentionally own separate entry renderers. Entries presents interactive current ledger state grouped by business date; Activity presents compact historical snapshots and diffs grouped by event time. Shared domain and presentation policies should remain narrower than those views.

## Getting started

Requirements: Node.js ≥ 22.5 and pnpm ≥ 10.

```sh
pnpm install
pnpm -C packages/relay install
pnpm dev
```

The root application and relay deliberately have independent lockfiles. The relay lockfile is the self-contained production dependency boundary copied into its Docker image. Each package's `pnpm-workspace.yaml` records the dependency install scripts it permits; add exceptions deliberately rather than allowing scripts globally.

`pnpm dev` runs the relay, elm-watch, esbuild, the i18n watcher, and the service worker builder concurrently via `run-pty`. The app is served by elm-watch (Elm dev server) and the backend at <http://localhost:8090>.

### Build for production

```sh
pnpm build:optimize
```

Output is written to `dist/`.

### Tests and linting

```sh
pnpm test          # elm-test
pnpm lint          # elm-review
pnpm format:check  # elm-format --validate
```

## Deployment

See [`docs/DEPLOY.md`](docs/DEPLOY.md) for container deployment.

## Repository layout

```
src/              Elm source (Domain, Page, Infra, ...)
vendor/           Vendored Elm packages
packages/relay/   Minimal relay backend (Apache-2.0)
public/           index.html, manifest, icons, JS glue
translations/     travelm-agency translation files
tests/            elm-test suites
review/           elm-review configuration
docs/             Specification and deployment docs
```

## License

The Partage frontend is licensed under the **Mozilla Public License 2.0** — see [`LICENSE`](LICENSE).

The `packages/relay` subproject is licensed under Apache-2.0 (see its own `package.json`).

This project depends on third-party Elm and JavaScript libraries under BSD-3-Clause, MIT, and MPL-2.0 licenses; their copyright notices are preserved in their respective sources.
