# Feasibility Study: Partage in Elm

> Assessment of building the Partage bill-splitting PWA as an Elm application
> using the recommended library stack.

---

## Executive Summary

Building Partage in Elm is **feasible**. The recommended library stack covers every major technical requirement — encryption, IndexedDB persistence, PocketBase sync, PWA lifecycle, i18n, forms, UUID generation, and UI — with no fundamental blockers. The main costs are (1) integration effort from using several unpublished/embedded libraries sharing an `elm-concurrent-task` backbone, and (2) custom UI component work that elm-ui v2 does not provide out of the box.

| Verdict | Confidence |
|---------|------------|
| **Go** | High — all critical paths have library support; remaining gaps are solvable with application code. |

---

## 1. Library Stack Overview

| Concern | Library | Published? | Integration |
|---------|---------|-----------|-------------|
| UI layout & styling | elm-ui v2 (branch `2.0`) | No (embed) | Git submodule + elm-animator v2 |
| Forms | dwayne/elm-form + elm-field + elm-validation | Yes | `elm install` |
| Encryption | elm-webcrypto | No (embed) | Git submodule, elm-concurrent-task |
| IndexedDB | elm-indexeddb | No (embed) | Git submodule, elm-concurrent-task |
| PocketBase client | elm-pocketbase | No (embed) | Git submodule, elm-concurrent-task |
| PWA lifecycle | elm-pwa | No (embed) | Git submodule, 2 ports |
| Navigation | Port-based + elm-app-url | elm-app-url published | 2 ports + JS glue |
| i18n | travelm-agency | Yes (CLI) | Build step, Fluent files |
| Async task runner | elm-concurrent-task | Yes | 2 ports, JS runtime |
| Virtual DOM safety | elm-safe-virtual-dom | No (kernel patch) | ELM_HOME patching script |
| Core utilities | elmcraft/core-extra | Yes | `elm install` |
| Custom-key Dicts | turboMaCk/any-dict | Yes | `elm install` |
| UUIDs | elm-uuid (upgraded fork) | No (embed) | Git submodule |

Five unpublished libraries (elm-webcrypto, elm-indexeddb, elm-pocketbase, elm-pwa, elm-uuid) plus elm-ui v2 and elm-animator v2 must be embedded as git submodules with their source directories added to `elm.json`. Four of the unpublished libs share `elm-concurrent-task` as their async backbone, which simplifies wiring: a single pair of `send`/`receive` ports serves all of them.

---

## 2. Feature-by-Feature Assessment

### 2.1 Encryption & Security

**Requirement:** AES-256-GCM data encryption, ECDSA P-256 signatures, SHA-256 hashing, PoW challenge solving, key import/export.

**Coverage:** elm-webcrypto supports all of the above. Specifically:
- `WebCrypto.Symmetric`: generateKey, encrypt/decrypt (raw bytes, strings, JSON), importKey/exportKey (Base64).
- `WebCrypto.Signature`: generateSigningKeyPair, sign, verify (P-256 + SHA-256).
- `WebCrypto.KeyPair`: ECDH P-256 key generation, public key hashing (SHA-256).
- `WebCrypto.sha256` / `sha256Hex`: hashing.
- `WebCrypto.ProofOfWork`: SHA-256 PoW solving in a Web Worker (non-blocking).

**Gap — Password derivation from group key:** The spec requires `Base64URL(SHA-256(Base64(groupKey)))`. SHA-256 is available; Base64URL encoding needs a small Elm helper (trivial).

**Gap — No HKDF/PBKDF2:** Not needed by the spec, which uses direct symmetric keys.

**Risk:** Low. All required primitives are present.

### 2.2 Local Storage (IndexedDB)

**Requirement:** Persist identity, group keys, event logs, computed state cache, pending events, usage statistics.

**Coverage:** elm-indexeddb provides typed stores (InlineKey, ExplicitKey, GeneratedKey) with full CRUD, batch operations, automatic schema migrations on version bump, secondary indexes, and key range queries.

**Key features for Partage:**
- **Secondary indexes** (`defineIndex`, `uniqueIndex`, `multiEntryIndex`): enable efficient queries on non-primary-key fields. Indexes are synced automatically when the schema version is bumped.
- **Key ranges** (`from`, `above`, `upTo`, `below`, `between`, `only`): filter queries at the IndexedDB level so only matching records are transferred to Elm.
- **`PosixKey`**: stores timestamps as native `Date` objects in IndexedDB, enabling correct time-based ordering and range queries.
- **Index queries** (`getByIndex`, `getKeysByIndex`, `countByIndex`): query records by indexed fields with key ranges.
- **Range deletions** (`deleteInRange`): efficiently remove records matching a key range.

