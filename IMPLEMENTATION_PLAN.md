# Plan: Frontend Implementation (Phases 1-5)

## Context

Domain logic is complete (GroupState, Balance, Settlement) with 158 passing tests. We are building the frontend following FEASIBILITY.md (minus elm-safe-virtual-dom), getting to a functional local bill-splitter by Phase 5.

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

**pnpm** (from Phase 2): `elm-url-navigation-port` JS module, `elm-watch` for dev/build, `travelm-agency` for i18n

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

### Current file structure
```
public/
  index.html              -- HTML shell
  index.js                -- Elm init + navigation port wiring + language flag
translations/
  messages.en.json        -- English translations (44 keys)
  messages.fr.json        -- French translations (44 keys)
package.json              -- pnpm scripts + devDependencies
elm.json                  -- Elm config with vendor source dirs
.gitignore                -- includes src/Translations.elm
src/
  Main.elm                -- App entry, ports, Model, Msg, update, view, i18n
  Route.elm               -- Route types + URL parsing/serialization
  Format.elm              -- Currency/amount formatting
  SampleData.elm          -- Hardcoded events for 5 members
  Translations.elm        -- (generated, gitignored) i18n module
  Domain/                 -- (unchanged domain logic)
  Page/
    Setup.elm             -- Welcome screen (non-functional identity button)
    Home.elm              -- Group list with sample group
    About.elm             -- App info
    NotFound.elm          -- 404
    NewGroup.elm          -- Placeholder for group creation
    Group.elm             -- Group page shell with tab routing
    Group/
      BalanceTab.elm      -- Balance cards + settlement plan
      EntriesTab.elm      -- Entry cards (expenses + transfers)
      MembersTab.elm      -- Active + departed members
      ActivitiesTab.elm   -- Placeholder "coming soon"
  UI/
    Theme.elm             -- Design tokens (colors, spacing, typography, rounding, borders)
    Shell.elm             -- App shell + group shell + tab bar
    Components.elm        -- Reusable view components + language selector
```

---

## Phase 3: Async Backbone + Identity

**Goal:** Real cryptographic identity generation via elm-concurrent-task + elm-webcrypto.

**Status: NOT STARTED**

### New dependencies

Submodules:
```sh
git submodule add https://github.com/mpizenberg/elm-webcrypto vendor/elm-webcrypto
git submodule add -b v7 https://github.com/mpizenberg/elm-uuid vendor/elm-uuid
```

Published:
```sh
elm install andrewMacmurray/elm-concurrent-task
elm install TSFoster/elm-bytes-extra
elm install TSFoster/elm-md5
elm install TSFoster/elm-sha1
```

pnpm:
```sh
pnpm add elm-concurrent-task
```

Update elm.json `source-directories` to add `vendor/elm-webcrypto/src` and `vendor/elm-uuid/src`.

### Files

**`src/Main.elm`** (update) -- add task ports and pool:
```elm
-- New ports (added alongside existing nav ports)
port sendTask : Json.Encode.Value -> Cmd msg
port receiveTask : (Json.Decode.Value -> msg) -> Sub msg

type alias Model =
    { route : Route
    , identity : Maybe Identity
    , i18n : I18n
    , language : Language
    , pool : ConcurrentTask.Pool Msg
    , currentTime : Time.Posix
    , randomSeed : Random.Seed
    , uuidState : UUID.V7State
    }
```
- `init`: receive `flags.randomSeed` (list of ints from `crypto.getRandomValues`), seed `Random.Seed`, initialize `UUID.V7State`
- `subscriptions`: add `ConcurrentTask.onProgress` via `receiveTask`
- `update`: handle `OnTaskProgress` and `OnTaskComplete` messages

**`src/Identity.elm`** (new):
```elm
type alias Identity =
    { publicKeyHash : String
    , signingKeyPair : WebCrypto.Signature.SerializedSigningKeyPair
    }

generate : ConcurrentTask WebCrypto.Error Identity
-- generateSigningKeyPair |> andThen (export + sha256 publicKey)

-- JSON codecs (colocated with the type)
encode : Identity -> Json.Encode.Value
decoder : Json.Decode.Decoder Identity
```

**`src/Page/Setup.elm`** (update) -- functional:
- "Generate Identity" button triggers `Identity.generate` task
- Shows spinner during generation
- On success: store identity in Model, navigate to `/`

**`public/index.js`** (update) -- add elm-concurrent-task JS runner:
- Import runner from `node_modules/elm-concurrent-task`
- Register elm-webcrypto task definitions
- Wire `sendTask`/`receiveTask` ports
- Add `randomSeed` to flags: `Array.from(crypto.getRandomValues(new Uint32Array(4)))`

### Key patterns

