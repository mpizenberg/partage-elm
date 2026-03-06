# Partage — Remaining Implementation Plan

Phases 1–7 are complete. Remaining: usage stats, translations.

---

## Phase 1: Local UI Completions (Done)

All local UI gaps have been addressed.

- **1.1** Full currency picker: all 10 currencies from `Domain.Currency.allCurrencies` shown with wrapped radio buttons in the new group form.
- **1.2** Toast notifications: `UI/Toast.elm` with CSS keyframe animations, auto-dismiss (4s success, 6s error), wired into all submission handlers. Clipboard copy also triggers a toast via an `onClipboardCopy` port.
- **1.3** Entry delete/restore confirmation: `Page.EntryDetail` refactored to a stateful page with two-stage inline confirmation (warning + confirm button), same pattern as group deletion.
- **1.4** "Pay Them" button on balance cards: appears on non-current-user creditor cards, navigates to the new-entry form pre-filled as a locked transfer with the owed amount via `Page.NewEntry.initTransfer`.
- **1.5** Clickable payment links: phone (`tel:`), email (`mailto:`), Lydia, Revolut, PayPal, Venmo, Bitcoin rendered as `Ui.linkNewTab` in `Page.MemberDetail`.
- **1.6** Copiable payment details: `<copy-button>` custom element in `public/index.js` with a clipboard icon next to each value; copy success notifies Elm via port for toast.

---

## Phase 2: Filtering & Sorting (Done)

All filtering features have been implemented with collapsible filter bars and chip-based selection UI.

- **2.1** Entry filters: person (AND), category (OR), currency (OR), date range (OR), cross-type AND. `Domain.Filter.elm` holds pure types and predicate logic. `Page.Group.EntriesTab` converted to stateful page with Model/Msg/update and collapsible filter bar with toggle chips.
- **2.2** Date presets: Today, Yesterday, Last 7 days, Last 30 days, This month, Last month. Date arithmetic in `Domain.Date.elm` (addDays, startOfMonth, endOfMonth, previousMonth).
- **2.3** Activity filters: activity type (entry/member/group events), actor, involved members. `Page.Group.ActivityTab` converted to stateful page with filter bar. `expandedActivities` moved from Main.elm into ActivityTab model.

---

## Phase 3: Encryption & Security (Done)

All encryption and security features have been implemented.

- **3.1** AES-256-GCM encrypt/decrypt: `src/Crypto.elm` wraps `vendor/elm-webcrypto` (`WebCrypto.Symmetric`) for symmetric encryption with random IV. Used for encrypting events before server push and decrypting on pull.
- **3.2** Group key generation: AES-256 symmetric key generated at group creation (`Crypto.generateGroupKey` in `Submit.newGroup`). Stored in `groupKeys` IndexedDB store.
- **3.3** Encrypt events for server sync: Events are encrypted with the group key before pushing to PocketBase and decrypted on pull (`Server.pushSingleEvent`, `Server.decryptServerEvent`). Local IndexedDB stores plaintext events (per-origin isolation is sufficient).
- **3.4** Password derivation from group key: `Crypto.derivePassword` computes `Base64URL(SHA-256(Base64(groupKey)))` for server authentication.

---

## Phase 4: Server Sync (Done)

Full bidirectional sync with PocketBase, including offline support and realtime updates.

- **4.1** PocketBase HTTP client: `vendor/elm-pocketbase` provides `PocketBase.Auth`, `PocketBase.Collection`, `PocketBase.Custom`, `PocketBase.Realtime` modules. `src/Server.elm` wraps these with encryption/decryption logic.
- **4.2** Proof-of-Work solver: `WebCrypto.ProofOfWork` solves SHA-256 PoW challenges via elm-concurrent-task (Web Worker-backed). Server fetches challenge from `/api/pow/challenge` before group creation.
- **4.3** Server authentication flow: Group creation chains PoW → create group record → create user account → authenticate. Group load authenticates with derived password. All in `Server.elm`.
- **4.4** Event push/pull sync: Bidirectional `Server.syncGroup` chains push (encrypt + POST) then pull (GET + decrypt). Sync cursor tracked per group in `syncCursors` IndexedDB store. Paginated pull (200/page) with `+created` sort.
- **4.5** Real-time subscriptions: SSE via `PocketBase.Realtime.subscribe` for the `events` collection. Realtime events trigger a sync to pull and decrypt new data.
- **4.6** Offline queue: Unpushed event IDs tracked in `unpushedIds` IndexedDB store (`Set String` per group). IDs added on local event creation, removed after successful push. `syncInProgress` flag prevents concurrent/duplicate syncs (handles realtime echo). Follow-up sync triggered if new events were added during an ongoing sync.

