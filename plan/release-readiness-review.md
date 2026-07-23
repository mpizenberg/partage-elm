# Partage release-readiness review

## 1. Review metadata

| Item | Value |
| --- | --- |
| Review date | 2026-07-23 |
| Reviewed commit | `1c165fbd9c6025b235156779f9706497980385b5` |
| Initial worktree | `main...origin/main`; untracked `plan/` directory |
| Environment | macOS/Darwin arm64; Node.js `v24.13.1`; pnpm `10.30.2`; Elm `0.19.2` |
| Release target | First public release; self-hosted Node.js/SQLite relay; locally served Elm PWA |
| Normal-scale assumption | 2–20 members/group, 1–2 devices/member, 2–15 groups/person, and multi-year histories within the documented 50 MB/50,000-record relay cap |
| Accessibility target | WCAG 2.2 AA |
| Review mode | Source, documentation, tests, isolated builds, and bounded loopback relay validation |
| Explicit exclusion | Cybersecurity review and cybersecurity findings |

The review used the current working tree, `docs/SPECIFICATION.md` as the intended authority, and the owner-revised scope in `plan/release-readiness-review-prompt.md`. It did not inspect Git history, dependency internals, generated `src/Translations.elm` as authored source, Cloudflare deployment readiness, production services, or existing relay databases.

## 2. Executive summary

**Assessment: NO-GO**

The release candidate has strong financial-domain tests, deterministic replay coverage, a successful optimized build, and a self-host relay suite that passes in isolation. It is not ready for a first production release because four high-severity defects affect core guarantees:

1. An interrupted IndexedDB write can persist an event without its offline-queue marker, leaving it visible locally but never synchronized.
2. Multiple tabs can overwrite each other's queue state and keep divergent in-memory group state.
3. A long-lived PWA keeps a stale application clock, so newly created financial records can default to the wrong date.
4. Reused icon-only controls, including the primary add-entry action, have no programmatic accessible name.

Finding count: **0 Critical, 4 High, 7 Medium, 1 Low**. All four High findings are release blockers.

The recommended release path is to fix the four blockers, add focused fault-injection/multi-tab/browser accessibility regression tests, rerun the full isolated gate set, and execute a small cross-browser PWA acceptance matrix before release.

## 3. Release blockers

| ID | Severity | Blocker | Title |
| --- | --- | --- | --- |
| RR-001 | High | Yes | Event persistence and offline-queue tracking are not atomic |
| RR-002 | High | Yes | Multiple tabs can lose queued event IDs and diverge |
| RR-003 | High | Yes | Long-lived sessions use stale time for financial dates |
| RR-004 | High | Yes | Core icon-only controls have no accessible name |

### RR-001 — Event persistence and offline-queue tracking are not atomic

- **Severity / blocker / confidence:** High / Yes / High
- **Affected scenario:** Any local mutation during an IndexedDB error, storage-pressure failure, tab/process interruption, or browser termination between writes.
- **Repository evidence:**
  - `src/GroupOps.elm:152-168` writes the event and calls `Storage.addUnpushedIds` as separate tasks in a batch.
  - `src/Infra/Storage.elm:274-276` stores events, while `src/Infra/Storage.elm:321-323` stores the queue set in another store operation.
  - `src/Infra/Storage.elm:376-384` implements queue addition as a load-modify-save sequence.
  - `src/Infra/Storage.elm:389-414` and `src/Infra/Storage.elm:419-446` similarly spread group deletion/import persistence across independent operations.
  - First identity creation updates the ready model and route before persistence completes (`src/Main.elm:550-588`); save failure is only logged (`src/Main.elm:664-668`).
- **Specification:** The local event log is the system of record and offline events are queued for later synchronization (`docs/SPECIFICATION.md:835-867`).
- **Triggering sequence:** Create or edit an entry; allow the events-store write to complete; interrupt or fail the following queue-store write; reload; reconnect.
- **Observed versus expected:** The event can exist in the local log while its ID is absent from `unpushedIds`. Replay makes it visible after reload, but normal sync only pushes queued IDs. Expected behavior is an all-or-nothing commit of the event and its queue marker, or deterministic recovery that reconstructs the queue.
- **Impact and recovery:** Affected records can remain permanently local and other members never receive them. The state is difficult to detect because the record appears saved on the originating device. A relay cursor reset may eventually reconstruct missing remote history, but that is not a normal or timely recovery mechanism. Partial group writes can also leave an unloadable or incomplete group record. A failed first identity save can permit additional in-session work that will not have the same identity after reload.
- **Root cause:** Cross-store logical transactions are expressed as separate IndexedDB tasks without a shared transaction or a recovery journal.
- **Remediation direction:** Introduce one atomic storage operation for event(s) plus queue IDs, and atomic group save/delete operations across all involved stores. Do not transition identity-dependent UI state until identity persistence succeeds, or roll back and present a blocking recovery error.
- **Fix verification:** Add deterministic fault injection after each storage step. Assert that reopening produces either the entire operation or none of it; every locally authored event must either be queued or already acknowledged by the relay.

### RR-002 — Multiple tabs can lose queued event IDs and diverge

