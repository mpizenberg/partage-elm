# Partage — Implementation Summary

Local-first bill-splitting app built in Elm. Domain logic is event-sourced; frontend is a SPA with IndexedDB persistence. 102 tests (domain + codec roundtrip).

## Dependencies

**Git submodules** (in `vendor/`):
- `elm-ui` (branch `2.0`), `elm-animator` (branch `v2`), `elm-webcrypto`, `elm-indexeddb`, `elm-uuid` (branch `v7`)

**Elm packages**: `mpizenberg/elm-url-navigation-port`, `elmcraft/core-extra`, `andrewMacmurray/elm-concurrent-task`, `dwayne/elm-form`, `dwayne/elm-field`, `dwayne/elm-validation`

**pnpm**: `@andrewmacmurray/elm-concurrent-task` (runtime), devDeps: `elm-watch`, `run-pty`, `travelm-agency`, `esbuild`, `rimraf`, `shx`

## Build

- `pnpm dev` — elm-watch hot + HTML/JS/i18n watchers via run-pty
- `pnpm build` — i18n gen + esbuild bundle + elm-watch make --optimize
- `pnpm test` — elm-test-rs
- `pnpm i18n` — travelm-agency generates `src/Translations.elm` (gitignored) from `translations/messages.{en,fr}.json`

## Routes

```
[]                                          -> Home
["setup"]                                   -> Setup
["groups", "new"]                           -> NewGroup
["join", id]                                -> GroupRoute id (Join fragment)
["groups", id]                              -> GroupRoute id (Tab BalanceTab)
["groups", id, "entries"]                   -> GroupRoute id (Tab EntriesTab)
["groups", id, "members"]                   -> GroupRoute id (Tab MembersTab)
["groups", id, "activities"]                -> GroupRoute id (Tab ActivitiesTab)
["groups", id, "new-entry"]                 -> GroupRoute id NewEntry
["groups", id, "entries", eid]              -> GroupRoute id (EntryDetail eid)
["groups", id, "entries", eid, "edit"]      -> GroupRoute id (EditEntry eid)
["groups", id, "members", mid]             -> GroupRoute id (MemberDetail mid)
["groups", id, "members", mid, "edit"]     -> GroupRoute id (EditMemberMetadata mid)
["groups", id, "members", "new"]           -> GroupRoute id AddVirtualMember
["groups", id, "settings"]                  -> GroupRoute id EditGroupMetadata
["about"]                                   -> About
_                                           -> NotFound
```

Route guards: no identity → redirect to `/setup`; has identity → redirect away from `/setup`.

## Domain Model

**Event-sourced**: `GroupState.applyEvents : List Envelope -> GroupState -> GroupState` replays events to build state. Events are sorted by UUID v7 (time-sortable). State is recomputed on load and incrementally after each local event.

**GroupState** contains:
- `members : Dict Member.Id Member.ChainState` — keyed by rootId
- `entries : Dict Entry.Id EntryState` — keyed by rootId
- `balances : Dict Member.Id MemberBalance` — recomputed after event application
- `groupMeta : GroupMetadata` — name, subtitle, description, links
- `rejectedEntries` — entries that failed validation during replay

**Member chain model** (`Member.ChainState`): groups all device identities under one rootId (mirrors entry version chains). Each device is a `Member.Info { id, previousId, depth, memberType }`. `Member.pickCurrent` resolves concurrent replacements (deepest wins, ID breaks ties). Real members use `identity.publicKeyHash` as member ID directly; virtual members get UUID v4.

**Entry chain model** (`EntryState`): groups all versions under a rootId. `pickVersion` resolves concurrent edits (deepest wins, ID breaks ties). Entries have `isDeleted` flag toggled by delete/undelete events.

**Event payloads** (11 variants): `MemberCreated`, `MemberRenamed`, `MemberRetired`, `MemberUnretired`, `MemberReplaced`, `MemberMetadataUpdated`, `EntryAdded`, `EntryModified`, `EntryDeleted`, `EntryUndeleted`, `GroupMetadataUpdated`.

**Balance**: `computeBalances : List Entry -> Dict Member.Id MemberBalance`. No resolver needed — entries use rootIds directly.

**Settlement**: greedy algorithm producing `List Transaction { from, to, amount }`.

## Storage (IndexedDB)

Database `"partage"`, version 1:

| Store       | Key         | Purpose                  |
|-------------|-------------|--------------------------|
| `identity`  | ExplicitKey | User identity (single)   |
| `groups`    | InlineKey   | Group summaries          |
| `groupKeys` | ExplicitKey | Symmetric keys per group |
| `events`    | InlineKey   | Event envelopes (indexed by groupId) |

`Storage.InitData`: `{ db, identity : Maybe Identity, groups : Dict Group.Id GroupSummary }`

## App Architecture

**`Browser.element`** with port-based navigation (`elm-url-navigation-port`). 4 ports: `navCmd`, `onNavEvent`, `sendTask`, `receiveTask`.

**`AppState`**: `Loading | Ready InitData | InitError String`. Identity generation via `elm-webcrypto` + `elm-concurrent-task`.

**Page-owned form state**: form pages (`Page.NewGroup`, `Page.NewEntry`, `Page.MemberDetail`, `Page.AddMember`, `Page.EditMemberMetadata`, `Page.EditGroupMetadata`) expose opaque `Model/Msg/init/update/view`. `update` returns `( Model, Maybe Output )`. Main checks for `Just output` to run submission logic.

**`Submit` module**: centralizes event submission — UUID generation, envelope wrapping, IndexedDB persistence. Functions: `newGroup`, `newEntry`, `editEntry`, `addMember`, `deleteEntry`, `restoreEntry`, `event` (generic).

