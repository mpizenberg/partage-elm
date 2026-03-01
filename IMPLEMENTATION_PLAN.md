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

**Status: IN PROGRESS (Steps 0-5 complete)**

### Step 0: Main.elm cleanup ✅

**Status: COMPLETE**

Extracted form state, update logic, and event building out of `Main.elm` into dedicated modules.

#### What was done

**Page-owned form state (commits `125eaea`, `5d440bf`):**

- `Page.NewGroup` now exposes `Model`, `Msg`, `init`, `update`, `view`:
  - `Model` is opaque: `type Model = Model NewGroup.Form Bool` (Bool tracks "submitted" state)
  - `Msg` has 7 variants: `InputName`, `InputCreatorName`, `InputCurrency`, `InputVirtualMemberName`, `AddVirtualMember`, `RemoveVirtualMember`, `Submit`
  - `update : Msg -> Model -> ( Model, Maybe Output )` — returns `Maybe Output` to signal submission to Main
  - `view : I18n -> (Msg -> msg) -> Model -> Ui.Element msg` — uses `Ui.map toMsg` pattern

- `Page.NewEntry` follows the same pattern: `Model`, `Msg`, `init`, `update`, `view`
  - `update : Msg -> Model -> ( Model, Maybe Output )` — `Output` is a tagged union (`ExpenseOutput | TransferOutput`)
  - `init : Config -> Model` — takes `{ currentUserRootId, activeMembers, today }` for contextual defaults

- `Main.elm` simplified:
  - `Model` uses `newGroupModel : Page.NewGroup.Model` and `newEntryModel : Page.NewEntry.Model`
  - ~10 fine-grained Msg variants replaced by `NewGroupMsg Page.NewGroup.Msg` / `NewEntryMsg Page.NewEntry.Msg`
  - Main's update has 2 branches per form page: one for `NewGroupMsg`/`NewEntryMsg` (delegates to page update, checks `Maybe Output`), one for `OnGroupCreated`/`OnEntrySaved` (handles async response)

**Event building extraction:**

- New `UuidGen` module (`src/UuidGen.elm`): `v4`, `v4batch`, `v7`, `v7batch` — extracted UUID generation helpers
- `Domain.Event` extended with:
  - `buildGroupCreationEvents : { creatorId, groupName, creatorName, virtualMembers, eventIds, currentTime } -> List Envelope`
  - `buildExpenseEvent : { entryId, eventId, memberId, currentTime, currency, payerId, beneficiaryIds, description, amountCents, category, notes, date } -> Envelope`
  - `buildTransferEvent : { entryId, eventId, memberId, currentTime, currency, fromMemberId, toMemberId, amountCents, notes, date } -> Envelope`

#### Key decisions

- **`( Model, Maybe Output )` return** instead of `( Model, ConcurrentTask )` — keeps ConcurrentTask/port coupling entirely within Main. Simpler and cleaner.
- **`(Msg -> msg)` + `Ui.map`** replaces the `Callbacks msg` pattern from Phase 5 — fewer arguments, more standard Elm architecture.
- **`initNewEntryIfNeeded`** in Main — re-initializes entry form with contextual data (`currentUserRootId`, `activeMembers`, `today`) whenever navigating to NewEntry route.

### Step 1: Transfer entries ✅

**Status: COMPLETE**

**Spec ref:** Section 5.1, 5.3

#### What was done

Transfer support integrated into `Page.NewEntry` (no separate `Form.NewTransfer.elm`):

- `EntryKind` type: `ExpenseKind | TransferKind` with radio toggle in the view
- `Output` tagged union: `ExpenseOutput { ... } | TransferOutput { amountCents, fromMemberId, toMemberId, notes, date }`
- Transfer form fields: amount, date, from-member dropdown, to-member dropdown, notes
- Validation: `fromMemberId /= toMemberId` check, amount > 0
- Smart defaults: current user as "from", next member as "to"
- `memberDropdown` shared component used for payer (expense), from-member, and to-member selection
- `Event.buildTransferEvent` builds `EntryAdded` event with `Entry.Transfer` kind
- `Main.submitNewEntry` pattern-matches on `ExpenseOutput | TransferOutput`
- Same `/groups/:id/new-entry` route — form state determines entry kind
- Translation keys: `newEntryKindLabel`, `newEntryKindExpense`, `newEntryKindTransfer`, `newEntryFromLabel`, `newEntryToLabel`, `newEntrySameFromTo`

