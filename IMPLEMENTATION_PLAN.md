# Plan: Frontend Implementation (Phases 1-5)

## Context

Domain logic is complete (GroupState, Balance, Settlement) with 158 passing tests. `Main.elm` is a placeholder. We need to build the frontend following FEASIBILITY.md (minus elm-safe-virtual-dom), getting to a functional local bill-splitter by Phase 5.

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

**pnpm** (from Phase 3): `elm-concurrent-task` JS runner, `elm-url-navigation-port` JS module

---

## Phase 1: Build Tooling + Navigation

**Goal:** SPA routing with port-based navigation, stub pages with elm/html.

### New dependencies
```sh
elm install mpizenberg/elm-url-navigation-port
```
(This pulls in `lydell/elm-app-url` and `elm/url` transitively.)

### Files

**`index.html`** (new) -- HTML shell:
- `<div id="app"></div>`
- Load `elm.js`
- Init with flags: `{ initialUrl: location.href, currentTime: Date.now(), languages: navigator.languages }`
- Wire navigation ports via the `elm-url-navigation-port` JS module:
  ```js
  import * as Navigation from "elm-url-navigation-port";
  Navigation.init({ navCmd: app.ports.navCmd, onNavEvent: app.ports.onNavEvent });
  ```

**`Makefile`** (new):
- `build`: `elm make src/Main.elm --output=elm.js`
- `test`: `pnpx elm-test`

**`src/Main.elm`** (rewrite) -- `port module`, `Browser.element`:
```elm
port module Main exposing (main)

-- Navigation ports (elm-url-navigation-port)
port navCmd : Nav.CommandPort msg
port onNavEvent : Nav.EventPort msg

type alias Model =
    { route : Route, navKey : Nav.Key, identity : Maybe String }

type Msg
    = OnNavEvent Nav.Event
    | NavigateTo Route
```
- `init`: parse `flags.initialUrl` via `Nav.init` to get `Nav.Key` + initial `Nav.Event`, derive Route
- `update`: `OnNavEvent` extracts `AppUrl` from event, converts to Route; `NavigateTo` uses `Nav.pushUrl`
- `view`: dispatch to page module based on `model.route`
- `subscriptions`: `Nav.onNavEvent onNavEvent OnNavEvent`
- Route guard: if no identity and route requires auth, redirect to `/setup`
- Dev workaround: hardcode `identity = Just "dev"` to bypass guards during Phase 1

**`src/Route.elm`** (extend) -- add URL parsing/serialization:
- `fromAppUrl : AppUrl -> Route` -- pattern-matches on `appUrl.path`
- `toPath : Route -> String` -- serializes each route variant to a URL string
- Route table:
  ```
  []                         -> Home
  ["setup"]                  -> Setup
  ["groups", "new"]          -> NewGroup
  ["join", id]               -> GroupRoute id (Join (fragment or ""))
  ["groups", id]             -> GroupRoute id (Tab BalanceTab)
  ["groups", id, "entries"]  -> GroupRoute id (Tab EntriesTab)
  ["groups", id, "members"]  -> GroupRoute id (Tab MembersTab)
  ["groups", id, "activities"] -> GroupRoute id (Tab ActivitiesTab)
  ["groups", id, "new-entry"] -> GroupRoute id NewEntry
  ["about"]                  -> About
  _                          -> NotFound
  ```

**Stub page modules** (new, each exposes `view`):
- `src/Page/Setup.elm` -- "Welcome to Partage"
- `src/Page/Home.elm` -- "Your groups"
- `src/Page/About.elm` -- "About Partage"
- `src/Page/NotFound.elm` -- "Page not found"
- `src/Page/NewGroup.elm` -- "Create a group"
- `src/Page/Group.elm` -- shows current tab name, links to switch tabs

### Verification
- `make build` succeeds, `make test` passes 158 tests
- Open `index.html`: navigate via URL bar to `/`, `/setup`, `/about`, `/groups/test-id`, `/groups/test-id/entries`
- Back button works via `Nav.back`
- Internal links navigate without page reload

---

## Phase 2: Static UI with elm-ui v2

**Goal:** Visually complete prototype rendering hardcoded domain data.

### New dependencies

Submodules:
```sh
git submodule add -b 2.0 https://github.com/mdgriffith/elm-ui vendor/elm-ui
git submodule add -b v2 https://github.com/mdgriffith/elm-animator vendor/elm-animator
```

Published:
```sh
elm install elmcraft/core-extra
elm install avh4/elm-color
elm install mdgriffith/elm-bezier
```

Update elm.json `source-directories`: `["src", "vendor/elm-ui/src", "vendor/elm-animator/src"]`

### Files

