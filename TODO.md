# Partage — Remaining Implementation Plan

Features not yet implemented, ordered local-first. Server sync, encryption, and PWA come last.

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

## Phase 3: Encryption & Security

### 3.1 AES-256-GCM encrypt/decrypt

Implement encrypt and decrypt functions using `elm-webcrypto`. Each call takes a key + plaintext/ciphertext and returns ciphertext/plaintext. Use 12-byte random IV, prepended to ciphertext.

**Files:** new `src/Crypto.elm`, `vendor/elm-webcrypto` (may need new bindings)

### 3.2 Group key generation

Generate an AES-256 symmetric key at group creation. Store in `groupKeys` IndexedDB store (already exists).

**Files:** `src/Crypto.elm`, `src/Submit.elm` (newGroup), `src/Storage.elm`

### 3.3 Encrypt events before storage

All event payloads are encrypted with the group key before writing to IndexedDB and before sending to the server. Decrypt on read.

**Files:** `src/Storage.elm`, `src/Crypto.elm`, `src/Main.elm`

### 3.4 Password derivation from group key

Derive server account password as `Base64URL(SHA-256(Base64(groupKey)))`.

**Files:** `src/Crypto.elm`

---

## Phase 4: Server Sync

### 4.1 PocketBase HTTP client

Module for server API calls: auth (create user, login, refresh token), group CRUD, event push/pull.

**Files:** new `src/Server.elm` or `src/PocketBase.elm`

### 4.2 Proof-of-Work solver

Solve SHA-256 PoW challenge (18 leading zero bits) in a Web Worker to avoid blocking UI. Requires a port to dispatch work and receive the solution.

**Files:** new `public/pow-worker.js`, `public/index.js` (ports), `src/Main.elm`

### 4.3 Server authentication flow

On group creation: solve PoW, create group record, create user account, authenticate. On group load: authenticate with derived password, receive JWT.

**Files:** `src/Server.elm`, `src/Main.elm`

### 4.4 Event push/pull sync

- Push: encrypt local events, POST to server.
- Pull: GET events since last sync cursor, decrypt, apply.
- Track sync cursor per group in IndexedDB.

**Files:** `src/Server.elm`, `src/Storage.elm` (sync cursor), `src/Main.elm`

### 4.5 Real-time subscriptions

Server-sent events (SSE) connection to PocketBase `/api/realtime` for live event updates. Subscribe per-group.

### 4.6 Offline queue

Events created while offline are queued in a `pendingEvents` IndexedDB store. On connectivity restore, flush the queue.

**Files:** `src/Storage.elm` (new store), `src/Main.elm`

---

## Phase 5: Import/Export Enhancements

### 5.1 Export with group key

Currently export includes group summary + events. When encryption is added, the export should optionally include the group symmetric key so that the import side can decrypt.

**Files:** `src/GroupExport.elm`

### 5.2 Import merge analysis (future)

Detect relationship between local and imported data (`new`, `local_subset`, `import_subset`, `diverged`) and merge diverged groups by union of events deduplicated by event ID. Currently rejects duplicate group IDs.

*Deferred until sync is implemented, since merge logic is shared.*

---

## Phase 6: Invitation & Group Joining

Same page for invite link and joining.
Display either depending if you are a member of the group already.

### 6.1 Invite link generation

Build URL: `https://<domain>/join/<groupId>#<base64url-group-key>`. Display in a modal with copy button.

**Files:** `src/Page/Group/MembersTab.elm` (invite button), new modal component, translations

### 6.2 QR code generation

Generate QR code from invite link. Likely requires a JS library (e.g., `qrcode`) via ports or an Elm QR library.

**Files:** `public/index.js` (QR port or inline lib), invite modal

### 6.3 Web Share API

On supported devices, offer native share via `navigator.share()` through a port.

**Files:** `public/index.js` (share port), invite modal

### 6.4 Join flow UI

Implement `JoinGroupScreen` (currently shows "coming soon"):
1. Extract group ID and key from URL.
2. Authenticate to server, fetch and decrypt all events.
3. Show group name and member list.
4. Offer: claim virtual member (primary), re-join as existing real member (collapsed), or join as new member.
5. Record member event and sync.

**Files:** new `src/Page/JoinGroup.elm`, `src/Main.elm` (route handler), `src/Server.elm`, translations

---

## Phase 7: Progressive Web App

Vendor elm-pwa: https://github.com/mpizenberg/elm-pwa

### 7.1 Web app manifest

Create `manifest.json` with app name ("Partage - Bill Splitting"), icons, theme color (`#2563eb`), `display: standalone`, categories (finance, utilities).

**Files:** new `public/manifest.json`, `public/index.html` (link tag)

### 7.2 App icons

SVG icon with maskable variants for adaptive displays. Generate PNG fallbacks at standard sizes (192x192, 512x512).

**Files:** new `public/icons/`

### 7.3 Service worker

Workbox or hand-rolled:
- Cache-first for static assets (JS, CSS, HTML, SVG, WASM, JSON, fonts).
- Network-first for API calls.
- Navigation fallback to `index.html`.
- Max 5 MB per precached resource.

**Files:** new `public/sw.js`, `public/index.js` (registration)

### 7.4 Install prompt

- Intercept `beforeinstallprompt` on Android/Desktop Chrome, show custom install UI.
- Show manual iOS instructions after 30-second delay.
- Dismissible, re-appears after 7 days (tracked in localStorage).
- Not shown in standalone mode.

**Files:** `public/index.js` (event interception), new install prompt component, translations

### 7.5 Auto-update

Service worker update detection. Handle `SKIP_WAITING` for seamless transitions. Optionally notify user of available update.

**Files:** `public/sw.js`, `public/index.js`

### 7.6 Apple-specific meta tags

Add `apple-mobile-web-app-capable`, `apple-mobile-web-app-status-bar-style`, and apple touch icon to `index.html`.

**Files:** `public/index.html`

### 7.7 Connectivity detection & banner

Detect online/offline status. Show an accessible offline banner (`role="alert"`, `aria-live="polite"`). Auto-resync on reconnect.

**Files:** `public/index.js` (online/offline event ports), `src/Main.elm`, translations

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

Show on the About screen: base cost, storage, compute, network, total, average per month. Rates from spec (Section 17.2).

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