### Step 2: Richer expense form fields ✅ (partial)

**Status: Sub-steps 1-3 COMPLETE, sub-steps 4-5 deferred**

**Spec ref:** Sections 5.2, 5.4, 5.5

#### What was done

**Category** (commit `6c6f1b5`):
- `category : Maybe Entry.Category` in ModelData, `InputCategory` Msg variant
- Radio button list with 10 options: None + 9 categories via `Ui.Input.chooseOne Ui.column`
- Translation keys for all 9 categories in EN + FR

**Notes:**
- `notes : String` in ModelData, `InputNotes` Msg variant
- Text input with placeholder, trimmed to `Maybe String` on submission (empty → `Nothing`)

**Date:**
- `date : Field Date` added to `Form.NewEntry.State` with custom `dateType` field parsing "YYYY-MM-DD"
- `initDate : Date -> Form -> Form` pre-populates with today's date
- Text input (not native date picker — elm-ui v2 limitation)
- Both expense and transfer forms share the date field

**Payer selection (single):**
- `payerId : Member.Id` in ModelData, defaults to `config.currentUserRootId`
- `memberDropdown` component (shared with transfer from/to)
- `buildExpenseEvent` accepts `payerId` from output

**Beneficiary selection (subset, equal shares):**
- `beneficiaryIds : Set Member.Id` in ModelData, defaults to all active member root IDs
- Checkbox per active member via `beneficiaryCheckbox` component
- Validation: at least one beneficiary required
- Still uses `ShareBeneficiary` with 1 share each

#### Not done (deferred)

- **Multiple payers** — single payer only; would require per-payer amount entry with sum validation
- **Exact amount split** — equal `ShareBeneficiary` only; would require per-beneficiary amount entry
- **Unequal shares** — currently only 1 share per person

### Step 3: Entry modification and deletion ✅

**Status: COMPLETE**

**Spec ref:** Sections 5.6, 5.7

#### What was done

**Routes:**
- `EntryDetail Entry.Id` and `EditEntry Entry.Id` variants added to `GroupView` in `Route.elm`
- URLs: `/groups/:id/entries/:entryId` and `/groups/:id/entries/:entryId/edit`
- Full parsing in `fromAppUrl`, serialization in `toPathSegments`/`toPath`

**Entry detail view (`src/Page/EntryDetail.elm`):**
- `view : I18n -> Context msg -> EntryState -> Ui.Element msg`
- `Context msg`: `{ onEdit, onDelete, onRestore, onBack, currentUserRootId, resolveName }`
- Expense view: description, formatted amount + currency, date, payer(s), beneficiaries, category (if set), notes (if set)
- Transfer view: formatted amount + currency, date, from → to, notes (if set)
- Metadata footer using `Ui.none` for conditional "edited" indicator (depth > 0)
- Deleted banner using `Ui.none` when not deleted
- Action buttons: "Edit" (primary) + "Delete" (danger) or "Restore" (success)

**Clickable entry cards:**
- `UI.Components.entryCard` signature: `entryCard : I18n -> (Member.Id -> String) -> msg -> Entry -> Ui.Element msg`
- `Page.Group.EntriesTab` exposes `Msg msg` type alias for view config: `{ onNewEntry, onEntryClick, showDeleted, onToggleDeleted }`
- `Page.Group.Context` extended with `onEntryClick : Entry.Id -> msg` and `onToggleDeleted : msg`
- `showDeleted : Bool` passed separately to `Page.Group.view` (not in `Context`)

