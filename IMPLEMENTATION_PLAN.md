# Plan: Frontend Implementation (Phases 1-5)

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

### Current file structure

```
public/
  index.html                -- HTML shell
  index.js                  -- ES imports, Elm init, nav ports, merged ConcurrentTask registration
translations/
  messages.en.json          -- English translations (46 keys)
  messages.fr.json          -- French translations (46 keys)
package.json                -- pnpm scripts + dependencies
elm.json                    -- Elm config with 6 vendor source dirs
.gitmodules                 -- 5 submodules (elm-ui, elm-animator, elm-webcrypto, elm-uuid, elm-indexeddb)
vendor/
  elm-ui/                   -- elm-ui v2
  elm-animator/             -- elm-animator v2
  elm-webcrypto/            -- WebCrypto API via ConcurrentTask
  elm-uuid/                 -- UUID v4/v7 generation
  elm-indexeddb/            -- IndexedDB via ConcurrentTask
src/
  Main.elm                  -- App entry, 4 ports, AppState lifecycle, async init chain
  Route.elm                 -- Route types + URL parsing/serialization
  Format.elm                -- Currency/amount formatting
  Identity.elm              -- Identity type, crypto generation, JSON codecs
  Storage.elm               -- IndexedDB schema (4 stores), InitData, GroupSummary, CRUD operations
  SampleData.elm            -- Hardcoded events for 5 members
  Translations.elm          -- (generated, gitignored) i18n module
  Domain/
    Currency.elm            -- Currency type + JSON codecs
    Date.elm                -- Date type + JSON codecs
    Group.elm               -- Group/Link types + Link JSON codecs
    Member.elm              -- Member types + JSON codecs (Type, Metadata, PaymentInfo)
    Entry.elm               -- Entry types + full JSON codecs (10+ encode/decode pairs)
    Event.elm               -- Event types + JSON codecs (Envelope, 11-variant Payload, GroupMetadataChange)
    GroupState.elm           -- Event-sourced state machine
    Balance.elm              -- Balance computation
    Settlement.elm           -- Settlement plan computation
    Activity.elm             -- Activity feed types
  Page/
    Loading.elm             -- "Loading..." centered text
    InitError.elm           -- Error display
    Setup.elm               -- Generate Identity button with loading state
    Home.elm                -- Group list with sample group
    About.elm               -- App info
    NotFound.elm            -- 404
    NewGroup.elm            -- Placeholder for group creation
    Group.elm               -- Group page shell with tab routing
    Group/
      BalanceTab.elm        -- Balance cards + settlement plan
      EntriesTab.elm        -- Entry cards (expenses + transfers)
      MembersTab.elm        -- Active + departed members
      ActivitiesTab.elm     -- Placeholder "coming soon"
  UI/
    Theme.elm               -- Design tokens
    Shell.elm               -- App shell + group shell + tab bar
    Components.elm          -- Reusable view components + language selector
tests/
  CodecTest.elm             -- 17 fuzz roundtrip tests for all JSON codecs
  GroupStateTest.elm         -- GroupState event processing tests
  EntryResolutionTest.elm    -- Entry version resolution tests
  BalanceTest.elm            -- Balance computation tests
  SettlementTest.elm         -- Settlement plan tests
  TestHelpers.elm            -- Shared test utilities and fuzzers
```

---

## Phase 5: Local Group Management

**Goal:** Create groups locally, add entries, view real computed state. First functional bill-splitter.

**Status: NOT STARTED**

### Prerequisites from Phase 4

- `Storage.elm` provides `saveGroupSummary`, `saveGroupKey`, `saveEvents`, `loadGroupEvents` — all ready to use
- `Storage.InitData` carries `db`, `identity`, `groups` — available via `model.appState` in Main
- All domain JSON codecs are complete (Event, Entry, Member, Currency, Date, Group)
- `UUID.V7State` in Model for event ID generation

### No new dependencies

### Files

**`src/Page/NewGroup.elm`** (rewrite) -- real group creation form:

- Fields: group name (required), creator display name (required), default currency (dropdown)
- Optional: subtitle, description
- "Add virtual member" button + list of virtual member names
- On submit:
  1. Generate group ID (UUID v4), member IDs (UUID v4), group symmetric key (`WebCrypto.Symmetric.generateKey`)
  2. Create events: `GroupMetadataUpdated` + `MemberCreated` for creator + `MemberCreated` for each virtual member
  3. Each event gets a UUID v7 event ID and current timestamp
  4. Save to IndexedDB via `Storage.saveGroupSummary`, `Storage.saveGroupKey`, `Storage.saveEvents`
  5. Navigate to `/groups/:id`