**View structure**: `viewReady` dispatches by route using local helpers:
- `shell title content` — wraps in `UI.Shell.appShell` with language selector
- `withGroup groupId viewFn` — loads group or shows loading state
- `withGroupShell groupId title contentFn` — combines both
- Extracted view functions (`viewGroupTab`, `viewGroupNewEntry`, `viewGroupEditEntry`, `viewGroupEntryDetail`, `viewGroupMemberDetail`) return just content; shell wrapping at dispatch site

**`currentUserRootId` helper**: `Storage.InitData -> LoadedGroup -> Member.Id` — resolves device publicKeyHash to rootId via `GroupState.resolveMemberRootId`.

## Design Tokens (`UI/Theme.elm`)

```elm
fontSize = { sm = 14, md = 16, lg = 18, xl = 22, hero = 28 }
spacing  = { xs = 4, sm = 8, md = 16, lg = 24, xl = 32 }
rounding = { sm = 6, md = 8 }
borderWidth = { sm = 1, md = 2 }
```

Colors: `primary` (#2563eb), `primaryLight`, `success`/`successLight`, `danger`/`dangerLight`, `white`, neutral scale (200–900).

## i18n

`travelm-agency` inline mode. Translation files: `translations/messages.{en,fr}.json`. `I18n` and `Language` types threaded as first parameter to all view functions. Language selector (flag-based) in header.

## File Structure

```
src/
  Main.elm                  -- 4 ports, AppState lifecycle, route dispatch, submit handlers
  Route.elm                 -- Route types + URL parsing/serialization
  Format.elm                -- Currency/amount formatting
  Identity.elm              -- Identity type, crypto generation, JSON codecs
  Storage.elm               -- IndexedDB schema, InitData, GroupSummary, CRUD + deleteGroup
  Submit.elm                -- Event submission: UUID gen + wrap + IndexedDB save
  UuidGen.elm               -- UUID v4/v7 generation helpers
  Translations.elm          -- (generated, gitignored)
  Domain/
    Currency.elm            -- Currency type + codecs
    Date.elm                -- Date type + codecs + posixToDate
    Group.elm               -- Group/Link types + codecs
    Member.elm              -- ChainState, Info, pickCurrent, Type, Metadata, PaymentInfo + codecs
    Entry.elm               -- Entry types + full codecs + replace helper
    Event.elm               -- Envelope, 11-variant Payload + codecs + event builders
    GroupState.elm           -- Event replay engine, query functions (activeMembers, activeEntries, resolveMemberName, resolveMemberRootId)
    Balance.elm              -- Balance computation
    Settlement.elm           -- Settlement plan computation
    Activity.elm             -- Activity feed types (placeholder)
  Form/
    NewGroup.elm            -- Group creation form (dwayne/elm-form)
    NewEntry.elm            -- Entry creation form: amount parsing, date field
    EditMemberMetadata.elm  -- Member metadata form: email validation
    EditGroupMetadata.elm   -- Group metadata form: URL validation, dynamic link list
  Page/
    Loading.elm             -- Loading spinner
    InitError.elm           -- Error display
    Setup.elm               -- Generate Identity button
    Home.elm                -- Group list + new group button
    About.elm               -- App info
    NotFound.elm            -- 404
    NewGroup.elm            -- Group creation: Model/Msg/init/update/view
    NewEntry.elm            -- Entry creation/edit: expense + transfer, kindLocked on edit
    EntryDetail.elm         -- Entry detail: expense/transfer content, edit/delete/restore actions
    MemberDetail.elm        -- Member detail: inline rename, retire/unretire, metadata display
    AddMember.elm           -- Virtual member creation form
    EditMemberMetadata.elm  -- Contact/payment info editing
    EditGroupMetadata.elm   -- Group settings + deletion (two-stage confirm)
    Group.elm               -- Group page: Context msg + tab routing
    Group/
      BalanceTab.elm        -- Balance cards + settlement plan (mark as paid)
      EntriesTab.elm        -- Entry cards, show/hide deleted toggle
      MembersTab.elm        -- Member rows, group info, add member button
      ActivitiesTab.elm     -- Placeholder
  UI/
    Theme.elm               -- Design tokens (colors, spacing, fonts, rounding)
    Shell.elm               -- App shell + group shell + tab bar
    Components.elm          -- balanceCard, entryCard, memberRow, settlementRow, languageSelector
```

## Key Conventions

1. **Argument ordering**: stable/config first, data last (enables partial application, future `Ui.lazy`)
2. **`(Msg -> msg)` + `Ui.map`**: page views take a toMsg function (replaces earlier `Callbacks msg` pattern)
3. **`Context msg` pattern**: `Page.Group` bundles callbacks + config into one record
4. **`( Model, Maybe Output )` returns**: page updates signal submission intent without coupling to ConcurrentTask/ports
5. **`UpdateResult` pattern**: `Page.EditGroupMetadata` returns `{ model, metadataOutput, deleteRequested }` for multiple outputs
6. **Events use actual member IDs**: `triggeredBy`/`createdBy` store `publicKeyHash`; rootId resolution is a view concern
7. **UUID v7 for event IDs** (time-sortable ordering), **UUID v4 for entity IDs** (members, entries, groups)
8. **JSON codecs colocated** in each domain module; property-based roundtrip fuzz tests in `CodecTest.elm`

## Not Yet Implemented

- Multiple payers / exact amount split / unequal shares
- Multi-currency entries (exchange rates)
- Invitation & joining flow (requires server sync + group symmetric key)
- Activity feed
- Filtering & sorting (entries by person/category/date)
- Settlement preferences (per-member preferred payment recipients)
- Import / Export (JSON with merge analysis)
- PoW challenge for group creation
- PWA & service worker