**Edit entry (re-uses `Page.NewEntry`):**
- `initFromEntry : Config -> Entry -> Model` pre-populates all form fields from existing entry
- `kindLocked : Bool` in `ModelData` — set to `True` by `initFromEntry`, hides the expense/transfer toggle during edit
- `initEditEntryIfNeeded` in Main — parallel to `initNewEntryIfNeeded`
- `Main.NewEntryMsg` handler checks `model.route`: `EditEntry` routes go to `submitEditEntry`, others to `submitNewEntry`
- `submitEditEntry` looks up original entry, uses `outputToKind` + `Entry.replace` + `Event.buildEntryModifiedEvent`

**Delete and restore:**
- `DeleteEntry Entry.Id` and `RestoreEntry Entry.Id` Msg variants in Main
- `deleteOrRestoreEntry` helper parameterized by event builder function
- `OnEntryActionSaved` handler recomputes group state on success
- `buildEntryDeletedEvent` and `buildEntryUndeletedEvent` in `Domain.Event`

**Show/hide deleted entries:**
- `showDeleted : Bool` in `Main.Model`, toggled by `ToggleShowDeleted` Msg
- `EntriesTab` shows toggle link "Show deleted (N)" / "Hide deleted" when deleted count > 0
- Deleted entries rendered at 50% opacity with "Deleted" badge

**Event `triggeredBy` cleanup:**
- Event builders use `memberId` (the actual identity, `publicKeyHash`) instead of `currentUserRootId`
- Root ID resolution is now exclusively a group state / view concern, not an event concern
- Removed TODO comment in `buildExpenseEvent` about this issue

**20 translation keys added** (EN + FR) for detail view, actions, deleted state.

### Step 4: Member management within a group ✅

**Status: COMPLETE**

**Spec ref:** Sections 4.2, 4.5, 4.6

#### What was done

**Event construction:** No dedicated builder functions — callers construct `Event.Payload` values directly (e.g. `Event.MemberRenamed { memberId, oldName, newName }`) and pass them to `Submit.event` or `Event.wrap`. This was a deliberate simplification from the original plan (see Step 0 refactoring).

**`src/Page/MemberDetail.elm`** — Full page with `Model/Msg/init/update/view` pattern:
- `Model` (opaque): stores `MemberState`, inline rename state (`renaming : Bool`, `renameText : String`)
- `Output`: `RenameOutput { memberId, oldName, newName }` | `RetireOutput Member.Id` | `UnretireOutput Member.Id` | `NavigateToEditMetadata` | `NavigateBack`
- Inline rename: "Rename" button toggles text input with Save/Cancel directly in the detail view
- Display: member name (with "(you)"), type (Real/Virtual), status (Active/Retired), metadata section (phone, email, notes), payment info (IBAN, Wero, Lydia, Revolut, PayPal, Venmo, BTC, ADA)
- Action buttons: Rename (primary), Edit Contact Info (primary), Retire (danger, hidden for self), Reactivate (success, shown when retired)

**`src/Page/AddMember.elm`** — Simple form page:
- `Output`: `{ name : String }`
- Name text input with non-blank validation
- On submit: Main generates member UUID v4 via `Submit.addMember`, emits `MemberCreated` with `memberType = Virtual`

**`src/Page/EditMemberMetadata.elm`** — Metadata editing page with `Model/Msg/init/update/view`:
- `Output`: `{ memberId : Member.Id, metadata : Member.Metadata }`
- Uses `Form.EditMemberMetadata` for validation (email must contain `@domain.ext`)
- Fields: phone, email, notes (contact), IBAN, Wero, Lydia, Revolut, PayPal, Venmo, BTC, ADA (payment)
- All fields optional — empty strings become `Nothing`; payment section is `Just PaymentInfo` only if at least one payment field set

**`src/Form/EditMemberMetadata.elm`** — Form state and validation using `dwayne/elm-form` + `dwayne/elm-field`:
- Custom `emailString` field type with basic email format validation
- Accessor pattern for all 11 fields