**Mapping to spec stores:**

| Spec Store | IndexedDB Store Type | Key Strategy | Indexes |
|-----------|---------------------|-------------|---------|
| Identity (keypair) | ExplicitKey | `StringKey "identity"` | — |
| Group keys | ExplicitKey | `StringKey groupId` | — |
| Group metadata | InlineKey | keyPath = `"id"` | — |
| Events (per group) | InlineKey | keyPath = `"id"` | `byGroupId` on `"groupId"`, `byTimestamp` on `"timestamp"` |
| Computed state cache | ExplicitKey | `StringKey groupId` | — |
| Pending events | GeneratedKey | auto-increment | `byGroupId` on `"groupId"` |
| Usage statistics | ExplicitKey | `StringKey "stats"` | — |

The events store benefits directly from indexes: `getByIndex db eventsStore byGroupId (only (StringKey groupId))` fetches all events for a single group without loading the entire store. For incremental sync, a `PosixKey`-based timestamp index enables `between` range queries.

**Gap — No multi-store transactions:** Each operation is a single-store transaction. This is acceptable since the spec's event-sourced design never requires atomic writes across stores.

**Risk:** Low. The library's index and range query support maps directly to the event-sourced data model.

### 2.3 Server Sync (PocketBase)

**Requirement:** Auth with derived password, push/pull encrypted events, real-time SSE subscriptions, PoW challenge fetching, user account creation.

**Coverage:**
- `PocketBase.Auth.authWithPassword`: authenticates with username/password.
- `PocketBase.Auth.createAccount`: creates per-group server accounts (username `group_{groupId}` with derived password).
- `PocketBase.Auth.updateAccount` / `deleteAccount` / `requestPasswordReset`: full account lifecycle.
- `PocketBase.Auth.refreshAuth`: token refresh.
- `PocketBase.Collection.create`: pushes encrypted event records.
- `PocketBase.Collection.getOne` / `getList`: fetches events with filter/sort (supports PocketBase filter syntax for incremental sync).
- `PocketBase.Collection.update` / `delete`: full CRUD (not needed for append-only events, but available).
- `PocketBase.Realtime.subscribe`: SSE subscriptions for live updates.
- `PocketBase.Custom.fetch`: raw HTTP for the PoW challenge endpoint (`GET /api/pow/challenge`).

All spec server interactions are directly supported — no workarounds via `Custom.fetch` needed for core operations.

**Risk:** Low.

### 2.4 Event Sourcing & State Computation

**Requirement:** Immutable event log, deterministic replay by `(clientTimestamp, clientEventId)`, member state machine, entry versioning with last-writer-wins.

**Coverage:** This is pure application logic — no library needed. Elm is excellent for this:
- Events are algebraic data types.
- Replay is a fold over a sorted list.
- Member state machine is a pattern match.
- Deterministic ordering is a custom comparator on `(Int, String)` tuples.

**Concern — Integer arithmetic for balances:** The spec requires cent-based integer arithmetic with deterministic remainder distribution. Elm's `Int` is a 53-bit JavaScript number. For bill-splitting amounts in cents, this is more than sufficient (max safe integer is ~9 quadrillion cents). The `remainderBy` function and integer division (`//`) are available in `elm/core`.

**UUID generation:** The upgraded elm-uuid fork provides exactly what this project needs:
- **V7 UUIDs** (`UUID.generatorV7`): time-sortable UUIDs embedding a Unix millisecond timestamp. Ideal for event IDs since they naturally support the spec's `(clientTimestamp, clientEventId)` ordering — lexicographic comparison of V7 UUIDs respects chronological order.
- **Monotonic ordering** (`UUID.stepV7` / `UUID.initialV7State`): guarantees strict ordering even when multiple events are created within the same millisecond, preventing collisions in the deterministic sort.
- **V4 UUIDs** (`UUID.generator`): available for member IDs and other cases where time-ordering is not needed.
- **Pure Elm**: no ports or concurrent tasks required. Uses `Random.Generator` seeded from `crypto.getRandomValues()` via flags.

**Risk:** Low. Elm's type system is ideal for event sourcing, and V7 UUIDs are a natural fit for the event ordering model.

### 2.5 Balance Calculation & Settlement

**Requirement:** Per-member net balance, shares-based and exact splitting, deterministic rounding, settlement plan with preference-aware + greedy passes.

**Coverage:** Pure Elm computation. Key considerations:
- Shares-based split with remainder distribution: sort beneficiaries by member ID, distribute remainder cents. Straightforward with `List.sortBy` and fold.
- Settlement algorithm (two-pass greedy): stateful fold with accumulator. Elm handles this cleanly.
- All arithmetic in integer cents avoids floating-point issues.