- **Severity / blocker / confidence:** High / Yes / High
- **Affected scenario:** Two tabs for the same origin and group are open; one or both create entries or sync.
- **Repository evidence:**
  - `Storage.addUnpushedIds` reads, mutates, and rewrites the whole set (`src/Infra/Storage.elm:376-384`).
  - Sync derives the remaining set from one tab's in-memory `loaded.unpushedIds` (`src/GroupOps.elm:828-870`) and persists the entire result (`src/GroupOps.elm:1034-1066`).
  - The periodic subscription only emits a sync tick (`src/Page/Group.elm:214-229`); no repository-authored source uses `BroadcastChannel`, Web Locks, or an IndexedDB change-notification protocol.
  - `public/index.js:118-165` manages a separate reconnecting WebSocket per tab/group. Its `visibilitychange` handler only flushes usage bytes (`public/index.js:472-477`).
- **Specification/release scope:** Incremental sync and the offline queue are core (`docs/SPECIFICATION.md:861-873`), and multi-tab behavior is in the release-review scope.
- **Triggering sequence:** Open tabs A and B with queue set S. A authors event A and B authors event B before either observes the other's write. Their independent load-modify-save operations can write S+A and S+B; the later write drops one ID. A concurrent sync can likewise persist a stale reduced set over a newly added ID.
- **Observed versus expected:** There is no cross-tab serialization or state invalidation. Last-writer-wins applies to the entire queue record rather than to individual queue additions. Expected behavior is that both event IDs survive and both tabs converge without a reload.
- **Impact and recovery:** An event whose ID is overwritten remains in IndexedDB but may never be pushed, producing the same silent cross-device divergence as RR-001. Stale tabs can also display obsolete summaries, entries, or membership until an incidental pull or reload. The condition is plausible under the stated one-to-two-device and ordinary desktop multi-tab usage and has low detectability.
- **Root cause:** The app assumes a single writer per browser profile while storing shared mutable aggregates and maintaining independent tab-local models.
- **Remediation direction:** Define a supported multi-tab model. Prefer a per-group cross-tab lock/leader for mutation and sync, atomic queue records keyed by event ID, and a broadcast invalidation/update channel. If only one active tab is supported initially, detect that state and block mutations in secondary tabs with clear UI rather than silently racing.
- **Fix verification:** Add a two-page browser test that interleaves writes and sync completion, then reloads both pages and a fresh profile. Assert union preservation, one remote copy per event, and identical derived balances/history.

### RR-003 — Long-lived sessions use stale time for financial dates

- **Severity / blocker / confidence:** High / Yes / High
- **Affected scenario:** The PWA or browser tab remains open across a day boundary without a successful local event.
- **Repository evidence:**
  - `currentTime` is initialized once from the JavaScript flag (`src/Main.elm:278-286`).
  - It is updated only when `Page.Group.UpdateCurrentTime` is emitted (`src/Main.elm:406-407`).
  - The 100-second timer discards the supplied current time and emits only `SyncTick` (`src/Page/Group.elm:214-229`).
  - Successful event processing emits an envelope timestamp as the update (`src/Page/Group.elm:940-949`, `src/Page/Group.elm:1868-1879`).
  - The cached value supplies transfer dates (`src/Page/Group.elm:510-525`, `src/Page/Group.elm:776-785`), new-entry form “today” (`src/Page/Group.elm:2289-2298`), exchange-rate cache date (`src/Page/Group.elm:1526-1535`), and displayed last-sync time (`src/Page/Group.elm:2028-2038`).
- **Specification:** Entry dates and immutable audit history are product data; the release criteria treat incorrect audit history under supported use as blocking.
- **Triggering sequence:** Open a group before midnight, leave the installed app running overnight, and open the new-entry or record-transfer flow the next day before another successful local save.
- **Observed versus expected:** The form defaults to the previous session date even though envelope signing later obtains a fresh `Time.now`. Expected behavior is for user-facing “today” and time-derived cache/sync metadata to reflect the actual current time.
- **Impact and recovery:** A user can save an expense, income, or transfer under the wrong date. It affects filters, exports, exchange-rate lookup date, and audit interpretation. The user may notice and edit the entry, but nothing forces detection, and the erroneous version remains in history.
- **Root cause:** Wall-clock time is modeled as event-derived application state instead of being refreshed by the existing timer, visibility changes, or at the start of time-sensitive actions.
- **Remediation direction:** Carry `Time.Posix` from `Time.every`, refresh on visibility regain, and obtain fresh time immediately before initializing or submitting date-sensitive forms. Keep event timestamps and user-selected accounting dates conceptually separate.
- **Fix verification:** Use a controlled clock browser test across midnight and after background/resume. Cover new expense, transfer, settlement transfer, exchange-rate fetch, and last-synced display.

### RR-004 — Core icon-only controls have no accessible name

