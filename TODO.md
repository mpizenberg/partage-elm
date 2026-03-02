# Partage — Remaining Implementation Plan

Features not yet implemented, ordered local-first. Server sync, encryption, and PWA come last.

---

## Phase 1: Local UI Completions

Small gaps between the spec and the current local-only implementation.

### 1.1 Full currency picker in group creation form

The `Form.NewGroup` view only shows 4 currencies (EUR, USD, GBP, CHF) as radio buttons. All 10 supported currencies (`Domain.Currency.allCurrencies`) should be selectable. Use radio buttons for now.

**Files:** `src/Form/NewGroup.elm`, `src/Page/NewGroup.elm`

### 1.2 Toast notification system

The spec requires in-app toast notifications for success/error feedback (entry added, error saving, etc.). Currently there is no toast system.
Evaluate if it’s possible to use our elm-animator vendored dependency for that, and prioritize fully stateless animations.
We do not want stateful threading of time through the update loop.

**Design:**
- Add a `toasts : List Toast` field to `Model` (each with id, message, level, expiry time).
- Render as a fixed overlay at the top or bottom of the screen.
- Auto-dismiss after a configurable duration.
- Wire into submission handlers (entry saved, member added, import success/failure, etc.).

**Files:** new `UI/Toast.elm`, `src/Main.elm` (model + view + subscriptions for auto-dismiss)

### 1.3 Confirmation dialogs for destructive actions

Group deletion already has a two-stage confirm. Entry deletion and entry restoration currently happen immediately. The spec says destructive actions require explicit confirmation.

**Scope:**
- Entry delete: show a confirmation before creating the delete event.
- Entry restore: show a confirmation before creating the undelete event.

**Files:** `src/Main.elm` (add a `pendingConfirmation` field to model), `src/Page/EntryDetail.elm`

### 1.4 "Pay Them" button on balance cards

The spec says a "Pay Them" button should appear on balance cards of creditors, enabling quick settlement. Currently balance cards are display-only.

**Design:** The button navigates to the new-entry form pre-filled as a transfer from the current user to the creditor, with the owed amount.

**Files:** `src/UI/Components.elm` (balanceCard), `src/Page/Group/BalanceTab.elm`, `src/Page/NewEntry.elm` (accept pre-fill parameters via init)

### 1.5 Clickable payment links and phone numbers

The spec says some payment methods generate clickable links (Lydia, Revolut, PayPal, Venmo, Bitcoin) and phone numbers are clickable `tel:` links. Currently metadata is displayed as plain text.

- `https://pay.lydia.me/l?t=${normalized}`
- `https://revolut.me/${normalized}`
- `https://paypal.me/${normalized}`
- `https://venmo.com/${normalized}`
- `bitcoin:${value}`

**Files:** `src/Page/MemberDetail.elm`

### 1.6 Copiable payment details

Payment details should be displayed as copiable text (click-to-copy or copy button). May require a port or the Clipboard API.
Cleanest approach might be using a custom element web component.

**Files:** `src/Page/MemberDetail.elm`, `public/index.js` (port for clipboard)

---

## Phase 2: Filtering & Sorting

### 2.1 Entry filters

Entries can be filtered by multiple criteria simultaneously:

- **Person** (AND): entry must involve ALL selected persons.
- **Category** (OR): entry must match ANY selected category. Transfers have a virtual "transfer" category.
- **Currency** (OR): entry must use ANY selected currency.
- **Date range** (OR): entry date must fall within ANY selected range.

Cross-type combination: all active filter types combined with AND.

**Design:**
- Add a `FilterState` type holding active filters per dimension.
- Add filter UI above the entry list (collapsible filter bar with chips/dropdowns).
- Apply filters in `Page.Group.EntriesTab` before rendering.

**Files:** new `src/Domain/Filter.elm` (types + predicate logic), `src/Page/Group/EntriesTab.elm` (UI + state), translations