**Risk:** Low.

### 2.6 UI & Responsive Design

**Requirement:** Mobile-first PWA, 4-tab group view, forms, cards, modals, toasts, FAB, offline banner, color-coded balances, QR codes.

**Coverage (elm-ui v2):**
- Layout: `el`/`row`/`column` with `padding`/`spacing`, `fill`/`shrink`/`portion`.
- Responsive: CSS-based breakpoints via `Ui.Responsive` — no JS subscriptions.
- Inputs: buttons, text fields, checkboxes, choice inputs (radio).
- Tables: `Ui.Table` with sorting and sticky headers.
- Animations: `Ui.Anim` for transitions and keyframes.
- Accessibility: `Ui.Accessibility` for ARIA landmarks.

**Gaps requiring custom components:**

| Component | Effort | Approach |
|-----------|--------|---------|
| Tab bar | Medium | `row` of buttons with active state styling |
| Modal / dialog | Medium | Overlay `el` with backdrop, z-index management |
| Toast notifications | Medium | Stacked `column` with auto-dismiss timers (subscription) |
| Floating Action Button | Low | Fixed-position `el` with `Ui.Anim` |
| Dropdown / select | Medium | Custom with open/close state |
| Date picker | High | Custom or use native HTML input via `Ui.html` |
| QR code | Medium | Port to JS QR library or pure Elm QR encoder |
| Offline banner | Low | Conditional `el` with ARIA attributes |
| Confirmation dialogs | Medium | Reuse modal component |

**Concern — elm-ui v2 is unpublished:** Must embed source + elm-animator v2. Both are mature but not officially released. Breaking changes are possible but unlikely at this stage.

**Concern — Native HTML inputs:** For date pickers and complex selects, `Ui.html` allows embedding raw HTML elements within elm-ui layouts. This is a well-supported escape hatch.

**Risk:** Medium. Significant custom component work, but all achievable. The responsive story is strong.

### 2.7 Forms

**Requirement:** Expense form with multiple payers, beneficiary splits (shares/exact), transfer form, member metadata forms, group creation form with PoW.

**Coverage (dwayne/elm-form):**
- Dynamic sub-form lists via `Form.List` — ideal for multiple payers/beneficiaries.
- Conditional validation via `V.andThen` — handles shares vs. exact split branching.
- Cross-field validation — sum-must-equal-total checks.
- Dirty tracking via `Field.isDirty` — show errors only after interaction.
- Fully UI-agnostic — works with elm-ui v2.

**Concern — Accessor boilerplate:** Each field needs a `{ get, modify }` record. For forms with many fields (expense form has ~10 fields + dynamic lists), this is verbose but manageable. Helper functions can reduce repetition.

**Risk:** Low. The library is well-suited for this use case.

### 2.8 Navigation & Routing

**Requirement:** 8 routes including parameterized routes (`/groups/:groupId`, `/join/:groupId#key`), route guards, SPA navigation.

**Coverage:** Port-based navigation with elm-app-url:
- `pushUrl` for page navigation.
- `replaceUrl` for cosmetic URL updates.
- `popstate` handling for back button.
- `AppUrl.fromUrl` for path segment pattern matching.

**Route implementation:**

```
/setup             -> [] with guard
/                  -> [] (home)
/groups/new        -> ["groups", "new"]
/join/:id#key      -> ["join", id] with fragment extraction
/groups/:id        -> ["groups", id]
/groups/:id/:tab   -> ["groups", id, tab]
/about             -> ["about"]
```

**Concern — Fragment extraction for group key:** The URL fragment (`#base64key`) is available in the `Url` type from `elm/url`. `AppUrl` preserves it. The key extraction is straightforward.

**Concern — Route guards:** Implemented as Elm logic: check identity exists in model, redirect to `/setup` if not. No library needed.

**Risk:** Low.

### 2.9 PWA Lifecycle

**Requirement:** Service worker caching (cache-first for assets, network-first for API), install prompts, offline detection, auto-update.

**Coverage (elm-pwa):**
- `ConnectionChanged Bool`: offline/online detection.
- `UpdateAvailable`: service worker update notification.
- `InstallAvailable` / `requestInstall`: install prompt handling.
- `acceptUpdate`: seamless service worker transition.
- `generateSW()`: build-time service worker generation with cache-first, network-first, and network-only strategies.

**Gap — iOS install instructions:** The spec requires manual install instructions for iOS (after 30-second delay). This is application-level UI logic, not a library concern. Timer via `Process.sleep` + conditional rendering.