- **Severity / blocker / confidence:** High / Yes / High
- **Affected scenario:** Screen-reader or voice-control use of add-entry, notification, filter, and other icon-only actions.
- **Repository evidence:**
  - The shared `iconButton` API accepts no label and renders only an SVG (`src/UI/Components.elm:333-347`).
  - Filter toggles delegate to that component (`src/UI/Components.elm:635-655`).
  - `fab` accepts a `label` but never renders or attaches it; it renders only the plus SVG (`src/UI/Components.elm:723-741`).
  - The group screen uses that FAB as the primary add-entry route (`src/Page/Group.elm:2664-2672`).
  - The home notification action is another icon-only button (`src/Page/Home.elm:306-321`).
- **Standard/specification:** WCAG 2.2 SC 4.1.2 requires a programmatically determinable name for UI components, and W3C's applicable test rule requires each button to have a non-empty accessible name ([W3C understanding SC 4.1.2](https://www.w3.org/WAI/WCAG22/Understanding/name-role-value), [W3C button-name rule](https://www.w3.org/WAI/standards-guidelines/act/rules/97a4e1/)). The product target is WCAG 2.2 AA.
- **Triggering sequence:** Navigate to a populated group with a screen reader or inspect the accessibility tree; focus the add-entry FAB, filter toggle, or enable-notifications button.
- **Observed versus expected:** The accessible name is empty because SVG shape alone does not name the action. Expected names are localized functional labels such as “Add entry”, “Show filters”, or “Enable notifications.”
- **Impact and recovery:** Assistive-technology users cannot identify several actions, including the core path for creating a financial entry. There is no reliable workaround when a screen reader announces an unnamed button.
- **Root cause:** Reusable UI primitives do not make an accessible label mandatory, and the FAB's existing label argument is unused.
- **Remediation direction:** Require a localized accessible label in every icon-action API and expose it through text or the underlying element's accessible-name attribute. Include pressed/expanded state where relevant. Use a functional label, not the symbolic “+”.
- **Fix verification:** Add DOM/accessibility-tree assertions that all buttons and links have non-empty names, then manually exercise the core flow with keyboard plus VoiceOver/NVDA in at least one supported desktop browser.

## 4. Non-blocking findings

### RR-005 — Documented notification types fall back to generic activity

- **Severity / blocker / confidence:** Medium / No / High
- **Affected scenario:** A subscribed member receives a notification for an edited or deleted entry, or for a pushed batch with multiple event types.
- **Evidence:** The specification lists localized keys for modified expenses/transfers/income and deleted entries (`docs/SPECIFICATION.md:1108-1119`). The implementation defines only added-entry and joined-member templates (`src/Infra/PushServer.elm:177-199`) and maps all other or batched payloads to `new_activity` (`src/Infra/PushServer.elm:210-245`).
- **Observed versus expected:** Edits and deletions produce “New activity” instead of the documented event-specific notification.
- **Impact/recovery:** Optional notifications lose meaningful context and do not conform to the authoritative specification. All recipients of those event kinds are affected, but the in-app activity log remains an available recovery path and no financial state is changed.
- **Root cause:** The event-to-template mapping and translation set are incomplete.
- **Remediation/test:** Add all specified keys and payload mappings, including batched-event behavior; unit-test every event kind in both languages and the service-worker interpolation path.

### RR-006 — Notification enabling can silently no-op when the fixed push service is unavailable

- **Severity / blocker / confidence:** Medium / No / High
- **Affected scenario:** A user grants notification permission while the external key endpoint is unavailable, or a self-host operator wants to use a different push service.
- **Evidence:** The client always fetches and posts to `https://push.dokploy.zidev.ovh` (`src/Infra/PushServer.elm:3-42`, `src/Infra/PushServer.elm:149-174`). A missing key after permission has been granted makes `EnableNotifications` return no command or user feedback (`src/PwaState.elm:144-155`); initial fetch failure is only logged (`src/PwaState.elm:157-171`).
- **Observed versus expected:** A self-hosted Partage instance still depends on one externally operated notification service. If it is unreachable, the visible enable action can do nothing.
- **Impact/recovery:** Push is optional, so core bill splitting remains available, but all users of an affected deployment lose notification setup. They cannot diagnose or retry the feature from the action, and operators cannot point it to another endpoint without rebuilding.
- **Root cause:** Push URL/configuration and user-visible availability are not part of deployment configuration/state.
- **Remediation/test:** Make push optional and configurable per deployment, represent unavailable/error states in UI, and document the dependency and data lifecycle. Test denied, unavailable, retry, and successful enable/disable flows.

### RR-007 — Import materializes the entire compressed and decompressed file without a size bound

- **Severity / blocker / confidence:** Medium / No / High
- **Affected scenario:** Group recovery/import with an accidentally oversized, truncated, or unexpectedly expansive `.partage` file.
- **Evidence:** `File.toUrl` reads the selected file as a data URL and sends the full base64 string into the app (`src/Page/Home.elm:96-121`). JavaScript creates complete compressed and decompressed buffers and then a complete decoded string (`public/index.js:374-385`). There is no selected-file or decompressed-size check.
- **Trigger:** Select an accidentally very large or unexpectedly expansive `.partage` file.
- **Observed versus expected:** Several full-size copies can coexist before Elm JSON decoding creates additional values. Expected behavior is a bounded import with a clear size error and progress/recovery.
- **Impact/recovery:** The importing tab can become unresponsive or be terminated, losing unsaved in-session work. Other devices and relay state are unaffected, and reopening the app recovers persisted data. Ordinary exports are expected to be small, which limits frequency.
- **Root cause:** A streaming API is converted back into whole-buffer processing and no product limit is enforced.
- **Remediation/test:** Define compressed and uncompressed import limits from supported history scale; reject early using `File.size`; stream/count decompression where practical; surface progress and a recoverable error. Test just-below/above limits and truncated files.