UUID generation (pure, no task needed):
```elm
nextUUID : Time.Posix -> Model -> ( String, Model )
nextUUID time model =
    let ( uuid, newState ) = UUID.stepV7 time model.uuidState
    in ( UUID.toString uuid, { model | uuidState = newState } )
```

Route guards now work for real: `identity == Nothing` redirects to `/setup`.

### Verification
- Visit `/setup`, click "Generate Identity"
- Spinner shows, then identity is created and stored in Model
- Redirected to `/` (Home)
- Navigating to any auth route works; navigating to `/setup` when identity exists redirects to `/`
- `pnpm test` still passes 158 tests

---

## Phase 4: Persistent Storage (IndexedDB)

**Goal:** Identity and group data survive page reloads.

**Status: NOT STARTED**

### New dependencies

Submodule:
```sh
git submodule add https://github.com/mpizenberg/elm-indexeddb vendor/elm-indexeddb
```

Update elm.json `source-directories` to add `vendor/elm-indexeddb/src`.
Update `public/index.js` JS runner to register elm-indexeddb task definitions.

### Files

**`src/Storage.elm`** (new) -- IndexedDB schema + operations:

Schema (version 1):
```elm
dbSchema : IndexedDB.Schema
-- Stores:
--   "identity"   (ExplicitKey) -- single record at StringKey "default"
--   "groupKeys"  (ExplicitKey) -- keyed by StringKey groupId
--   "groups"     (InlineKey, keyPath "id") -- group metadata records
--   "events"     (InlineKey, keyPath "id") -- all events
--                  index "byGroupId" on "groupId"
```

Operations (all return `ConcurrentTask Storage.Error a`):
```elm
open : ConcurrentTask Error Db
saveIdentity : Db -> Identity -> ConcurrentTask Error ()
loadIdentity : Db -> ConcurrentTask Error (Maybe Identity)
saveGroupMeta : Db -> { id : String, name : String, defaultCurrency : Currency } -> ConcurrentTask Error ()
loadAllGroups : Db -> ConcurrentTask Error (List GroupSummary)
saveGroupKey : Db -> Group.Id -> String -> ConcurrentTask Error ()
loadGroupKey : Db -> Group.Id -> ConcurrentTask Error (Maybe String)
saveEvents : Db -> List Json.Encode.Value -> ConcurrentTask Error ()
loadGroupEvents : Db -> Group.Id -> ConcurrentTask Error (List Json.Decode.Value)
```

**JSON codecs colocated in domain modules** (add encode/decode to each):
- **`src/Domain/Event.elm`** -- `encodeEnvelope`, `envelopeDecoder`, `encodePayload`, `payloadDecoder` (11 payload variants)
- **`src/Domain/Entry.elm`** -- `encodeEntry`, `entryDecoder`, `encodeMetadata`, `metadataDecoder`, `encodeExpenseData`, `encodeTransferData`, etc.
- **`src/Domain/Member.elm`** -- `encodeMemberType`, `memberTypeDecoder`, `encodeMetadata`, `metadataDecoder`, `encodePaymentInfo`, `paymentInfoDecoder`
- **`src/Domain/Currency.elm`** -- `encodeCurrency`, `currencyDecoder`
- **`src/Domain/Date.elm`** -- `encodeDate`, `dateDecoder`
- **`src/Domain/Group.elm`** -- `encodeLink`, `linkDecoder`
- **`src/Identity.elm`** -- already has `encode`/`decoder` from Phase 3

**`src/Main.elm`** (update):
- `Model` gains `db : Maybe IndexedDB.Db` and `groups : List GroupSummary`
- `init` chain: open DB -> load identity -> load group list -> set route
- Show loading spinner during init
- `Page.Setup` saves identity to IndexedDB after generating it

### Verification
- Generate identity on `/setup`, reload page -> stays logged in (goes to `/` not `/setup`)
- `pnpm test` still passes 158 tests
- Open browser DevTools > Application > IndexedDB: see "partage" database with stores

---

## Phase 5: Local Group Management

**Goal:** Create groups locally, add entries, view real computed state. First functional bill-splitter.

**Status: NOT STARTED**

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
  4. Save to IndexedDB: group metadata, group key, events
  5. Navigate to `/groups/:id`

**`src/Page/Home.elm`** (rewrite) -- real group list:
- On mount: load group summaries from IndexedDB (already in Model from init)
- Group card: name, member count, user's net balance
- "+" button navigates to `/groups/new`
- Click group card navigates to `/groups/:id`

**`src/Page/Group.elm`** (rewrite) -- real data:
- On mount: load events from IndexedDB for this group ID, compute `GroupState.applyEvents`
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
- On submit: create `Entry` + `EntryAdded` event, save to IndexedDB, navigate back to entries tab
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