**Gap — Install prompt re-appearance after 7 days:** Application-level logic using localStorage timestamp.

**Risk:** Low.

### 2.10 Internationalization

**Requirement:** 3 languages (en, fr, es), ~200 keys, interpolation, locale-aware currency/date/number formatting, language auto-detection.

**Coverage (travelm-agency):**
- Compile-time code generation from translation files.
- One type-safe function per key with enforced placeholders.
- Inline mode (all translations in bundle) or dynamic mode (load via HTTP).
- Language switching at runtime.

**Fluent format enables:**
- `NUMBER($amount, style: "currency", currency: "EUR")` for locale-aware currency formatting.
- `DATETIME($date, dateStyle: "full")` for locale-aware dates.
- Plural rules.

**Dependency:** Requires `intl-proxy` npm + Elm packages for formatting.

**Gap — Relative time formatting:** "5 minutes ago", "yesterday" etc. Not built into travelm-agency. Options: (a) Use `Intl.RelativeTimeFormat` via a port or concurrent task, or (b) compute relative labels in Elm and use translation keys like `timeAgo.minutes { count }`.

**Risk:** Low. Fluent format covers all needs with minor custom work for relative time.

### 2.11 Import / Export

**Requirement:** JSON export of decrypted group data, import with merge analysis (new, subset, diverged).

**Coverage:** Pure Elm:
- JSON encoding/decoding with `elm/json`.
- File download via a port or `File.Download` (from `elm/file`).
- File upload via `File.Select` + `File.toString`.
- Merge analysis is application logic (set operations on event IDs).

**Risk:** Low.

### 2.12 Usage Statistics & Cost Estimation

**Requirement:** Track bytes transferred, storage size, compute cost estimates. Local only.

**Coverage:**
- Byte tracking: wrap PocketBase operations to count request/response sizes. Achievable with `ConcurrentTask.andThen` or `ConcurrentTask.withDuration`.
- Storage estimation: `navigator.storage.estimate()` via a concurrent task.
- Cost calculation: pure Elm arithmetic.

**Risk:** Low.

---

## 3. Architecture Considerations

### 3.1 elm-concurrent-task as the Backbone

Four libraries (elm-webcrypto, elm-indexeddb, elm-pocketbase, and partially elm-pwa) use elm-concurrent-task. This creates a unified async model:

**Advantages:**
- Single pair of `send`/`receive` ports for all async operations.
- Composable task chains: `open DB → decrypt events → compute state`.
- Concurrent initialization: `ConcurrentTask.map3` to load identity + groups + stats in parallel.

**Concern — Pool management:** The `ConcurrentTask.Pool` must be stored in the model and updated on every `OnProgress` message. With multiple concurrent task chains (DB ops + crypto + network), the pool handles multiplexing automatically.

**Concern — Error handling:** Different libraries use different error types. Use `ConcurrentTask.mapError` to normalize into an application-level error type.

### 3.2 Data Flow Architecture

```
User Action
  → Elm Msg
    → Create Event (pure)
      → Encrypt Event (ConcurrentTask: elm-webcrypto)
        → Store Locally (ConcurrentTask: elm-indexeddb)
          → Push to Server (ConcurrentTask: elm-pocketbase)
            → Update Model (pure)

Server SSE Event
  → Port (elm-pocketbase)
    → Decrypt (ConcurrentTask: elm-webcrypto)
      → Store Locally (ConcurrentTask: elm-indexeddb)
        → Replay & Update Model (pure)
```

This is a natural fit for Elm's unidirectional data flow. Each step is a composable task.

### 3.3 Model Structure

```elm
type alias Model =
    { identity : Maybe Identity
    , groups : Dict String GroupState
    , activeGroup : Maybe String
    , page : Page
    , taskPool : ConcurrentTask.Pool Msg
    , pwa : PwaState
    , i18n : I18n
    , online : Bool
    , ... -- UI state (modals, forms, toasts)
    }

type alias GroupState =
    { events : List Event           -- sorted event log
    , members : Dict String Member  -- computed from events
    , entries : Dict String Entry   -- computed from events
    , pendingEvents : List Event    -- awaiting sync
    , syncCursor : String           -- PocketBase `created` timestamp
    , groupKey : SymmetricKey
    , ...
    }
```

### 3.4 elm-safe-virtual-dom

Recommended to protect against DOM modification by browser extensions (Grammarly, Google Translate). Setup requires the patching script and a local `ELM_HOME`. This is a build-time concern, not a runtime concern.

---

## 4. Risk Register