**`src/UI/Theme.elm`** (new) -- design tokens:
- Colors: `primary` (#2563eb), `success` (green), `danger` (red), `neutral` (grays)
- `balanceColor : Balance.Status -> Ui.Color`
- Spacing constants, font sizes, max content width (768px)

**`src/UI/Layout.elm`** (new) -- app shell:
- `appShell : { title : String, content : Ui.Element msg } -> Ui.Element msg` -- header + content + max-width
- `groupShell : { groupName : String, activeTab : GroupTab, content : Ui.Element msg, onTabClick : GroupTab -> msg } -> Ui.Element msg` -- adds bottom tab bar

**`src/UI/Components.elm`** (new) -- reusable view components:
- `balanceCard : { name : String, balance : MemberBalance, isCurrentUser : Bool } -> Ui.Element msg`
- `entryCard : { entry : Entry, resolveName : Member.Id -> String } -> Ui.Element msg`
- `memberRow : { member : MemberState, isCurrentUser : Bool } -> Ui.Element msg`
- `settlementRow : { transaction : Transaction, resolveName : Member.Id -> String } -> Ui.Element msg`
- `tabBar : { active : GroupTab, onSelect : GroupTab -> msg } -> Ui.Element msg`

**`src/Format.elm`** (new):
- `formatCents : Int -> String` -- e.g., 1050 -> "10.50"
- `formatCentsWithCurrency : Int -> Currency -> String` -- e.g., "10.50 EUR"

**`src/SampleData.elm`** (new) -- hardcoded events for 4 members (Alice, Bob, Carol, Dave) with several expenses and a transfer, producing realistic balances via `GroupState.applyEvents`

**Page modules** (rewrite to use elm-ui):
- **`src/Page/Group.elm`** -- tab-switching shell using `UI.Layout.groupShell`
- **`src/Page/Group/BalanceTab.elm`** (new) -- balance cards from `GroupState.balances` + settlement from `Settlement.computeSettlement`
- **`src/Page/Group/EntriesTab.elm`** (new) -- entry cards from `GroupState.activeEntries`
- **`src/Page/Group/MembersTab.elm`** (new) -- active members sorted alphabetically, retired in separate section
- **`src/Page/Group/ActivitiesTab.elm`** (new) -- placeholder "Coming soon"
- **`src/Page/Home.elm`** -- group list card showing sample group
- **`src/Page/Setup.elm`** -- welcome screen with "Generate Identity" button (non-functional yet)

All page modules use `Ui.Element msg`. `Main.elm` view uses `Ui.layout` as the top-level renderer.

### Verification
- App renders balance cards with green/red/neutral color coding
- Tab switching shows different content on each tab
- Entry list shows expense and transfer cards with formatted amounts
- Member list shows active members; sample data produces non-zero balances
- Layout respects 768px max width

---

## Phase 3: Async Backbone + Identity

**Goal:** Real cryptographic identity generation via elm-concurrent-task + elm-webcrypto.

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
pnpm init
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
    , navKey : Nav.Key
    , identity : Maybe Identity
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

**`index.html`** (update) -- add elm-concurrent-task JS runner:
- Import runner from `node_modules/elm-concurrent-task`
- Register elm-webcrypto task definitions
- Wire `sendTask`/`receiveTask` ports
- Add `randomSeed` to flags: `Array.from(crypto.getRandomValues(new Uint32Array(4)))`

**`package.json`** (new via `pnpm init`) -- JS dependencies

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
- `make test` still passes 158 tests

---

## Phase 4: Persistent Storage (IndexedDB)

**Goal:** Identity and group data survive page reloads.

### New dependencies

Submodule:
```sh
git submodule add https://github.com/mpizenberg/elm-indexeddb vendor/elm-indexeddb
```

Update elm.json `source-directories` to add `vendor/elm-indexeddb/src`.
Update `index.html` JS runner to register elm-indexeddb task definitions.

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
- `make test` still passes 158 tests
- Open browser DevTools > Application > IndexedDB: see "partage" database with stores

---

## Phase 5: Local Group Management

**Goal:** Create groups locally, add entries, view real computed state. First functional bill-splitter.

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

## Target File Structure (after Phase 5)

```
index.html
Makefile
package.json
elm.json
.gitmodules
vendor/  elm-ui/ elm-animator/ elm-webcrypto/ elm-indexeddb/ elm-uuid/
src/
  Main.elm          -- App entry, ports, Model, Msg, update, subscriptions
  Route.elm         -- Route types + URL parsing/serialization
  Identity.elm      -- Keypair type, generation task, JSON codecs
  Storage.elm       -- IndexedDB schema and CRUD operations
  Format.elm        -- Currency/amount formatting
  Domain/           -- (existing + JSON codecs added to each module)
  Page/
    Setup.elm       -- Identity generation screen
    Home.elm        -- Group list
    About.elm       -- App info
    NotFound.elm    -- 404
    NewGroup.elm    -- Group creation form
    Group.elm       -- Group page shell with tab routing + FAB
    Group/
      BalanceTab.elm
      EntriesTab.elm
      MembersTab.elm
      ActivitiesTab.elm
      NewEntry.elm
  UI/
    Theme.elm       -- Colors, spacing, typography
    Layout.elm      -- App shell, group shell
    Components.elm  -- Reusable view components
```