**Clickable member rows:**
- `UI.Components.memberRow : I18n -> msg -> { member, isCurrentUser } -> Ui.Element msg` — gains `onClick` parameter
- `MembersTab` uses `Msg msg` type alias: `{ onMemberClick : Member.Id -> msg, onAddMember : msg, onEditGroupMetadata : msg }`
- "Add Member" button at bottom, "Edit Group" button at top

**Routes added to `GroupView`:**
- `MemberDetail Member.Id` — `/groups/:id/members/:memberId`
- `AddVirtualMember` — `/groups/:id/members/new`
- `EditMemberMetadata Member.Id` — `/groups/:id/members/:memberId/edit`

**Main.elm wiring:**
- Msg: `MemberDetailMsg`, `AddMemberMsg`, `EditMemberMetadataMsg`, `OnMemberActionSaved`
- Model: `memberDetailModel`, `addMemberModel`, `editMemberMetadataModel`
- `handleMemberDetailOutput` uses payload constructors directly: `Event.MemberRenamed { ... }`, `Event.MemberRetired { ... }`, etc.
- `submitMemberMetadata` constructs `Event.MemberMetadataUpdated` payload
- `OnMemberActionSaved`: recomputes group state, navigates back to MembersTab

**~30 translation keys** added (EN + FR) for detail view, actions, add member, metadata editing.

### Step 5: Group metadata editing ✅

**Status: COMPLETE**

**Spec ref:** Sections 3.2, 3.3

#### What was done

**Event construction:** Like member events, callers construct `Event.GroupMetadataUpdated change` directly and pass to `Submit.event` / `Event.wrap`.

**`src/Page/EditGroupMetadata.elm`** — Combined settings + deletion page with `Model/Msg/init/update/view`:
- `Output`: `Event.GroupMetadataChange` (partial update — only changed fields set)
- `UpdateResult`: `{ model, metadataOutput : Maybe Output, deleteRequested : Bool }` — signals both metadata save and delete intent
- Fields: name (required), subtitle (optional), description (optional), links (dynamic list of `{ label, url }` pairs)
- `buildChange`: Compares form values against `originalMeta` — `Nothing` = unchanged, `Just Nothing` = cleared, `Just (Just s)` = set
- Delete: two-stage confirmation (`confirmingDelete` toggle + confirm button)

**`src/Form/EditGroupMetadata.elm`** — Form state and validation using `dwayne/elm-form` + `dwayne/elm-field`:
- Custom `urlString` field type: validates URLs start with `http://` or `https://`
- Link label: required non-blank string; link URL: required valid URL
- Dynamic link list via `Form.List` (add/remove)

**Group info displayed in MembersTab:**
- Subtitle, description, and links (if set) shown at top of Members tab
- "Edit Group" button linking to settings page

**Route:** `EditGroupMetadata` in `GroupView` — URL: `/groups/:id/settings`

**Remove group locally:**
- "Remove Group" button (danger) with confirmation UI in EditGroupMetadata page
- `Storage.deleteGroup`: batch deletes group summary, group key, and all events (queried by groupId index)
- On success: removes from `groups` dict in model, navigates to Home

**Main.elm wiring:**
- Msg: `EditGroupMetadataMsg`, `OnGroupMetadataActionSaved`, `RemoveGroup`, `OnGroupRemoved`
- Model: `editGroupMetadataModel`
- `submitGroupMetadata`: constructs `Event.GroupMetadataUpdated change` payload via `submitEvent`
- `syncGroupSummaryName`: updates `GroupSummary` in both model dict and IndexedDB when group name changes
- `deleteGroup`: triggers `Storage.deleteGroup` via ConcurrentTask

**`groups` changed to `Dict Group.Id GroupSummary`** throughout the app (in `Storage.InitData`, Main model, and all usage sites) for natural O(1) lookups.

**~20 translation keys** added (EN + FR) for settings page, group info display, and deletion.

#### Key decisions