**`src/Page/Home.elm`** (rewrite) -- real group list:

- Read group summaries from `Storage.InitData.groups` (already loaded during init)
- Group card: name, member count, user's net balance
- "+" button navigates to `/groups/new`
- Click group card navigates to `/groups/:id`

**`src/Page/Group.elm`** (rewrite) -- real data:

- On mount: load events via `Storage.loadGroupEvents`, compute `GroupState.applyEvents`
- Build name resolver: `resolveName : Member.Id -> String` from `GroupState.members`
- Pass GroupState to tab sub-pages
- Remove SampleData dependency

**`src/Page/Group/BalanceTab.elm`** (update) -- wire to real GroupState
**`src/Page/Group/EntriesTab.elm`** (update) -- wire to real GroupState
**`src/Page/Group/MembersTab.elm`** (update) -- wire to real GroupState

**`src/Page/Group/NewEntry.elm`** (new) -- basic entry creation:

- Toggle: Expense / Transfer
- Expense: description, amount, single payer (current user), equal shares among all active members
- Transfer: amount, from, to
- Validation: amount > 0, description non-empty
- On submit: create `Entry` + `EntryAdded` event, save to IndexedDB via `Storage.saveEvents`, navigate back to entries tab
- (Advanced form features like multi-payer, exact split deferred to Phase 6)

**FAB** in Group.elm: floating "+" button navigating to `/groups/:id/new-entry`

### Key implementation details

Group creation event sequence (all share the same `clientTimestamp`, monotonic UUID v7 for ordering):

```
Event 1: GroupMetadataUpdated { name, subtitle, description, links }
Event 2: MemberCreated { memberId: creatorId, name: creatorName, memberType: Real, addedBy: creatorId }
Event 3+: MemberCreated { memberId: virtualId, name: virtualName, memberType: Virtual, addedBy: creatorId }
```

Entry creation:

- `Entry.newMetadata` creates metadata with `rootId = id`, `previousVersionId = Nothing`, `depth = 0`
- Wrap in `EntryAdded` payload, then in `Event.Envelope`
- After saving, reload events and recompute GroupState

### Verification

- Create a group with name "Trip to Paris" and 2 virtual members
- See it in the group list on Home
- Open the group: see 3 members (creator + 2 virtual) in Members tab
- Add an expense: "Dinner" for 6000 cents split 3 ways
- Balance tab shows correct balances (creator: +4000, others: -2000 each)
- Settlement tab shows 2 transactions
- Add a transfer from one member to creator
- Balances update correctly
- Reload page: all data persists

---

## Architecture Decisions

1. **`Browser.element`** with **`elm-url-navigation-port`** for SPA navigation
2. **All ports in `Main.elm`** -- nav ports (`navCmd`/`onNavEvent`) + task ports (`sendTask`/`receiveTask`)
3. **Single `ConcurrentTask.Pool`** in top-level Model, shared by webcrypto/indexeddb
4. **Flat page structure** -- pages expose `view` functions taking relevant data, not nested TEA
5. **Domain modules unchanged** -- frontend wraps them, doesn't modify them (except adding JSON codecs)
6. **JSON codecs colocated** -- each domain module has its own encode/decode functions
7. **GroupState computed on demand** from events via `applyEvents` (caching later if needed)
8. **UUID v7** for event IDs (time-sortable), **UUID v4** for entity IDs (members, entries, groups)
9. **I18n via travelm-agency** (inline mode) -- `I18n` passed explicitly as first param to all view functions, `Translations` aliased as `T`
10. **Member identity via `rootId`** -- views compare `rootId` (not `id`) to handle member replacement chains
11. **Build tooling via elm-watch + pnpm** -- no Makefile, `run-pty` for parallel dev processes
12. **JS bundling via esbuild** -- `public/index.js` uses ES imports, esbuild bundles to `dist/index.js` (iife format)
13. **`AppState` union type** -- `Loading | Ready InitData | InitError String` makes impossible states unrepresentable; `db` only accessible inside `Ready`
14. **Property-based codec tests** -- fuzz roundtrip tests (`decode(encode(x)) == x`) for every domain codec, using `Fuzz` combinators up to `andMap` for 10-field types