| # | Risk | Likelihood | Impact | Mitigation |
|---|------|-----------|--------|-----------|
| 1 | elm-ui v2 breaks before official release | Low | High | Pin git commit; minimal surface area exposed |
| 2 | elm-concurrent-task performance under heavy load | Low | Medium | Profile early; task pool handles backpressure |
| 3 | IndexedDB storage limits on iOS Safari | Medium | Medium | Monitor `navigator.storage.estimate()`; warn users |
| 4 | Browser extension DOM corruption | Medium | High | Use elm-safe-virtual-dom |
| 5 | Complex form state management (expense form) | Medium | Medium | elm-form handles dynamic lists well; prototype early |
| 6 | Custom UI component effort (modals, toasts, tabs) | Certain | Medium | Build a small component library incrementally |
| 7 | Relative time formatting in i18n | Low | Low | Custom Elm logic + translation keys |
| 8 | QR code generation | Low | Low | Use JS library via port or find Elm package |
| 9 | Build tooling complexity (submodules, ELM_HOME, travelm-agency CLI) | Medium | Low | Document in Makefile/scripts; CI handles it |

---

## 5. What Elm Brings to This Project

Elm is a particularly good fit for Partage because of:

1. **Deterministic state computation.** The event-sourcing model with replay and conflict resolution maps directly to pure functions and algebraic data types. Elm's compiler guarantees exhaustive pattern matching on event types and member states.

2. **No runtime exceptions.** For a financial application handling real money splits, Elm's guarantee of no runtime crashes (barring kernel bugs) is valuable. Combined with elm-safe-virtual-dom, even browser extension interference is handled.

3. **Refactoring confidence.** The spec has 19 sections of interrelated logic. Elm's type system makes cross-cutting changes (e.g., adding a new event type, changing member state transitions) safe to propagate through the entire codebase.

4. **Integer arithmetic for money.** Elm's `Int` type with explicit integer division (`//`) and `remainderBy` naturally supports cent-based calculations without floating-point surprises.

---

## 6. What Requires Extra Attention

1. **Build tooling.** Six git submodules (elm-webcrypto, elm-indexeddb, elm-pocketbase, elm-pwa, elm-uuid, elm-ui v2 + elm-animator v2), an ELM_HOME patch script, a travelm-agency build step, and service worker generation need to be orchestrated. A Makefile or npm script pipeline is essential.

2. **Custom UI components.** Modals, toasts, tab bars, date pickers, dropdowns, and FABs are not provided by elm-ui v2. Budget significant time for a component layer, or consider using `Ui.html` to embed native HTML elements for complex inputs.

3. **Testing strategy.** Pure functions (event replay, balance calculation, settlement) are trivially testable with `elm-test`. Port-based features (crypto, IndexedDB, PocketBase) require either integration tests or careful mocking via elm-concurrent-task's test helpers.

4. **Bundle size.** Embedding elm-ui v2, elm-animator v2, and inline translations adds to the JS bundle. Profile early. The service worker's cache-first strategy mitigates load-time impact after the first visit.

---

## 7. Recommended Implementation Order

| Phase | Scope | Key Libraries |
|-------|-------|--------------|
| 1. Foundation | Project setup, build pipeline, navigation, identity generation, setup screen | elm-concurrent-task, elm-webcrypto, elm-app-url, elm-pwa |
| 2. Local data | IndexedDB schema, event store, basic event replay | elm-indexeddb |
| 3. Group CRUD | Group creation (with PoW), group listing, group deletion | elm-pocketbase, elm-webcrypto |
| 4. Members | Member events, state machine, join flow, claiming | Pure Elm |
| 5. Entries | Expense/transfer forms, entry creation/edit/delete, splitting logic | elm-form, elm-ui v2 |
| 6. Balances | Balance computation, settlement algorithm, settlement preferences | Pure Elm |
| 7. Sync | PocketBase push/pull, real-time SSE, offline queue, conflict resolution | elm-pocketbase |
| 8. UI polish | Tabs, modals, toasts, FAB, responsive, animations, QR codes | elm-ui v2 |
| 9. i18n | Translation files, travelm-agency integration, locale formatting | travelm-agency |
| 10. PWA | Service worker, install prompt, offline banner, auto-update | elm-pwa |
| 11. Extras | Import/export, usage statistics, activity feed, filters | Pure Elm + elm/file |

---

## 8. Conclusion

The Partage specification is ambitious but well-matched to Elm's strengths. The recommended library stack covers all critical infrastructure concerns (crypto, storage, networking, PWA). The remaining work is application logic (event sourcing, balances, settlement) where Elm excels, and UI component construction where the effort is predictable.

**The project is feasible. No fundamental blockers exist.**
