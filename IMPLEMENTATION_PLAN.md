# Plan: Frontend Implementation

## Context

Domain logic is complete (GroupState, Balance, Settlement) with 79 domain tests + 17 codec roundtrip tests (96 total). We are building the frontend following FEASIBILITY.md (minus elm-safe-virtual-dom), getting to a functional local bill-splitter by Phase 5.

## Library Sources

**Git submodules** (into `vendor/`):

- elm-ui: `https://github.com/mdgriffith/elm-ui` branch `2.0`
- elm-animator: `https://github.com/mdgriffith/elm-animator` branch `v2`
- elm-webcrypto: `https://github.com/mpizenberg/elm-webcrypto`
- elm-indexeddb: `https://github.com/mpizenberg/elm-indexeddb`
- elm-uuid: `https://github.com/mpizenberg/elm-uuid` branch `v7`

**Published packages** (via `elm install`):

- `mpizenberg/elm-url-navigation-port` (navigation, depends on `lydell/elm-app-url`)
- `elmcraft/core-extra`
- `andrewMacmurray/elm-concurrent-task`
- Submodule transitive deps: `avh4/elm-color`, `mdgriffith/elm-bezier`, `TSFoster/elm-bytes-extra`, `TSFoster/elm-md5`, `TSFoster/elm-sha1`

**pnpm**:

- `@andrewmacmurray/elm-concurrent-task` (runtime dependency, from Phase 3)
- devDependencies: `elm-watch`, `run-pty`, `travelm-agency`, `esbuild`, `rimraf`, `shx`

---

## Phase 1: Build Tooling + Navigation ✅

**Goal:** SPA routing with port-based navigation, stub pages with elm/html.

**Status: COMPLETE**

### What was done

- Installed `mpizenberg/elm-url-navigation-port` (pulls in `lydell/elm-app-url` and `elm/url`)
- Created `public/index.html` and `public/index.js` (HTML shell + navigation port wiring)
- Used `pnpm` + `elm-watch` for build tooling instead of a Makefile
- Rewrote `src/Main.elm` as `port module` with `Browser.element`, navigation ports, route parsing, and route guards
- Extended `src/Route.elm` with `fromAppUrl`/`toAppUrl` URL parsing/serialization
- Created stub page modules: `Page.Setup`, `Page.Home`, `Page.About`, `Page.NotFound`, `Page.NewGroup`, `Page.Group`
- Dev workaround: hardcoded `identity = Just "dev"` to bypass guards during Phase 1

### Route table

```
[]                           -> Home
["setup"]                    -> Setup
["groups", "new"]            -> NewGroup
["join", id]                 -> GroupRoute id (Join (fragment or ""))
["groups", id]               -> GroupRoute id (Tab BalanceTab)
["groups", id, "entries"]    -> GroupRoute id (Tab EntriesTab)
["groups", id, "members"]    -> GroupRoute id (Tab MembersTab)
["groups", id, "activities"] -> GroupRoute id (Tab ActivitiesTab)
["groups", id, "new-entry"]  -> GroupRoute id NewEntry
["about"]                    -> About
_                            -> NotFound
```

---

## Phase 2: Static UI with elm-ui v2 ✅

**Goal:** Visually complete prototype rendering hardcoded domain data, with i18n support.

**Status: COMPLETE**

### What was done

#### Dependencies

- Added git submodules: `elm-ui` (branch `2.0`), `elm-animator` (branch `v2`)
- Installed: `elmcraft/core-extra`, `avh4/elm-color`, `mdgriffith/elm-bezier`
- Updated elm.json `source-directories`: `["src", "vendor/elm-ui/src", "vendor/elm-animator/src"]`
- Added pnpm devDependencies: `elm-watch` (2.0.0-beta.12), `run-pty`, `travelm-agency` (^3.8.0), `rimraf`, `shx`

#### Build tooling

- `pnpm dev`: runs `elm-watch hot` + public file watcher + i18n watcher via `run-pty`
- `pnpm build`: `pnpm prebuild && elm-watch make --optimize`
- `pnpm prebuild`: `pnpm i18n && pnpm prepare:dist`
- `pnpm i18n`: `travelm-agency translations --elm_path=src/Translations.elm --inline`

#### Design tokens (`src/UI/Theme.elm`)

```elm
fontSize = { sm = 14, md = 16, lg = 18, xl = 22, hero = 28 }  -- 5 levels
spacing  = { xs = 4, sm = 8, md = 16, lg = 24, xl = 32 }
rounding = { sm = 6, md = 8 }
borderWidth = { sm = 1, md = 2 }
```