### 2.2 Date presets

Predefined date ranges: Today, Yesterday, Last 7 days, Last 30 days, This month, Last month, Custom (user-defined start/end).

**Files:** `src/Domain/Filter.elm`, `src/Page/Group/EntriesTab.elm`, translations

### 2.3 Activity filters

Activities can be filtered by:
- Activity type (entry events, member events).
- Actor (who performed the action).
- Involved members.

**Files:** `src/Page/Group/ActivitiesTab.elm`, translations

---

## Phase 3: Import/Export Enhancements

### 3.1 Export with group key

Currently export includes group summary + events. When encryption is added, the export should optionally include the group symmetric key so that the import side can decrypt.

**Files:** `src/GroupExport.elm`

### 3.2 Import merge analysis (future)

Detect relationship between local and imported data (`new`, `local_subset`, `import_subset`, `diverged`) and merge diverged groups by union of events deduplicated by event ID. Currently rejects duplicate group IDs.

*Deferred until sync is implemented, since merge logic is shared.*

---

## Phase 4: Spanish Translations

### 4.1 Add `messages.es.json`

Translate all ~221 keys from English and French to Spanish.

### 4.2 Add Spanish to language selector

Add a Spanish flag option (🇪🇸) to the language selector.

**Files:** `translations/messages.es.json`, `src/UI/Components.elm` (languageSelector), possibly `src/Main.elm`

---

## Phase 5: Usage Statistics

### 5.1 Local usage tracking

Track locally (never sent to server):
- Total bytes transferred (cumulative network bandwidth).
- Storage size (estimated, updated at most once per day).
- Tracking start date.

**Design:**
- Add a `usageStats` IndexedDB store.
- Use `PerformanceResourceTiming` API with `transferSize` to monitor (start and observer) network usage.
- For storage costs, estimate total storage of all local groups, and update a total storage cost since last checked with a linear increase.

### 5.2 Cost estimation display

Show on the About screen: base cost, storage, compute, network, total, average per month. Rates from spec (Section 17.2).

**Files:** `src/Page/About.elm`, translations

### 5.3 Reset usage statistics

Allow users to reset their usage stats (e.g., after a donation).

**Files:** `src/Page/About.elm`, `src/Storage.elm`

---

## Phase 6: Encryption & Security

### 6.1 AES-256-GCM encrypt/decrypt

Implement encrypt and decrypt functions using `elm-webcrypto`. Each call takes a key + plaintext/ciphertext and returns ciphertext/plaintext. Use 12-byte random IV, prepended to ciphertext.

**Files:** new `src/Crypto.elm`, `vendor/elm-webcrypto` (may need new bindings)

### 6.2 Group key generation

Generate an AES-256 symmetric key at group creation. Store in `groupKeys` IndexedDB store (already exists).

**Files:** `src/Crypto.elm`, `src/Submit.elm` (newGroup), `src/Storage.elm`

### 6.3 Encrypt events before storage

All event payloads are encrypted with the group key before writing to IndexedDB and before sending to the server. Decrypt on read.

**Files:** `src/Storage.elm`, `src/Crypto.elm`, `src/Main.elm`

### 6.4 Password derivation from group key

Derive server account password as `Base64URL(SHA-256(Base64(groupKey)))`.

**Files:** `src/Crypto.elm`

---

## Phase 7: Server Sync

### 7.1 PocketBase HTTP client

Module for server API calls: auth (create user, login, refresh token), group CRUD, event push/pull.

**Files:** new `src/Server.elm` or `src/PocketBase.elm`

### 7.2 Proof-of-Work solver

Solve SHA-256 PoW challenge (18 leading zero bits) in a Web Worker to avoid blocking UI. Requires a port to dispatch work and receive the solution.

**Files:** new `public/pow-worker.js`, `public/index.js` (ports), `src/Main.elm`

### 7.3 Server authentication flow