---

## Phase 5: Import/Export Enhancements (Done)

- **5.1** Export with group key: `src/GroupExport.elm` exports group summary, events, and optional group symmetric key in `partage-group-v1` JSON format. Import validates format and rejects duplicate group IDs.

### 5.2 Import merge analysis (future)

Detect relationship between local and imported data (`new`, `local_subset`, `import_subset`, `diverged`) and merge diverged groups by union of events deduplicated by event ID. Currently rejects duplicate group IDs.

---

## Phase 6: Invitation & Group Joining (Done)

All invitation and group joining features are complete.

- **6.1** Invite link generation: URL format `https://<domain>/join/<groupId>#<base64url-group-key>` with copy button in `Page.Group.MembersTab`. Group key passed as fragment (never sent to server).
- **6.2** Join flow UI: `Page.JoinGroup` extracts group ID and key from URL, authenticates, fetches and decrypts events, shows group name and members, offers claim virtual member / re-join / join as new member options, records member event and syncs.
- **6.3** QR code generation: `pablohirafuji/elm-qrcode` renders the invite link as an inline SVG with a show/hide toggle. `MembersTab` converted to stateful page (Model/Msg/update) to track QR visibility.
- **6.4** Web Share API: `<share-button>` custom element in `public/index.js` calls `navigator.share()` on supported devices, auto-hides when unavailable. Appears alongside the copy button in the invite section.

---

## Phase 7: Progressive Web App (Done)

All PWA features implemented using vendor elm-pwa (https://github.com/mpizenberg/elm-pwa).

- **7.1** Web app manifest: `public/manifest.json` with app name, icons, theme color (`#2563eb`), `display: standalone`.
- **7.2** App icons: SVG (`public/icon.svg`) with maskable variant, PNG fallbacks at 192x192 and 512x512.
- **7.3** Service worker: generated via `build-sw.mjs` using elm-pwa's `generateSW`. Cache-first for static assets, network-first for API, navigation fallback to `index.html`.
- **7.4** Install prompt: `beforeinstallprompt` interception on Android/Desktop Chrome, iOS manual instructions after delay, dismissible with 7-day re-prompt, hidden in standalone mode.
- **7.5** Auto-update: SW update detection with `SKIP_WAITING` support and user notification.
- **7.6** Apple-specific meta tags: apple touch icon and `apple-mobile-web-app-capable` in `index.html`.
- **7.7** Connectivity detection & banner: online/offline via ports, accessible offline banner (`role="alert"`, `aria-live="polite"`), auto-resync on reconnect.
- **7.8** Localized push notifications: readable English fallback body with template data (`data.key`, `data.name`) in `data` field. Sent with `legacy: true` to force SW processing. Elm app persists translation map to IndexedDB on init and language switch. SW transform hook (`public/sw-transform-notification.js`) resolves localized body via IndexedDB lookup and `{param}` substitution. Falls back to English if transform fails or SW is bypassed (e.g., Safari Declarative Web Push).

---

## Phase 8: Usage Statistics

### 8.1 Local usage tracking

Track locally (never sent to server):
- Total bytes transferred (cumulative network bandwidth).
- Storage size (estimated, updated at most once per day).
- Tracking start date.

**Design:**
- Add a `usageStats` IndexedDB store.
- Use `PerformanceResourceTiming` API with `transferSize` to monitor (start and observer) network usage.
- For storage costs, estimate total storage of all local groups, and update a total storage cost since last checked with a linear increase.

### 8.2 Cost estimation display

Show on the About screen: base cost, storage, compute, network, total, average per month. Rates from SPECIFICATION.md (Section 17.2).

**Files:** `src/Page/About.elm`, translations

### 8.3 Reset usage statistics

Allow users to reset their usage stats (e.g., after a donation).

**Files:** `src/Page/About.elm`, `src/Storage.elm`

---

## Phase 9: Spanish Translations

### 9.1 Add `messages.es.json`

Translate all ~221 keys from English and French to Spanish.

### 9.2 Add Spanish to language selector

Add a Spanish flag option (🇪🇸) to the language selector.

**Files:** `translations/messages.es.json`, `src/UI/Components.elm` (languageSelector), possibly `src/Main.elm`