### RR-008 — SQLite event append and accounting update are separate transactions

- **Severity / blocker / confidence:** Medium / No / High
- **Affected scenario:** The self-host relay process or host stops at the narrow boundary between inserting an event record and updating its group accounting.
- **Evidence:** `appendEvent` computes quota state, executes the event insert, then updates group counters as separate statements (`packages/relay/src/storage-sqlite.js:185-199`). By contrast, compaction explicitly wraps its related statements in `BEGIN IMMEDIATE`/commit/rollback (`packages/relay/src/storage-sqlite.js:202-215`). SQLite documents that separately executed statements use separate implicit transactions unless an explicit transaction is opened ([SQLite transactions](https://sqlite.org/lang_transaction.html)); explicit transactions provide the atomic unit across interruption ([SQLite atomic commit](https://sqlite.org/atomiccommit.html)).
- **Trigger:** Relay process or host stops after the event insert commits but before the counter update commits.
- **Observed versus expected:** The event remains, while `record_count`, `total_bytes`, and monthly accounting can be stale. Expected event data and its accounting to commit or roll back together.
- **Impact/recovery:** Quota decisions, record count shown to clients, compaction heuristics, and operator metrics drift for that group. Event content itself is not lost, but there is no documented automatic reconciliation; an operator would need a repair procedure.
- **Root cause:** Append does not use the transaction discipline already used by compaction.
- **Remediation/test:** Wrap duplicate check, quota-plan read, insert, and accounting update in one appropriate write transaction; add startup/admin reconciliation or an integrity check. Inject a failure between statements and assert no partial state.

### RR-009 — Self-host lifecycle and recovery guidance is incomplete

- **Severity / blocker / confidence:** Medium / No / High
- **Affected scenario:** Container upgrade/termination, health-based orchestration, disk pressure, restore, or rollback on the supported self-host target.
- **Evidence:** The storage adapter exposes `close()` (`packages/relay/src/storage-sqlite.js:309-311`) and the Node adapter exposes server close (`packages/relay/src/node-server.js:86-99`), but the production entrypoint installs no `SIGTERM`/`SIGINT` handler and never closes either resource (`packages/relay/src/server.js:36-68`). The image has no health check (`packages/relay/Dockerfile:5-14`). Deployment documentation covers build, volume, proxy, and WebSocket setup (`docs/DEPLOY.md:26-100`) but not health/readiness, consistent SQLite backup/restore, disk-full handling, rollback, or recovery drills.
- **Observed versus expected:** Container termination relies on abrupt process exit; operators lack a documented way to establish readiness or recover the SQLite service predictably.
- **Impact/recovery:** Every self-host operator inherits manual, undocumented decisions during an incident. SQLite is designed to recover committed transactions, and the relay is documented as a cache, so this is not by itself a release blocker; it still increases outage duration and operator error during upgrades or storage incidents.
- **Root cause:** The deployment path is build-oriented rather than lifecycle-oriented.
- **Remediation/test:** Add graceful signal handling that stops acceptance, closes sockets/server, closes SQLite, and has a bounded forced-exit path. Add a lightweight health/readiness endpoint and operator runbook for backup/restore, disk alerts, restart, rollback, and client rehydration. Exercise termination during idle and active requests.

### RR-010 — Pull pagination is record-bounded but not byte-bounded or progress-guarded

- **Severity / blocker / confidence:** Medium / No / High
- **Affected scenario:** First join or catch-up sync for a large valid history, or recovery from an inconsistent relay response.
- **Evidence:** The relay fetches 201 rows and returns up to 200 regardless of aggregate response bytes (`packages/relay/src/app.js:339-370`; `PULL_PAGE_SIZE` is 200 at `packages/relay/src/app.js:21`). The storage/performance document explicitly calls for a byte cap as well as the 200-record cap (`docs/STORAGE_AND_PERFORMANCE.md:89-101`). On the client, `hasMore` recurses with a cursor derived from the last event, with no assertion that the page is non-empty or the cursor advanced (`src/Infra/Server.elm:430-480`).
- **Trigger:** A valid near-limit group has many large relay records on one page, or a faulty relay returns `hasMore: true` without a later sequence.
- **Observed versus expected:** A page can approach the group quota in size, causing a large response and browser memory spike. An inconsistent response can cause an unbounded request loop.
- **Impact/recovery:** One joining/catching-up device can become slow or fail, and a non-progressing response can repeatedly load both client and relay until navigation or process termination. Existing group members remain usable; normal compacted groups are expected to stay far below this condition.
- **Root cause:** Pagination models record count only and the client trusts progress metadata.
- **Remediation/test:** Enforce a response-byte budget while guaranteeing at least one record when possible; expose continuation metadata; reject or stop on empty/non-advancing pages and impose a bounded total. Test mixed record sizes, one maximum-size record, and non-progressing pages.

### RR-011 — Browser/PWA critical paths lack automated integration coverage

- **Severity / blocker / confidence:** Medium / No / High
- **Affected scenario:** Any change to ports, IndexedDB orchestration, service-worker events, time/visibility handling, accessible DOM output, or multi-tab behavior.
- **Evidence:** Root scripts provide Elm tests, formatting, lint, and builds but no browser test or accessibility audit (`package.json:5-25`). The test inventory consists of Elm unit/fuzz suites under `tests/`, Node relay tests under `packages/relay/test/`, and Cloudflare-target tests under `packages/relay/test-workers/`. CI runs those suites but no browser, multi-tab, IndexedDB fault, service-worker lifecycle, or accessibility job (`.github/workflows/ci.yml:45-61`).
- **Observed versus expected:** The areas behind all four release blockers are not exercised end to end. Passing domain and relay suites therefore cannot catch them.
- **Impact/recovery:** Browser-level regressions can reach every user despite green CI and may be found only during manual testing or after release. Recovery is a fix and redeploy; persisted-state defects may additionally require repair logic.
- **Root cause:** Test coverage stops at Elm logic and relay protocol boundaries.
- **Remediation/test:** Add a small deterministic browser suite for first use, group/entry persistence, offline/reconnect, two-tab queue behavior, midnight/background time refresh, service-worker update, and accessible button names. Run desktop Chromium in CI and schedule/manual-release coverage for Firefox and WebKit.

### RR-012 — PWA metadata is partially tied to the project host

- **Severity / blocker / confidence:** Low / No / High
- **Affected scenario:** A self-hosted operator serves the built frontend from a domain other than the project-hosted instance, or a user installs the PWA.
- **Evidence:** Canonical, Open Graph URL/image, and Twitter image are hard-coded to `partage.dokploy.zidev.ovh` (`public/index.html:12-33`). The manifest omits the specified `categories` and portrait preference (`public/manifest.webmanifest:1-19` versus `docs/SPECIFICATION.md:1170-1189`).
- **Observed versus expected:** Built self-host instances advertise another host as canonical and omit two documented manifest fields. Expected metadata should either identify the deployed instance or intentionally identify the project site and match the specification.
- **Impact/recovery:** Link previews and indexing can point at the wrong host, while install metadata is less complete. Core operation is unaffected and the issue is recoverable by rebuilding metadata.
- **Root cause:** Static metadata has not been separated into deploy-time configuration, and two documented manifest fields were not implemented.
- **Remediation/test:** Generate host-specific social/canonical metadata or clearly document the project-site choice; add the intended manifest fields; validate the built manifest and link preview in the release checklist.

## 5. Specification conformance

| Major area | Assessment | Evidence/notes |
| --- | --- | --- |
| Identity and routing | Partial | Route guards and identity generation are implemented, but first identity persistence is not coupled to the UI transition (RR-001). |
| Groups and members | Substantial | Creation, joining, virtual/real members, linking, retirement, metadata, merge, archive, and recovery flows are represented in source and domain tests. Atomic group persistence and multi-tab state remain gaps. |
| Entries and audit history | Substantial with blocker | Expense, transfer, income, edit/delete/restore/duplicate, immutable versions, and activity derivation are implemented and heavily tested. Stale default dates can create incorrect history (RR-003). |
| Balances and settlements | Conformant in reviewed logic | Integer minor-unit arithmetic, payer/beneficiary allocation, normalized currencies, settlement plans, stable settlements, and linked-member roots have focused tests and fuzz invariants. |
| Currency handling | Substantial | Currency precision/formatting and default-currency amounts are covered. Exchange-rate cache dating inherits RR-003. |
| Event protocol/replay | Substantial | Deterministic ordering, raw-envelope preservation, deduplication, idempotent relay records, cursor epochs, reset healing, conflict rebuild, and compaction are implemented and tested. Pagination robustness remains RR-010. |
| Local storage/durability | Non-conformant | IndexedDB schema matches the documented stores, but logical persistence operations are not atomic and multi-tab writers are uncoordinated (RR-001, RR-002). |
| Import/export | Partial | Full gzip group export/import and CSV output exist with codec/import tests; import memory is unbounded (RR-007). |
| Offline/sync | Partial | Offline queue, retry ticks, WebSockets, reconnect, reset healing, and relay persistence are implemented. Queue durability and multi-tab convergence block release. |
| Push notifications | Partial | Subscription, affected-recipient computation, service-worker localization, and user controls exist; documented event types and failure/deployment UX are incomplete (RR-005, RR-006). |
| PWA | Partial | Manifest, install hints, generated service worker, offline/update events, and push hooks exist. Metadata discrepancies and missing browser lifecycle validation remain (RR-011, RR-012). |
| UX/accessibility | Non-conformant | Responsive component architecture, forms, toasts, and recovery states exist, but unnamed core controls violate the WCAG target (RR-004). |
| Self-host relay/operations | Partial | Static SPA serving, HTTP/WebSocket relay, SQLite persistence, retention, quotas, compaction, metrics, and admin pages have tests. Append accounting and lifecycle/runbook gaps remain (RR-008, RR-009). |
| Diagnostics/localization | Substantial | English/French translation generation succeeds; diagnostics, error log, usage statistics, and language switching are represented. No exhaustive linguistic review was performed. |

## 6. Privacy disclosures and data lifecycle

This section is issue spotting, not legal advice. Cybersecurity assurance is excluded.

- **Local data:** IndexedDB contains identity material, a local self-profile with contact/payment details, group summaries and keys, full event/audit logs, sync cursors, queue state, notification translations, and usage statistics (`docs/SPECIFICATION.md:847-859`). The full event log is intentionally retained as the local system of record.
- **Relay-visible metadata:** The specification identifies sequence numbers, group IDs, and actor IDs as relay metadata (`docs/SPECIFICATION.md:617-620`). The self-host dashboard also reports fleet-level sizes, counts, and opaque group hot lists (`docs/DEPLOY.md:49-60`).
- **Push data:** Group name, actor display name, event kind, and a per-member topic are sent to a fixed external push service (`docs/SPECIFICATION.md:1127-1139`; `src/Infra/PushServer.elm:29-42`, `src/Infra/PushServer.elm:149-174`). This is disclosed in the technical specification but should also be presented in owner-facing deployment/privacy material before users opt in.
- **Retention:** The relay's documented inactivity TTL is 12 months, possibly shorter for very large groups, renewed by any member activity (`docs/SPECIFICATION.md:965-978`). Local removal deletes only the current browser's copy; other members and the relay follow their separate lifecycle.
- **Export/removal:** Full exports contain decrypted group data, metadata, the event log, and audit trail; CSV contains active financial records (`docs/SPECIFICATION.md:814-828`). These files need clear user-facing handling language. The product should distinguish local removal, group archiving, relay expiry, and third-party push subscription removal.
- **Readiness conclusion:** The implementation has a coherent data-minimization model for the relay, but release documentation should give users and self-host operators a concise inventory of local, relay, and push data; retention triggers; export sensitivity; and what each delete/archive action actually removes.

## 7. Correctness, synchronization, and data durability

Financial-domain correctness is the strongest reviewed area. Balances use integer minor units, currency precision is explicit, proportional allocation distributes deterministic remainders, and the test suite checks net-zero and paid/owed conservation. Stable-settlement unit and integration suites cover deterministic planning and linked-member behavior. Entry replay preserves version chains and soft deletion, while event ordering has deterministic tie behavior.

The release risk is below the domain layer:

- Locally authored events and their queue markers are not one durable operation (RR-001).
- Queue state is a shared mutable set without cross-tab serialization (RR-002).
- Sync persistence correctly chains pulled events before the cursor (`src/GroupOps.elm:1039-1050`), which avoids a cursor advancing past missing pulled events, but saves queue/tamper state and that chain in a broader batch (`src/GroupOps.elm:1052-1066`).
- Relay idempotency, reset epochs, heal re-push, WebSocket notification, and compaction race handling have implementation and test evidence.
- Pull response size/progress protections remain incomplete (RR-010).

Until RR-001 and RR-002 are fixed, the advertised local-first/offline model cannot guarantee that a locally visible mutation reaches other members.

## 8. Self-hosted operational readiness

The Node/SQLite target starts cleanly with an explicit temporary database, serves the SPA, passes HTTP and WebSocket tests, and persists its tested state. The container build pins Node 24, uses the relay lockfile, mounts `/data`, and supports same-origin static serving. Node 24 is an LTS line, which is appropriate for production according to the [Node.js release schedule](https://nodejs.org/en/about/previous-releases).

Remaining work:

- Make append plus accounting atomic (RR-008).
- Add signal-aware graceful shutdown, health/readiness, and a recovery runbook (RR-009).
- Implement the documented byte-bounded pull behavior (RR-010).
- Define disk-capacity alert thresholds and practice recovery/rehydration before release.
- Document exactly which image tag is deployed and retain the prior immutable commit tag for rollback.

Because the relay is designed as a cache and clients retain full histories, lack of relay backup is not automatically data loss. That design depends on the client-side durability blockers being resolved first.

## 9. UX, accessibility, browser, and PWA assessment

### Browser support matrix

A practical first-release matrix is:

| Platform | Release support target | Notes |
| --- | --- | --- |
| Chrome desktop / Edge desktop | Current and previous stable major | Primary desktop PWA/IndexedDB/WebSocket path |
| Firefox desktop | Current and previous stable major | Browser app path; installation UX may differ |
| Safari on macOS | Current and previous major, with Safari 17 as a conservative floor | Browser and installed web-app path |
| Chrome and Edge on Android | Current and previous stable major | Primary Android install path |
| Safari on iOS/iPadOS | Current and previous major; iOS/iPadOS 16.4 is the functional floor for Home Screen Web Push | Web Push is limited to Home Screen web apps and a direct user gesture, as documented by [WebKit](https://webkit.org/blog/13878/web-push-for-web-apps-on-ios-and-ipados/) |
| Firefox on Android | Current stable | Browser path; verify install/share affordances separately |
| Firefox/Chrome/Edge on iOS | Treat as the iOS WebKit path | Validate browser-specific UI, but platform web capabilities follow iOS constraints |

The gzip import/export dependency is reasonable for this matrix: MDN marks Compression Streams as widely available across browsers since May 2023 ([MDN Compression Streams API](https://developer.mozilla.org/en-US/docs/Web/API/Compression_Streams_API)). Optional APIs should continue to be feature-detected and visibly degrade.

This matrix is a release target, not a claim of completed validation. Browser automation was stopped at the owner's direction, so the candidate still needs representative manual/automated acceptance on the matrix above.

### UX/accessibility/PWA conclusions

- RR-004 is a critical-path assistive-technology barrier and must be fixed before claiming WCAG 2.2 AA.
- Keyboard focus styling and target sizing are represented in shared UI primitives, but no complete keyboard or screen-reader pass was performed.
- RR-003 affects backgrounded/long-lived installed-app behavior.
- Offline/install/update plumbing exists, but service-worker install, update activation, stale-cache recovery, and offline navigation were not validated end to end in this review.
- The manifest is installable in structure, but metadata is incomplete/tied to the project host (RR-012).
- Push should be treated as optional and its platform restrictions and unavailable state made explicit (RR-005, RR-006).

## 10. Tests, tooling, dependencies, and maintainability

- Root lockfile and relay lockfile match the installed top-level packages reported by pnpm.
- Root and relay engine requirements are Node `>=22.5.0`; CI uses Node 24, and the review passed on Node 24.
- The optimized build regenerated translations, compiled Elm with optimization, bundled JavaScript, and built the service worker successfully.
- `elm-review` reported no errors and seven existing suppressions.
- The Elm suite passed 291 tests, including fuzz/property coverage for financial calculations, settlements, replay/state, compaction, codecs, import, identity, and diagnostics.
- The self-host Node relay passed 102 tests covering protocol behavior, static SPA serving, WebSockets, persistence, quotas, retention/metrics, compaction, and admin behavior.
- Cloudflare worker tests were intentionally not run because that deployment target is excluded.
- Dependency review was limited to declarations, lock consistency, installed versions, engine compatibility, builds/tests, and obvious integration risk. No dependency source or advisory review was performed.
- The largest maintainability gap is browser-level coverage (RR-011). Storage and port-heavy PWA code needs integration tests because the Elm type system and relay suites cannot observe actual browser transaction, lifecycle, or accessibility behavior.

## 11. Positive assurance

The following checks produced specific positive evidence:

- **Financial conservation:** Existing balance fuzz tests assert total paid equals total owed and aggregate net balance is zero across arbitrary splits and currency-normalized amounts.
- **Currency precision:** Tests include currencies with different minor-unit precision, including zero-decimal JPY behavior.
- **Settlement determinism:** Stable-settlement tests and integration tests cover repeatability, preferences, linked-member roots, and transfer recording.
- **Event replay:** Group state, entry resolution, codec, compaction, and verification suites cover deterministic sorting/replay, version selection, unknown shapes, deletion/restoration, and raw-envelope round trips.
- **Sync recovery mechanisms:** Source and relay tests support idempotent record append, pagination, epoch/cursor reset, re-push healing, WebSocket reconnect notifications, and compaction race rejection.
- **Relay isolation:** All local relay runtime checks used an explicit disposable SQLite path; existing repository relay databases were not opened or used.
- **Build/reproducibility:** Formatting, review rules, unit tests, relay tests, and optimized same-origin production build all pass with the checked-in dependencies.
- **Localization generation:** English/French generated-code production completed during the optimized build, providing evidence that translation keys required by compilation are present.

These checks do not negate the browser/storage lifecycle gaps described above.

## 12. Validation performed

All commands that could write caches or output ran in the isolated mirror:

`/private/tmp/partage-release-review.VjXxhf/repo`

Full logs remain in:

`/private/tmp/partage-release-review.VjXxhf/`

| Command/check | Result |
| --- | --- |
| `pnpm format:check` | Pass; formatter returned `[]` |
| `pnpm lint` with isolated `ELM_HOME` | Pass; no errors, 7 suppressions |
| `pnpm test` with isolated `ELM_HOME` | Pass; 291 passed, 0 failed |
| `pnpm -C packages/relay test` | Pass; 102 passed, 0 failed/cancelled |
| `SERVER_URL= pnpm build:optimize` with isolated `ELM_HOME` | Pass; translation generation, optimized Elm compile, JS bundle, and PWA build completed |
| `pnpm list --depth 0` and relay equivalent | Declared top-level versions resolve consistently with their lockfiles |
| Loopback relay startup/static/WebSocket exercise | Covered by the relay suite using a disposable DB and a temporary mirror-only loopback bind adjustment |
| Browser automation | Stopped at owner direction; no browser-runtime conclusion drawn |
| Cloudflare worker suite | Not run; excluded release target |

Two initial test attempts encountered sandbox/environment limitations: Elm's default global cache lock and restricted local socket creation. They were rerun with an isolated `ELM_HOME` and approved loopback execution; the final results above passed. The temporary relay mirror was changed only to bind its test server explicitly to `127.0.0.1`; repository source was not changed for validation.

## 13. Coverage and limitations

Reviewed:

- `CLAUDE.md`, README, full specification, deployment guide, storage/performance guide.
- Repository-authored Elm frontend/domain/storage/sync/import/PWA/UI modules, browser JavaScript and service-worker build/transform code.
- Root and relay package/lock/build/test/CI/container configuration.
- Node relay app, server adapter, SQLite storage, quota/metrics/admin/static/WebSocket paths, and their test suites.
- English as the primary UI language, with compilation-level French key coverage.

Limitations:

- No production/live deployment or non-loopback network was contacted.
- Existing `packages/relay/data/relay.db*` files were not read, copied, migrated, or modified.
- Browser automation and visual/mobile inspection were not completed after the owner asked to continue without that task. Consequently, service-worker lifecycle, actual IndexedDB interruption, offline/reconnect UI, narrow layouts, keyboard order, contrast, and real accessibility trees remain release-test obligations.
- No iOS/iPadOS, Android, Firefox, Edge, Safari, VoiceOver, or NVDA device session was run.
- No deliberate resource exhaustion was attempted; large-file/page findings are source-derived.
- RR-001, RR-002, RR-003, RR-007, RR-008, and RR-010 are established by source-level failure sequences rather than a destructive runtime reproduction. Each sequence was re-read against recovery paths and existing tests.
- The review did not recursively inspect dependency or vendored package internals and did not conduct an exhaustive translation-quality or formal legal-compliance audit.
- Cybersecurity review and related assurance are excluded.

## 14. Prioritized remediation plan

### Before release

1. **Make browser persistence atomic (RR-001).** Provide atomic event-plus-queue and group lifecycle operations; make identity creation persistence-gated. Add failure injection first so each interruption boundary is reproducible.
2. **Define and implement multi-tab coordination (RR-002).** Serialize per-group mutation/sync and broadcast state invalidation, or explicitly prevent secondary-tab mutation.
3. **Refresh time correctly (RR-003).** Use real timer values and visibility/action refreshes; test midnight and background/resume.
4. **Name every action (RR-004).** Make localized accessible labels mandatory in icon-button/FAB APIs and run automated plus manual assistive-technology checks.
5. **Add browser release tests (RR-011).** Cover the fixed blocker sequences plus first use, offline/reconnect, reload persistence, and service-worker update.
6. Rerun all isolated gates and execute the practical browser matrix on desktop and mobile/narrow viewports.

### Short term

1. Complete notification mappings and error/deployment states (RR-005, RR-006).
2. Bound import memory and provide progress/error UX (RR-007).
3. Make relay append accounting transactional and add reconciliation validation (RR-008).
4. Add graceful shutdown, health/readiness, and the self-host operations runbook (RR-009).
5. Implement byte-bounded, progress-checked pull pagination (RR-010).

### Post-release acceptable

1. Make self-host social/canonical metadata configurable and complete manifest metadata (RR-012).
2. Expand the browser suite across scheduled Firefox/WebKit jobs and add device-assisted accessibility checks.
3. Periodically rehearse relay restart, rollback, disk alert, restore/rehydration, and long-idle retention scenarios.

## 15. Final release checklist

- [ ] RR-001 fixed; event and queue/group operations pass interruption fault-injection tests.
- [ ] RR-002 fixed or secondary-tab mutation explicitly prevented; two-tab convergence test passes.
- [ ] RR-003 fixed; controlled midnight and resume tests pass for all date-sensitive flows.
- [ ] RR-004 fixed; every interactive control has a localized accessible name and core screen-reader flow passes.
- [ ] Elm, relay, formatting, lint, and optimized same-origin build gates pass from a clean isolated environment.
- [ ] Browser integration suite covers first use, create/join, entry save/reload, offline/reconnect, multi-tab, storage failure, and service-worker update.
- [ ] Current/previous Chrome, Edge, Firefox, Safari desktop smoke tests pass.
- [ ] Current Android Chrome/Edge/Firefox and iOS/iPadOS Safari smoke tests pass at narrow viewport and installed-PWA modes where supported.
- [ ] Notification availability, privacy disclosure, and platform restrictions are clear; specified notification types are tested.
- [ ] Import rejects files outside the supported size envelope without freezing the page.
- [ ] Relay append/accounting is atomic; graceful shutdown and health/readiness checks pass.
- [ ] Self-host runbook covers immutable image tag, volume, disk alerts, restart, rollback, retention, and recovery/rehydration.
- [ ] Pull pages are byte-bounded and client pagination fails safely on non-progress.
- [ ] Final Git diff contains only reviewed owner-intended plan/report changes; no source, generated output, lockfile, existing data, or relay database was modified.

**Final decision remains NO-GO until the four High release blockers are resolved and verified.**
