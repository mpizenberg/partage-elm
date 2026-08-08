# Remove the Cloudflare relay target

## Progress

- Increment complete: deleted the Worker, Durable Object storage, Worker tests/configuration, Cloudflare dependencies, and deployment path; collapsed the one-runtime test scaffolding; renamed SQLite storage as the sole relay storage; and updated CI and current docs. The relay lockfile fell from 1,657 to 69 lines and the total change removes 2,178 net lines. Frozen relay installs pass under pnpm 10 and 11; the production build, 343 Elm tests, relay Node suite, elm-review, elm-format, JavaScript syntax, Markdown links, removed-target reference scan, and diff checks pass.

## Goal

Make the deployed Node.js/SQLite relay the only supported backend. Delete the unproven Cloudflare Worker and Durable Object implementation instead of maintaining two storage paths, while keeping the surviving HTTP/application boundary reasonably portable.

## Increment

1. **Remove the Cloudflare target and collapse its seams.** Delete the Worker, Durable Object storage, Worker tests/configuration, Cloudflare-only dependencies and CI path. Rename the surviving SQLite storage as the relay storage, remove cross-runtime test abstractions that now have one caller, and update current documentation. Regenerate the independent relay lockfile, then validate frozen installation, relay behavior, the production build, Elm tests, lint, formatting, links, and the final absence of Cloudflare implementation references.

## Scope boundaries

- Preserve all Node relay API, WebSocket, retention, quota, compaction, observability, static-serving, and shutdown behavior.
- Keep Hono's Fetch-style application boundary, Web Crypto usage, and storage injection where they remain useful in their own right. They leave a future edge implementation possible without retaining speculative platform code today.
- Do not retain dormant Cloudflare configuration, adapter interfaces, dependencies, tests, or deployment promises “for compatibility.” Git history is the recovery path if the target is deliberately restored later.
- Do not edit historical plan records or third-party vendored documentation merely because they mention Cloudflare; they are not current application implementation or deployment support.

## Decisions

- Remove the Cloudflare implementation outright rather than extracting a shared storage kernel. Alternative: consolidate SQLite and Durable Object logic behind a stronger abstraction. Reason: there is only one used and deployed target, so deletion removes both the duplication and the adapter problem. Reintroducing Cloudflare later would require a fresh implementation against the then-current relay contract.
- Keep the Fetch-style Hono app and injected storage boundary rather than fusing HTTP, WebSockets, and SQLite into one module. Alternative: make the entire relay Node/SQLite-specific. Reason: these boundaries already separate protocol, transport, and persistence cleanly, support real-SQLite tests, and preserve portability without any Cloudflare code.
- Collapse the cross-runner conformance wrapper and protocol-helper layer into the Node test files. Alternative: retain them as scaffolding for a possible second runtime. Reason: with one runner they add indirection without testing another contract.
- Keep an explicit empty `allowBuilds` map in the relay workspace. Alternative: remove the build-permission policy with the dependencies that needed scripts. Reason: explicit denial preserves the repository's pnpm 10/11 install posture and cleanly states that the surviving relay dependencies need no install scripts.