On group creation: solve PoW, create group record, create user account, authenticate. On group load: authenticate with derived password, receive JWT.

**Files:** `src/Server.elm`, `src/Main.elm`

### 7.4 Event push/pull sync

- Push: encrypt local events, POST to server.
- Pull: GET events since last sync cursor, decrypt, apply.
- Track sync cursor per group in IndexedDB.

**Files:** `src/Server.elm`, `src/Storage.elm` (sync cursor), `src/Main.elm`

### 7.5 Real-time subscriptions

Server-sent events (SSE) connection to PocketBase `/api/realtime` for live event updates. Subscribe per-group.

### 7.6 Offline queue

Events created while offline are queued in a `pendingEvents` IndexedDB store. On connectivity restore, flush the queue.

**Files:** `src/Storage.elm` (new store), `src/Main.elm`

---

## Phase 8: Invitation & Group Joining

Same page for invite link and joining.
Display either depending if you are a member of the group already.

### 8.1 Invite link generation

Build URL: `https://<domain>/join/<groupId>#<base64url-group-key>`. Display in a modal with copy button.

**Files:** `src/Page/Group/MembersTab.elm` (invite button), new modal component, translations

### 8.2 QR code generation

Generate QR code from invite link. Likely requires a JS library (e.g., `qrcode`) via ports or an Elm QR library.

**Files:** `public/index.js` (QR port or inline lib), invite modal

### 8.3 Web Share API

On supported devices, offer native share via `navigator.share()` through a port.

**Files:** `public/index.js` (share port), invite modal

### 8.4 Join flow UI

Implement `JoinGroupScreen` (currently shows "coming soon"):
1. Extract group ID and key from URL.
2. Authenticate to server, fetch and decrypt all events.
3. Show group name and member list.
4. Offer: claim virtual member (primary), re-join as existing real member (collapsed), or join as new member.
5. Record member event and sync.

**Files:** new `src/Page/JoinGroup.elm`, `src/Main.elm` (route handler), `src/Server.elm`, translations

---

## Phase 9: Progressive Web App

Vendor elm-pwa: https://github.com/mpizenberg/elm-pwa

### 9.1 Web app manifest

Create `manifest.json` with app name ("Partage - Bill Splitting"), icons, theme color (`#2563eb`), `display: standalone`, categories (finance, utilities).

**Files:** new `public/manifest.json`, `public/index.html` (link tag)

### 9.2 App icons

SVG icon with maskable variants for adaptive displays. Generate PNG fallbacks at standard sizes (192x192, 512x512).

**Files:** new `public/icons/`

### 9.3 Service worker

Workbox or hand-rolled:
- Cache-first for static assets (JS, CSS, HTML, SVG, WASM, JSON, fonts).
- Network-first for API calls.
- Navigation fallback to `index.html`.
- Max 5 MB per precached resource.

**Files:** new `public/sw.js`, `public/index.js` (registration)

### 9.4 Install prompt

- Intercept `beforeinstallprompt` on Android/Desktop Chrome, show custom install UI.
- Show manual iOS instructions after 30-second delay.
- Dismissible, re-appears after 7 days (tracked in localStorage).
- Not shown in standalone mode.

**Files:** `public/index.js` (event interception), new install prompt component, translations

### 9.5 Auto-update

Service worker update detection. Handle `SKIP_WAITING` for seamless transitions. Optionally notify user of available update.

**Files:** `public/sw.js`, `public/index.js`

### 9.6 Apple-specific meta tags

Add `apple-mobile-web-app-capable`, `apple-mobile-web-app-status-bar-style`, and apple touch icon to `index.html`.

**Files:** `public/index.html`

### 9.7 Connectivity detection & banner

Detect online/offline status. Show an accessible offline banner (`role="alert"`, `aria-live="polite"`). Auto-resync on reconnect.

**Files:** `public/index.js` (online/offline event ports), `src/Main.elm`, translations