- Colors: `primary` (#2563eb), `primaryLight`, `success`, `successLight`, `danger`, `dangerLight`, `white`, neutral scale (200, 300, 500, 700, 900)
- `balanceColor : Balance.Status -> Ui.Color`
- `contentMaxWidth = 768`

#### Application shells (`src/UI/Shell.elm`)

- `appShell : { title : String, headerExtra : Ui.Element msg, content : Ui.Element msg } -> Ui.Element msg`
- `groupShell : { groupName, headerExtra, activeTab, content, onTabClick, tabLabels } -> Ui.Element msg`
- `TabLabels` type alias for translated tab labels
- Header renders title left, `headerExtra` (language selector) right
- Tab bar at bottom with active/inactive styling

#### Reusable components (`src/UI/Components.elm`)

- `balanceCard : I18n -> { name, balance, isCurrentUser } -> Ui.Element msg` — color-coded, personalized status text
- `entryCard : I18n -> { entry, resolveName } -> Ui.Element msg` — expense and transfer cards
- `memberRow : I18n -> { member, isCurrentUser } -> Ui.Element msg` — with "(you)" suffix and "virtual" label
- `settlementRow : I18n -> { transaction, resolveName } -> Ui.Element msg`
- `languageSelector : Language -> (Language -> msg) -> Ui.Element msg` — flag-based (🇬🇧/🇫🇷) with opacity

#### i18n with travelm-agency

- Translation files: `translations/messages.en.json`, `translations/messages.fr.json` (44 keys each)
- Generated `src/Translations.elm` (gitignored) — inline mode, no HTTP needed
- `I18n` and `Language` types threaded through all view functions as first parameter
- All UI strings replaced with `T.*` calls (imported as `Translations as T`)
- Interpolated keys: `homeMemberCount` ({count}), `nameYouSuffix` ({name}), `entryPaidBySingle` ({name}), `entryPaidByMultiple` ({names}), `entryTransferDirection` ({from}, {to})
- Personalized balance text: `balanceIsOwedYou`/`balanceOwesYou` for current user vs `balanceIsOwed`/`balanceOwes` for others
- Language selector in header, language stored in Model, `SwitchLanguage` msg re-inits I18n
- `Flags` includes `language : String` (from `navigator.language`)

#### Sample data (`src/SampleData.elm`)

- 5 members: Alice (Real, current user), Bob (Real), Carol (Virtual), Dave (Real), Eve (Real, retired)
- 4 expenses + 1 transfer producing realistic balances
- Exposes `currentUserId`, `currentUserRootId`, `groupId`, `groupState`, `resolveName`
- `currentUserRootId` resolved via `GroupState.resolveMemberRootId`

#### Page modules (all use `Ui.Element msg`)

- `Main.elm`: `Model` has `route`, `identity`, `i18n`, `language`; `Msg` has `OnNavEvent`, `NavigateTo`, `SwitchTab`, `SwitchLanguage`; unknown group IDs show 404
- `Page.Group`: passes `I18n`, `headerExtra`, `activeTab`, `onTabClick` to `groupShell`; builds `tabLabels` from translations
- `Page.Group.BalanceTab`: balance cards + settlement plan from real domain computation
- `Page.Group.EntriesTab`: entry cards from `GroupState.activeEntries`
- `Page.Group.MembersTab`: active members sorted alphabetically + "Departed" section; uses `rootId` for member comparisons
- `Page.Group.ActivitiesTab`: placeholder "Coming soon"
- `Page.Home`: group list card with sample group
- `Page.Setup`, `Page.About`, `Page.NewGroup`, `Page.NotFound`: simple content pages

#### Key decisions made during Phase 2

- Named the shell module `UI/Shell.elm` (not `UI/Layout.elm` as originally planned)
- Tab bar lives in `UI/Shell.elm` (not `UI/Components.elm`)
- Reduced font sizes from 7 to 5 levels (merged xs into sm, merged xl/xxl into xl)
- Added rounding and borderWidth scales to Theme (not in original plan)
- Added i18n in Phase 2 (originally not planned until later) to catch architectural issues early
- Member comparisons use `rootId` (not `id`) throughout views, anticipating member replacement chains
- Language selector in `UI/Components.elm` (generic, not tied to Main's Msg type)

---

## Phase 3: Async Backbone + Identity ✅

**Goal:** Real cryptographic identity generation via elm-concurrent-task + elm-webcrypto, plus UUID infrastructure.

**Status: COMPLETE**

### What was done

#### Dependencies

- Added git submodules: `elm-webcrypto`, `elm-uuid` (branch `v7`)
- Updated elm.json `source-directories` to include `vendor/elm-webcrypto/src` and `vendor/elm-uuid/src`
- Installed Elm packages: `andrewMacmurray/elm-concurrent-task`, `TSFoster/elm-bytes-extra`, `TSFoster/elm-md5`, `TSFoster/elm-sha1`, `elm/random`, `elm/bytes` (as direct deps)
- Installed pnpm: `@andrewmacmurray/elm-concurrent-task` (runtime), `esbuild` (JS bundling)

#### JS bundling with esbuild

- `public/index.js` now uses ES imports for ConcurrentTask runtime and elm-webcrypto task definitions
- esbuild bundles `public/index.js` → `dist/index.js` (iife format)
- Build scripts updated:
  - `bundle:js`: esbuild one-shot bundle
  - `watch:js`: esbuild watch mode for dev
  - `bundle:html` / `watch:html`: separate HTML copying (replaces old `copydist`/`watch:public`)
  - `prebuild`: `pnpm i18n && pnpm prepare:dist && pnpm bundle:js`
  - `dev`: runs `elm-watch hot` + `watch:html` + `watch:js` + `watch:i18n` via `run-pty`

#### ConcurrentTask integration (`src/Main.elm`)

- New ports: `sendTask` / `receiveTask` for elm-concurrent-task communication
- `Flags` extended: `randomSeed : List Int` (from `crypto.getRandomValues`), `currentTime : Int` (from `Date.now()`)
- `Model` extended: `identity : Maybe Identity`, `generatingIdentity : Bool`, `pool : ConcurrentTask.Pool Msg`, `uuidState : UUID.V7State`
- `Msg` extended: `GenerateIdentity`, `OnTaskProgress`, `OnIdentityGenerated`
- Removed hardcoded `identity = Just "dev"` — app starts with `Nothing`, route guard redirects to `/setup`
- `init`: seeds `Random.Seed` from flags, initializes `UUID.V7State`, creates empty `ConcurrentTask.pool`
- `subscriptions`: `ConcurrentTask.onProgress` alongside existing nav subscription
- `applyRouteGuard` now takes `Maybe Identity` instead of `Maybe String`

#### Identity module (`src/Identity.elm`)

```elm
type alias Identity =
    { publicKeyHash : String
    , signingKeyPair : Signature.SerializedSigningKeyPair
    }

generate : ConcurrentTask WebCrypto.Error Identity
-- generateSigningKeyPair |> mapError never |> andThen (export + sha256 publicKey)

encode : Identity -> Encode.Value
decoder : Decode.Decoder Identity
```

- `generate` chains: `generateSigningKeyPair` (error: `Never`) → `mapError never` → `exportSigningKeyPair` (pure) → `sha256 publicKey` → map to `Identity`
- JSON codecs reuse `Signature.encodeSerializedSigningKeyPair` / `serializedSigningKeyPairDecoder`

#### Setup page (`src/Page/Setup.elm`)

- Signature: `view : I18n -> { onGenerate : msg, isGenerating : Bool } -> Ui.Element msg`
- "Generate Identity" button (primary bg, white text)
- When generating: button disabled (neutral bg), shows "Generating..." text
- Removed old `setupIdentityNote` placeholder text

#### JS initialization (`public/index.js`)

- ES imports: `@andrewmacmurray/elm-concurrent-task`, `vendor/elm-webcrypto/js/src/index.js`
- `ConcurrentTask.register()` with `createTasks()` from elm-webcrypto
- Flags include `randomSeed` and `currentTime`

#### Translations

- Added: `setupGenerateButton` ("Generate Identity" / "Générer une identité"), `setupGenerating` ("Generating..." / "Génération...")
- Removed: `setupIdentityNote`

#### UUID infrastructure (for Phase 5)

- `UUID.V7State` stored in Model, initialized from crypto-random seed
- Pure generation via `UUID.stepV7 : Time.Posix -> V7State -> (UUID, V7State)` — no tasks needed
- Ready to use for event ID generation in Phase 5

---

## Phase 4: Persistent Storage (IndexedDB) ✅

**Goal:** Identity and group data survive page reloads.

**Status: COMPLETE**

### What was done

#### Dependencies

- Added git submodule: `elm-indexeddb` (`https://github.com/mpizenberg/elm-indexeddb`)
- Updated elm.json `source-directories` to include `vendor/elm-indexeddb/src`

#### JS task registration (`public/index.js`)

- Qualified imports: `createWebCryptoTasks` from elm-webcrypto, `createIndexedDbTasks` from elm-indexeddb
- Merged with object spread into single `ConcurrentTask.register()` call:
  ```js
  tasks: { ...createWebCryptoTasks(), ...createIndexedDbTasks() }
  ```

#### JSON codecs added to domain modules

All codecs follow the pattern: `encode*` returns `Encode.Value`, `*Decoder` returns `Decode.Decoder`. No existing behavior changed.

- **`src/Domain/Currency.elm`** — `encodeCurrency` / `currencyDecoder` (lowercase string tags: `"usd"`, `"eur"`, etc.)
- **`src/Domain/Date.elm`** — `encodeDate` / `dateDecoder` (`{ year, month, day }` object)
- **`src/Domain/Group.elm`** — `encodeLink` / `linkDecoder` (`{ label, url }` object)
- **`src/Domain/Member.elm`** — `encodeType` / `typeDecoder` (`"real"` / `"virtual"` strings), `encodePaymentInfo` / `paymentInfoDecoder` (8 optional string fields, omit `Nothing`s), `encodeMetadata` / `metadataDecoder`
- **`src/Domain/Entry.elm`** — Full codec suite:
  - `encodeCategory` / `categoryDecoder` — 9-variant enum as lowercase strings
  - `encodePayer` / `payerDecoder`, `encodeBeneficiary` / `beneficiaryDecoder` (tagged union: `"share"` / `"exact"`)
  - `encodeMetadata` / `entryMetadataDecoder` — 7 fields, `Time.Posix` as millis int
  - `encodeExpenseData` / `expenseDataDecoder` — 10 fields, uses local `andMap` helper (applicative pattern) since `Decode.map8` only covers 8
  - `encodeTransferData` / `transferDataDecoder` — 7 fields via `Decode.map7`
  - `encodeKind` / `kindDecoder` — tagged union with nested `data` field
  - `encodeEntry` / `entryDecoder`
- **`src/Domain/Event.elm`** — `encodeEnvelope` / `envelopeDecoder`, `encodePayload` / `payloadDecoder` (11-variant tagged union with `"type"` discriminator), `encodeGroupMetadataChange` / `groupMetadataChangeDecoder` (handles `Maybe (Maybe String)`: absent = unchanged, `null` = cleared, string = set)

#### Storage module (`src/Storage.elm`)

New module encapsulating IndexedDB schema and all CRUD operations.

Schema (database `"partage"`, version 1):

| Store       | Key type    | KeyPath/Index                                    | Purpose                             |
| ----------- | ----------- | ------------------------------------------------ | ----------------------------------- |
| `identity`  | ExplicitKey | single record at `StringKey "default"`           | User identity                       |
| `groups`    | InlineKey   | keyPath `"id"`                                   | Group summaries for Home page       |
| `groupKeys` | ExplicitKey | `StringKey groupId`                              | Symmetric encryption keys per group |
| `events`    | InlineKey   | keyPath `"id"`, index `byGroupId` on `"groupId"` | All event envelopes                 |

Types:

- `InitData` — `{ db : Idb.Db, identity : Maybe Identity, groups : List GroupSummary }` (loaded during app init)
- `GroupSummary` — `{ id : Group.Id, name : String, defaultCurrency : Currency }`

Operations:

```elm
open : ConcurrentTask Idb.Error Idb.Db
init : Idb.Db -> ConcurrentTask Idb.Error InitData  -- loads identity + groups in parallel via map2
saveIdentity / loadIdentity
saveGroupSummary / loadAllGroups
saveGroupKey / loadGroupKey
saveEvents / loadGroupEvents  -- events stored with extra "groupId" field for index
errorToString : Idb.Error -> String
```

#### App state lifecycle (`src/Main.elm`)

- New `AppState` union type: `Loading` | `Ready Storage.InitData` | `InitError String`
- `Model.identity` replaced by `Model.appState`
- `init`: kicks off async chain `Storage.open |> andThen Storage.init` → `OnInitComplete`; route guard deferred until init completes
- `OnInitComplete Success`: stores `InitData`, applies route guard
- `OnInitComplete Error`: shows error page
- `OnIdentityGenerated Success`: now also saves identity to IndexedDB via `Storage.saveIdentity` → `OnIdentitySaved` (fire-and-forget)
- `OnNavEvent`: extracts identity from `appState` for route guard

#### New page modules

- **`src/Page/Loading.elm`** — centered "Loading..." text (translated)
- **`src/Page/InitError.elm`** — error title + message

#### Translations

- Added: `loadingApp` ("Loading..." / "Chargement...")

#### Property-based roundtrip tests (`tests/CodecTest.elm`)

- 17 fuzz tests verifying `decode(encode(x)) == x` for every codec pair
- Custom `Fuzzer` for each domain type (Currency, Date, Link, Member.Type, PaymentInfo, Member.Metadata, Category, Payer, Beneficiary, Entry.Metadata, TransferData, ExpenseData, Kind, Entry, GroupMetadataChange, Payload, Envelope)
- Also fixed all test modules to `exposing (suite)` instead of `exposing (..)` to prevent duplicate test runs

---

## Phase 5: Local Group Management ✅

**Goal:** Create groups locally, add basic expense entries, view real computed state. First functional bill-splitter.

**Status: COMPLETE**

### What was done

#### Dependencies

- Installed `dwayne/elm-form`, `dwayne/elm-field`, `dwayne/elm-validation` (published packages for form management)

#### Domain additions

- **`src/Domain/Date.elm`** — Added `posixToDate : Time.Posix -> Date` (converts UTC Posix to calendar date) with internal `monthToInt` helper
- **`src/Domain/GroupState.elm`** — Added `resolveMemberName : GroupState -> Member.Id -> String` (canonical name resolution, falls back to raw ID)

#### Form modules (new, using `dwayne/elm-form`)

**`src/Form/NewGroup.elm`** — Group creation form:

- State: `name : Field String`, `creatorName : Field String`, `currency : Field Currency` (default EUR), `virtualMembers : Forms VirtualMemberForm`
- Validation: all fields non-blank, currency from enum (USD, EUR, GBP, CHF)
- Output: `{ name : String, creatorName : String, currency : Currency, virtualMembers : List String }`
- Virtual member sub-form inline (single `name : Field String` per member)
- Dynamic member list via `Form.List` (add/remove accessors)

**`src/Form/NewEntry.elm`** — Entry creation form:

- State: `description : Field String`, `amount : Field Int` (parsed from decimal string to cents, e.g. "12.50" → 1250)
- Validation: description non-blank, amount > 0
- Output: `{ description : String, amountCents : Int }`

#### Page modules

**`src/Page/Home.elm`** (rewritten):

- Signature: `view : I18n -> (Route -> msg) -> List GroupSummary -> Ui.Element msg`
- Empty state message when no groups
- Group cards (name only, clickable → `GroupRoute id (Tab BalanceTab)`)
- "+ New Group" button navigating to `Route.NewGroup`
- Removed `SampleData` dependency

**`src/Page/NewGroup.elm`** (rewritten):

- Signature: `view : I18n -> Callbacks msg -> Form -> Ui.Element msg`
- `Callbacks msg` type alias with 7 callbacks (name, creator name, currency, virtual member CRUD, submit)
- Renders: title, name field, creator name field, currency radio buttons, virtual members section (dynamic list with add/remove), submit button
- Labels, placeholders, and hints on all fields
- Inline error display (dirty + invalid → "This field is required")

**`src/Page/NewEntry.elm`** (new):

- Signature: `view : I18n -> Callbacks msg -> Form -> Ui.Element msg`
- `Callbacks msg` type alias with 3 callbacks (description, amount, submit)
- Renders: title, description field, amount field, split note ("equally among all members"), submit button
- Labels, placeholders, and hints on all fields

**`src/Page/Group.elm`** (rewritten):

- `Context msg` type alias: `{ i18n, onTabClick, onNewEntry, currentUserRootId }`
- Signature: `view : Context msg -> Ui.Element msg -> GroupState -> GroupTab -> Ui.Element msg`
- `tabContent` routes to tab-specific views (3 args: Context, GroupState, GroupTab)
- Removed `SampleData` dependency

**`src/Page/Group/BalanceTab.elm`** (updated):

- Signature: `view : I18n -> Member.Id -> GroupState -> Ui.Element msg`
- Empty state: shows dedicated "No expenses yet" message when `Dict.isEmpty state.entries`
- Name resolution via `GroupState.resolveMemberName` (no `resolveName` parameter)
- Partial application: `settleTx = UI.Components.settlementRow i18n resolveName`

**`src/Page/Group/EntriesTab.elm`** (updated):

- Signature: `view : I18n -> msg -> GroupState -> Ui.Element msg`
- Added "New Entry" button at the bottom (primary, full-width)
- Name resolution via `GroupState.resolveMemberName` (no `resolveName` parameter)

**`src/Page/Group/MembersTab.elm`** (updated):

- Signature: `view : I18n -> Member.Id -> GroupState -> Ui.Element msg`

**`src/UI/Components.elm`** (updated signatures):

- `entryCard : I18n -> (Member.Id -> String) -> Entry -> Ui.Element msg`
- `settlementRow : I18n -> (Member.Id -> String) -> Settlement.Transaction -> Ui.Element msg`
- `languageSelector : (Language -> msg) -> Language -> Ui.Element msg`
- Argument ordering: stable/config first, data last (enables partial application)

#### Main.elm changes

**Model additions:**

- `randomSeed : Random.Seed` — threaded through UUID generation
- `currentTime : Time.Posix` — used for event timestamps and date derivation
- `newGroupForm : Form.NewGroup.Form`
- `newEntryForm : Form.NewEntry.Form`
- `loadedGroup : Maybe LoadedGroup`
- `LoadedGroup` type: `{ groupId, events, groupState, summary }`

**New Msg variants:**

- Group form: `InputNewGroupName`, `InputNewGroupCreatorName`, `InputNewGroupCurrency`, `InputVirtualMemberName`, `AddVirtualMember`, `RemoveVirtualMember`, `SubmitNewGroup`, `OnGroupCreated`
- Entry form: `InputEntryDescription`, `InputEntryAmount`, `SubmitNewEntry`, `OnEntrySaved`
- Group loading: `OnGroupEventsLoaded`

**Form update handlers:** Use `Form.modify .accessor (Field.setFromString s) form` pattern.

**`submitNewGroup`**: Validates form → generates group ID (v4), creator uses `identity.publicKeyHash` as member ID directly (no UUID), virtual members get v4 UUIDs, event IDs are v7 → builds `GroupMetadataUpdated` + `MemberCreated` events → saves summary + events to IndexedDB → on success: navigates to group, resets form, appends to groups list.

**`submitNewEntry`**: Validates form → generates entry ID (v4), event ID (v7) → builds `Expense` entry (single payer = current user, equal `ShareBeneficiary` for all active members, 1 share each) → saves event → on success: recomputes group state, resets form, navigates to entries tab.

**`ensureGroupLoaded`**: Triggered on `OnNavEvent` for `GroupRoute`. Checks if already loaded for this group, otherwise kicks off `Storage.loadGroupEvents`. On success: `GroupState.applyEvents` + store in `loadedGroup`.

**`viewReady`**: Routes to page views, passes form state and callbacks. Derives `currentUserRootId` from `Dict.get identity.publicKeyHash groupState.members`.

**Removed:** `SampleData.elm` deleted, all `import SampleData` removed.

#### Translations

~30 new keys added (EN + FR) for form labels, placeholders, hints, empty states, and button text across both forms.

#### Key implementation details

**Group creation event sequence** (all share same `clientTimestamp`, monotonic UUID v7 for ordering):

```
Event 1: GroupMetadataUpdated { name = Just name, subtitle = Nothing, ... }
Event 2: MemberCreated { memberId = publicKeyHash, name = creatorName, memberType = Real, addedBy = publicKeyHash }
Event 3+: MemberCreated { memberId = randomUUID, name = vmName, memberType = Virtual, addedBy = publicKeyHash }
```

**Member identity model:** Real members use `identity.publicKeyHash` as their member ID directly (no separate UUID). Virtual members get UUID v4 IDs. This means `Dict.get publicKeyHash state.members` finds the current user without any linear scan or extra field.

**Entry creation:** `Entry.newMetadata` with `rootId = id`, `previousVersionId = Nothing`, `depth = 0`. Date derived from `currentTime` via `Date.posixToDate`. No date picker yet.

**Argument ordering convention:** All view functions follow stable/config args first, frequently-changing data last. This enables partial application and future `Ui.lazy` usage. Example: `BalanceTab.view : I18n -> Member.Id -> GroupState -> Ui.Element msg`.

#### Key decisions made during Phase 5

- **`dwayne/elm-form`** for form management — provides `Form.get`, `Form.modify`, `Form.toState`, `Form.List` for dynamic lists
- **`Callbacks msg` pattern** — page views define a type alias for their callback records, exposed from the module
- **`Context msg` pattern** — `Page.Group` bundles stable callbacks and config into a single record
- **`GroupState.resolveMemberName`** as canonical name resolution — eliminates threading a `resolveName` function through the module hierarchy
- **Public key hash as member ID** — real members identified by their hash directly (no UUID indirection), simplifying current-user lookup
- **`GroupSummary` minimal** — only `{ id, name, defaultCurrency }` (no `creatorMemberId`); current user derived from identity + group state at runtime
- **No group symmetric key generation** — skipped for now (no sync yet), will be needed in the sync phase
- **Expense-only entries** — transfer entry type deferred (form + submission logic)
- **Equal-share split only** — no multi-payer, no exact-amount split yet

### Current file structure

```
src/
  Main.elm                  -- App entry, 4 ports, AppState lifecycle, form state, submit handlers
  Route.elm                 -- Route types + URL parsing/serialization
  Format.elm                -- Currency/amount formatting
  Identity.elm              -- Identity type, crypto generation, JSON codecs
  Storage.elm               -- IndexedDB schema (4 stores), InitData, GroupSummary, CRUD operations
  Translations.elm          -- (generated, gitignored) i18n module
  Domain/
    Currency.elm            -- Currency type + JSON codecs
    Date.elm                -- Date type + JSON codecs + posixToDate
    Group.elm               -- Group/Link types + Link JSON codecs
    Member.elm              -- Member types + JSON codecs (Type, Metadata, PaymentInfo)
    Entry.elm               -- Entry types + full JSON codecs
    Event.elm               -- Event types + JSON codecs (Envelope, 11-variant Payload)
    GroupState.elm           -- Event-sourced state machine + resolveMemberName
    Balance.elm              -- Balance computation
    Settlement.elm           -- Settlement plan computation
    Activity.elm             -- Activity feed types
  Form/
    NewGroup.elm            -- Group creation form (dwayne/elm-form)
    NewEntry.elm            -- Entry creation form (dwayne/elm-form)
  Page/
    Loading.elm             -- "Loading..." centered text
    InitError.elm           -- Error display
    Setup.elm               -- Generate Identity button with loading state
    Home.elm                -- Group list from storage, "+ New Group" button
    About.elm               -- App info
    NotFound.elm            -- 404
    NewGroup.elm            -- Group creation form view (Callbacks msg pattern)
    NewEntry.elm            -- Entry creation form view (Callbacks msg pattern)
    Group.elm               -- Group page shell (Context msg pattern) + tab routing
    Group/
      BalanceTab.elm        -- Balance cards + settlement plan + empty state
      EntriesTab.elm        -- Entry cards + new entry button
      MembersTab.elm        -- Active + departed members
      ActivitiesTab.elm     -- Placeholder "coming soon"
  UI/
    Theme.elm               -- Design tokens
    Shell.elm               -- App shell + group shell + tab bar
    Components.elm          -- Reusable view components + language selector
```

---

## Phase 5.5: Complete Local Group Management

**Goal:** Complete the local bill-splitting experience by adding the remaining features from the specification that don't require server sync. Also clean up `Main.elm` by extracting form logic into page modules.

**Status: NOT STARTED**

### Step 0: Main.elm cleanup

`Main.elm` currently holds all form state, form update handlers, and submission logic for both group creation and entry creation. This should be extracted to keep Main focused on routing, app lifecycle, and orchestration.

**Evaluate and extract into `Page.NewGroup` and `Page.NewEntry`:**

- **Form state ownership**: Move `newGroupForm` and `newEntryForm` out of the top-level Model. Each page module could own its form state via an opaque `Model` type.
- **Form update logic**: The `InputNewGroup*`, `AddVirtualMember`, `RemoveVirtualMember` handlers (and their `InputEntry*` equivalents) are pure `Form.modify` calls that belong in the page module.
- **Submission logic**: `submitNewGroup` and `submitNewEntry` build domain events and IndexedDB tasks. These could live in the page module or a dedicated module, returning `( Model, ConcurrentTask )` for Main to dispatch.
- **Msg consolidation**: Replace the ~10 fine-grained form Msg variants with something like `NewGroupMsg Page.NewGroup.Msg` and `NewEntryMsg Page.NewEntry.Msg`, forwarded in Main via a single branch each.

The goal is that Main's update function has at most 2 branches per form page (one for form updates, one for async responses), rather than the current ~10.

### Step 1: Transfer entries

**Spec ref:** Section 5.1, 5.3

The entry creation form currently only supports expenses. Add transfer entry type.

- **Form**: New `Form.NewTransfer.elm` (or extend `Form.NewEntry.elm` with a type toggle)
  - Fields: amount (required, > 0), from member (required), to member (required, different from "from")
  - Currency: group default currency
  - Date: auto-derived from `currentTime`
- **Page**: Entry creation view with expense/transfer toggle
- **Submission**: Build `Transfer` kind instead of `Expense`, with `from`, `to`, `amount`, `currency`, `date`
- **Route**: Same `/groups/:id/new-entry` route, form state determines which kind

### Step 2: Richer expense form fields

**Spec ref:** Sections 5.2, 5.4, 5.5

Incrementally add fields the domain already supports but the form doesn't expose:

- **Category** (optional): Dropdown with 9 options (food, transport, accommodation, etc.). Maps to `Entry.Category`.
- **Notes** (optional): Free-text textarea.
- **Date**: Date picker instead of auto-derived. Default to today, allow override.
- **Payer selection**: Currently hardcoded to current user. Add a member dropdown (single payer, full amount).
- **Multiple payers**: Toggle to split the paid amount among multiple payers, each with their portion. Sum must equal total.
- **Beneficiary selection**: Currently all active members with equal shares. Allow selecting a subset of members.
- **Exact amount split**: Toggle between shares-based (default) and exact-amount split. For exact split, each beneficiary specifies their amount; sum must equal total.

Suggested sub-steps (each independently useful):

1. Category + notes + date picker
2. Payer selection (single, any member)
3. Beneficiary selection (subset of members, equal shares)
4. Multiple payers
5. Exact amount split

### Step 3: Entry modification and deletion

**Spec ref:** Sections 5.6, 5.7

- **View entry details**: Clicking an entry card opens a detail view (or navigates to a detail route)
- **Edit entry**: Pre-populate the form with existing entry data. On submit, create a new entry version linked via `previousVersionId` and same `rootId`. Emit `EntryAdded` event with the new version.
- **Delete entry**: Soft-delete via `EntryDeleted` event. Entry hidden from lists by default.
- **Restore entry**: Undo soft-delete via `EntryUndeleted` event.
- **Toggle deleted entries**: Show/hide deleted entries in the entries tab.

### Step 4: Member management within a group

**Spec ref:** Sections 4.2, 4.5, 4.6

Currently members are only created at group creation time. Add in-group member management:

- **Add virtual member**: Button in Members tab to add a new virtual member (emit `MemberCreated` event)
- **Rename member**: Edit a member's display name (emit `MemberRenamed` event)
- **Retire member**: Mark a member as departed (emit `MemberRetired` event). Retired members no longer appear in entry forms but historical data preserved.
- **Unretire member**: Reactivate a retired member (emit `MemberUnretired` event)
- **Member metadata**: View/edit contact info and payment methods (emit `MemberMetadataUpdated` event). Payment details displayed as copiable text.

### Step 5: Group metadata editing

**Spec ref:** Sections 3.2, 3.3

- **Edit group metadata**: Edit group name, subtitle, description, links (emit `GroupMetadataUpdated` event). Default currency cannot be changed after creation.
- **Display group info**: Show subtitle, description, and links on the Members tab (as specified in Section 18.4).
- **Remove group locally**: Delete a group from the local device (remove from IndexedDB). Does not affect server or other members. Requires confirmation dialog.

### Step 6: Settlement actions

**Spec ref:** Section 7.3

- **"Mark as Paid" button**: On each settlement row, clicking creates a `Transfer` entry recording the payment.
- **Highlight current user**: Settlement transactions involving the current user are visually highlighted.

### Files modified/created (estimated)

| File                            | Action             | Description                                             |
| ------------------------------- | ------------------ | ------------------------------------------------------- |
| `src/Main.elm`                  | Modified           | Slimmed down: delegates form logic to page modules      |
| `src/Page/NewGroup.elm`         | Modified           | Owns form state + update logic (opaque Model/Msg)       |
| `src/Page/NewEntry.elm`         | Modified           | Owns form state + update logic, expense/transfer toggle |
| `src/Form/NewGroup.elm`         | Unchanged or minor | Already complete for current fields                     |
| `src/Form/NewEntry.elm`         | Modified           | Add category, notes, date, payer/beneficiary selection  |
| `src/Form/NewTransfer.elm`      | New                | Transfer entry form (amount, from, to)                  |
| `src/Page/Group/EntriesTab.elm` | Modified           | Entry click → detail, deleted toggle                    |
| `src/Page/Group/MembersTab.elm` | Modified           | Add/rename/retire member UI, metadata display           |
| `src/Page/Group/BalanceTab.elm` | Modified           | "Mark as Paid" button, current user highlighting        |
| `src/Page/EntryDetail.elm`      | New                | Entry detail view with edit/delete actions              |
| `translations/messages.en.json` | Modified           | ~30-40 new keys                                         |
| `translations/messages.fr.json` | Modified           | ~30-40 new keys                                         |

### Implementation order

Step 0 (Main.elm cleanup) should come first — it makes all subsequent steps easier by establishing the pattern for page-owned form state. Steps 1-6 can then be done in order, each independently shippable.

### Not in scope (deferred to later phases)

These features from the specification require server sync, complex infrastructure, or are independent enough to warrant their own phase:

- **Multi-currency entries** (Spec Section 10): Requires `defaultCurrencyAmount` field + manual exchange rate entry. Complex UX.
- **Invitation & joining flow** (Spec Section 12): Requires group symmetric key generation, server authentication, invite link generation/sharing, join UI with member claiming.
- **Activity feed** (Spec Section 8): Requires `Domain.Activity` to be fully wired. Complex diff computation for entry modifications.
- **Filtering & sorting** (Spec Section 9): Entry filters by person, category, currency, date range. Activity filters. Useful but not core.
- **Settlement preferences** (Spec Section 7.2): Per-member preferred payment recipients. Requires preference storage + UI.
- **Import / Export** (Spec Section 13): JSON export/import with merge analysis.
- **PoW challenge** (Spec Section 3.1): Server-side feature for group creation anti-spam.
- **PWA & service worker** (Spec Section 15): Installation, offline caching, auto-update.

---

## Architecture Decisions

1. **`Browser.element`** with **`elm-url-navigation-port`** for SPA navigation
2. **All ports in `Main.elm`** -- nav ports (`navCmd`/`onNavEvent`) + task ports (`sendTask`/`receiveTask`)
3. **Single `ConcurrentTask.Pool`** in top-level Model, shared by webcrypto/indexeddb
4. **Flat page structure** -- pages expose `view` functions taking relevant data, not nested TEA (Phase 5.5 Step 0 will introduce page-owned state for form pages)
5. **Domain modules unchanged** -- frontend wraps them, doesn't modify them (except adding JSON codecs and helpers like `resolveMemberName`)
6. **JSON codecs colocated** -- each domain module has its own encode/decode functions
7. **GroupState computed on demand** from events via `applyEvents` (caching later if needed)
8. **UUID v7** for event IDs (time-sortable), **UUID v4** for entity IDs (members, entries, groups)
9. **I18n via travelm-agency** (inline mode) -- `I18n` passed explicitly as first param to all view functions, `Translations` aliased as `T`
10. **Member identity via `rootId`** -- views compare `rootId` (not `id`) to handle member replacement chains
11. **Build tooling via elm-watch + pnpm** -- no Makefile, `run-pty` for parallel dev processes
12. **JS bundling via esbuild** -- `public/index.js` uses ES imports, esbuild bundles to `dist/index.js` (iife format)
13. **`AppState` union type** -- `Loading | Ready InitData | InitError String` makes impossible states unrepresentable; `db` only accessible inside `Ready`
14. **Property-based codec tests** -- fuzz roundtrip tests (`decode(encode(x)) == x`) for every domain codec, using `Fuzz` combinators up to `andMap` for 10-field types
15. **Public key hash as member ID** -- real members use `identity.publicKeyHash` directly as their member ID (no UUID indirection); virtual members get UUID v4 IDs
16. **`dwayne/elm-form` for forms** -- `Form.get`, `Form.modify`, `Form.toState`, `Form.List` for dynamic lists; `dwayne/elm-field` for field types with validation; `dwayne/elm-validation` for applicative validation pipelines
17. **`Callbacks msg` pattern** -- page form views define a `type alias Callbacks msg` for their callback records, exposed from the module
18. **`Context msg` pattern** -- `Page.Group` bundles stable callbacks and config into a single `Context msg` record, reducing argument count
19. **Argument ordering convention** -- stable/config args first, frequently-changing data last; enables partial application and future `Ui.lazy` usage
20. **`GroupState.resolveMemberName`** as canonical name resolution -- eliminates threading a `resolveName` function; each tab view derives it locally from the `GroupState` it receives