- **No separate `Page.GroupSettings.elm`** — `Page.EditGroupMetadata` serves both editing and deletion, accessed via `/groups/:id/settings`
- **`UpdateResult` pattern** instead of standard `( Model, Maybe Output )` — needed to signal both metadata output and delete request from a single update call
- **Link validation**: label is mandatory (non-blank), URL must start with `http://` or `https://` (custom `urlString` field type)

### Step 6: Settlement actions

**Status: NOT STARTED**

**Spec ref:** Section 7.3

#### 6a. "Mark as Paid" on settlement rows

Each settlement row in `BalanceTab` gains a "Mark as Paid" button. Clicking it creates a `Transfer` entry recording the payment, using the existing `Submit.newEntry` pipeline.

**`UI.Components.settlementRow`** — Signature changes to accept a message:
- Current: `settlementRow : I18n -> (Member.Id -> String) -> Settlement.Transaction -> Ui.Element msg`
- New: `settlementRow : I18n -> (Member.Id -> String) -> Maybe (Settlement.Transaction -> msg) -> Settlement.Transaction -> Ui.Element msg`
- When `Just onSettle`: renders a "Mark as Paid" button (primary, small) on the right side of the row
- When `Nothing`: read-only display (no button) — useful if we need to render settlement rows without actions in the future

**`Page.Group.BalanceTab`** — Signature changes to accept a settlement callback:
- Current: `view : I18n -> Member.Id -> GroupState -> Ui.Element msg`
- New: `view : I18n -> Member.Id -> Maybe (Settlement.Transaction -> msg) -> GroupState -> Ui.Element msg`
- Passes `onSettle` through to `UI.Components.settlementRow`

**`Page.Group.Context`** — Add settlement callback:
- Add `onSettleTransaction : Settlement.Transaction -> msg` to `Context msg`

#### 6b. Main.elm wiring

New Msg variant:
- `SettleTransaction Settlement.Transaction`

Handler `SettleTransaction tx`:
1. Build a `Page.NewEntry.TransferOutput` from the `Settlement.Transaction`:
   - `amountCents = tx.amount`
   - `fromMemberId = tx.from`
   - `toMemberId = tx.to`
   - `notes = Nothing`
   - `date = Date.posixToDate model.currentTime` (today's date)
2. Call `submitNewEntry` with the constructed output (reuses the existing transfer submission pipeline)
3. On success (`OnEntrySaved`): recomputes group state, stays on Balance tab (not Entries tab as for normal entries)

Note: The settlement action bypasses the `Page.NewEntry` form entirely — it goes straight to submission since all data is already known from the settlement computation. No user input needed.

**Navigation after save:** When `SettleTransaction` triggers `OnEntrySaved`, the handler should stay on the Balance tab instead of navigating to Entries tab. This can be handled by checking the current route: if already on `Tab BalanceTab`, remain there.

#### 6c. Highlight current user in settlement rows

Settlement rows involving the current user are visually emphasized:

**`UI.Components.settlementRow`** — Add `currentUserRootId : Member.Id` parameter:
- New: `settlementRow : I18n -> (Member.Id -> String) -> Member.Id -> Maybe (Settlement.Transaction -> msg) -> Settlement.Transaction -> Ui.Element msg`
- When `tx.from == currentUserRootId` or `tx.to == currentUserRootId`: use `Theme.primaryLight` background (or a subtle highlight color) instead of `Theme.neutral200`
- The "you" suffix is already handled by `resolveName` in the caller — no special name formatting needed here

**`Page.Group.BalanceTab`** — Thread `currentUserRootId` through to `settlementRow`.

#### Files modified

| File | Action | Description |
| --- | --- | --- |
| `src/UI/Components.elm` | Modified | `settlementRow` gains `onSettle` callback + `currentUserRootId` + highlight |
| `src/Page/Group/BalanceTab.elm` | Modified | Pass settle callback and currentUserRootId to settlementRow |
| `src/Page/Group.elm` | Modified | Add `onSettleTransaction` to `Context` |
| `src/Main.elm` | Modified | `SettleTransaction` Msg + handler |
| `translations/messages.en.json` | Modified | ~2 new keys |
| `translations/messages.fr.json` | Modified | ~2 new keys |

#### Translation keys needed

- `settlementMarkAsPaid`: "Mark as Paid" / "Marquer comme payé"
- `settlementPaid`: "Paid!" / "Payé !" (optional, for toast/feedback after marking)

### Not in scope (deferred to later phases)

These features from the specification require server sync, complex infrastructure, or are independent enough to warrant their own phase:

- **Multiple payers** (Spec Section 5.4): Toggle to split paid amount among multiple payers with per-payer amounts. Sum must equal total.
- **Exact amount split** (Spec Section 5.5): Toggle between shares-based and exact-amount beneficiary split. Per-beneficiary amounts, sum must equal total.
- **Multi-currency entries** (Spec Section 10): Requires `defaultCurrencyAmount` field + manual exchange rate entry. Complex UX.
- **Invitation & joining flow** (Spec Section 12): Requires group symmetric key generation, server authentication, invite link generation/sharing, join UI with member claiming.
- **Activity feed** (Spec Section 8): Requires `Domain.Activity` to be fully wired. Complex diff computation for entry modifications.
- **Filtering & sorting** (Spec Section 9): Entry filters by person, category, currency, date range. Activity filters. Useful but not core.
- **Settlement preferences** (Spec Section 7.2): Per-member preferred payment recipients. Requires preference storage + UI.
- **Import / Export** (Spec Section 13): JSON export/import with merge analysis.
- **PoW challenge** (Spec Section 3.1): Server-side feature for group creation anti-spam.
- **PWA & service worker** (Spec Section 15): Installation, offline caching, auto-update.

### Current file structure (after Steps 0-5)

```
src/
  Main.elm                  -- App entry, 4 ports, AppState lifecycle, delegates to page modules
  Route.elm                 -- Route types + URL parsing (Entry, Member, GroupMetadata routes)
  Format.elm                -- Currency/amount formatting
  Identity.elm              -- Identity type, crypto generation, JSON codecs
  Storage.elm               -- IndexedDB schema (4 stores), InitData (Dict groups), CRUD + deleteGroup
  Submit.elm                -- Event submission: attempt, newGroup, newEntry, editEntry, delete/restore, addMember, event
  UuidGen.elm               -- UUID v4/v7 generation helpers (extracted from Main)
  Translations.elm          -- (generated, gitignored) i18n module
  Domain/
    Currency.elm            -- Currency type + JSON codecs
    Date.elm                -- Date type + JSON codecs + posixToDate + toString
    Group.elm               -- Group/Link types + Link JSON codecs
    Member.elm              -- Member types + JSON codecs (Type, Metadata, PaymentInfo)
    Entry.elm               -- Entry types + full JSON codecs + replace helper
    Event.elm               -- Event types + JSON codecs + wrap + createGroup
    GroupState.elm           -- Event-sourced state machine + resolveMemberName
    Balance.elm              -- Balance computation
    Settlement.elm           -- Settlement plan computation
    Activity.elm             -- Activity feed types
  Form/
    NewGroup.elm            -- Group creation form (dwayne/elm-form)
    NewEntry.elm            -- Entry creation form: description, amount, date (dwayne/elm-form)
    EditMemberMetadata.elm  -- Member metadata form: contact info + payment methods
    EditGroupMetadata.elm   -- Group metadata form: name, subtitle, description, links
  Page/
    Loading.elm             -- "Loading..." centered text
    InitError.elm           -- Error display
    Setup.elm               -- Generate Identity button with loading state
    Home.elm                -- Group list from storage, "+ New Group" button
    About.elm               -- App info
    NotFound.elm            -- 404
    NewGroup.elm            -- Group creation: Model/Msg/init/update/view (opaque Model)
    NewEntry.elm            -- Entry creation/edit: Model/Msg/init/initFromEntry/update/view, kindLocked
    EntryDetail.elm         -- Entry detail view: Context msg, expense/transfer content, actions
    MemberDetail.elm        -- Member detail: inline rename, retire/unretire, metadata display
    AddMember.elm           -- Simple virtual member creation form
    EditMemberMetadata.elm  -- Member contact/payment info editing
    EditGroupMetadata.elm   -- Group metadata editing + group deletion
    Group.elm               -- Group page shell (Context msg pattern) + tab routing
    Group/
      BalanceTab.elm        -- Balance cards + settlement plan + empty state
      EntriesTab.elm        -- Clickable entry cards, show/hide deleted toggle, Msg msg type alias
      MembersTab.elm        -- Clickable member rows, group info display, add member + edit group buttons
      ActivitiesTab.elm     -- Placeholder "coming soon"
  UI/
    Theme.elm               -- Design tokens
    Shell.elm               -- App shell + group shell + tab bar
    Components.elm          -- Reusable view components + language selector
```

---

## Architecture Decisions

1. **`Browser.element`** with **`elm-url-navigation-port`** for SPA navigation
2. **All ports in `Main.elm`** -- nav ports (`navCmd`/`onNavEvent`) + task ports (`sendTask`/`receiveTask`)
3. **Single `ConcurrentTask.Pool`** in top-level Model, shared by webcrypto/indexeddb
4. **Page-owned form state** -- form pages (`Page.NewGroup`, `Page.NewEntry`) expose opaque `Model/Msg/init/update/view`; `update` returns `( Model, Maybe Output )`; Main checks for `Just output` to run submission/async logic
5. **Domain modules unchanged** -- frontend wraps them, doesn't modify them (except adding JSON codecs, helpers like `resolveMemberName`, `Event.wrap`, and `Event.createGroup`)
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
17. **`(Msg -> msg)` + `Ui.map`** -- page form views take a `toMsg` mapping function; replaces the earlier `Callbacks msg` pattern
18. **`Context msg` pattern** -- `Page.Group` bundles stable callbacks and config into a single `Context msg` record, reducing argument count
19. **Argument ordering convention** -- stable/config args first, frequently-changing data last; enables partial application and future `Ui.lazy` usage
20. **`GroupState.resolveMemberName`** as canonical name resolution -- eliminates threading a `resolveName` function; each tab view derives it locally from the `GroupState` it receives
21. **`UuidGen` module** -- extracted UUID generation helpers (`v4`, `v4batch`, `v7`, `v7batch`); keeps Main and event builders focused on logic
22. **`Event.wrap` + direct payload construction** -- callers construct `Event.Payload` values directly (e.g. `Event.MemberRenamed { ... }`) and use `Event.wrap` to create envelopes; `Event.createGroup` is the only multi-payload helper; `Submit.elm` handles UUID generation + IndexedDB persistence
23. **`Submit` module** -- centralizes event submission logic: `attempt` (save to IndexedDB), `simpleEvent` (generate eventId + wrap + attempt), `newGroup`, `newEntry`, `editEntry`, `addMember`, `deleteEntry`, `restoreEntry`, `event` (generic)
24. **Events use actual member IDs** -- `triggeredBy` and `createdBy` store the identity's `publicKeyHash` (the actual member ID), not a root ID; root ID resolution is a group state concern handled in views and form initialization
25. **`kindLocked` prevents entry type change** -- when editing an entry via `initFromEntry`, `kindLocked = True` hides the expense/transfer toggle; new entries have `kindLocked = False`
26. **`showDeleted` outside `Context`** -- ephemeral UI state like `showDeleted : Bool` is passed separately to `Page.Group.view`, not bundled into the `Context msg` record which holds stable callbacks
27. **`Dict Group.Id GroupSummary`** for groups storage -- O(1) lookup/insert/remove instead of list scanning; used in `Storage.InitData` and `Main.Model`
28. **`UpdateResult` pattern** -- `Page.EditGroupMetadata.update` returns `{ model, metadataOutput, deleteRequested }` when a page needs to signal multiple independent outputs from a single update
29. **Custom field types** -- `urlString` (validates http(s):// prefix) and `emailString` (validates @domain.ext format) via `Field.customType` in form modules
