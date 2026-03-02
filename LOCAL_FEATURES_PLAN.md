# Local Features Plan

Two remaining local-only features: settlement preferences and group import/export.

## Feature 1: Settlement Preferences

### Current State

The settlement algorithm (`Domain.Settlement`) already supports a two-pass approach with preferences. `computeSettlement` takes `Dict Member.Id MemberBalance -> List Preference -> List Transaction`. The `Preference` type (`{ memberRootId, preferredRecipients }`) and the preference-aware pass are fully implemented. But `BalanceTab` always passes `[]` as preferences.

Preferences must be shared across all devices so every participant sees the same settlement plan. They are event-sourced like all other group data.

### Design

**New event payload**: Add a 12th `Payload` variant:
```elm
| SettlementPreferencesUpdated { memberRootId : Member.Id, preferredRecipients : List Member.Id }
```

One event per member whose preferences change. This replaces (not patches) the member's preference list.

**State**: Add `settlementPreferences : List Settlement.Preference` to `GroupState`. Built during event replay by `applySettlementPreferencesUpdated`. Passed to `computeSettlement` instead of `[]`.

**UI**: Add a preferences editor on the Balance tab, below the settlement plan. Any member can set preferred creditors. The editor shows a reorderable list of creditors for the current user (when they are a debtor).

### Changes

| File | Change |
|---|---|
| `src/Domain/Event.elm` | Add `SettlementPreferencesUpdated` payload variant, encoder/decoder |
| `src/Domain/GroupState.elm` | Add `settlementPreferences` to `GroupState`, handle new event in `applyEvent` |
| `src/Domain/Activity.elm` | Handle new event in `fromEnvelope` (activity feed entry) |
| `src/Domain/Settlement.elm` | Add JSON encoder/decoder for `Preference` |
| `src/Page/Group/BalanceTab.elm` | Pass preferences to `computeSettlement`, add preference editor UI |
| `src/Submit.elm` | Add submission helper for settlement preference events |
| `src/Main.elm` | Handle preference update messages, submit event |
| `translations/messages.{en,fr}.json` | Labels: "Settlement preferences", "Pay first", "No preference" |
| `tests/CodecTest.elm` | Roundtrip fuzz test for `SettlementPreferencesUpdated` |

### Implementation Steps

1. Add `SettlementPreferencesUpdated` to `Event.Payload` with encoder/decoder
2. Add `Preference` encoder/decoder in `Domain.Settlement`
3. Add `settlementPreferences : List Settlement.Preference` to `GroupState`, apply during replay
4. Add `fromEnvelope` case in `Domain.Activity` for the new event
5. Add `Submit` helper for creating preference events
6. Pass `state.settlementPreferences` to `computeSettlement` in `BalanceTab`
7. Add preference editor UI on the Balance tab
8. Wire messages through `Main.elm`
9. Add translation keys and codec tests

---

## Feature 2: Group Import / Export

### Current State

All group data is event-sourced. A group consists of:
- `GroupSummary` (id, name, defaultCurrency)
- `List Event.Envelope` (the full event log)

JSON codecs exist for all types: `Event.encodeEnvelope` / `Event.envelopeDecoder`, `Storage.encodeGroupSummary` / `Storage.groupSummaryDecoder`.

No `elm/file` dependency exists yet — needed for both download (export) and file selection (import).

### Export Format

```json
{
  "format": "partage-group-v1",
  "exportedAt": 1234567890,
  "group": { "id": "...", "name": "...", "defaultCurrency": "EUR" },
  "events": [ { "id": "...", "clientTimestamp": ..., "triggeredBy": "...", "payload": { ... } }, ... ]
}
```

### Import Strategy

Since events are immutable and have globally unique UUIDv7 IDs:
- **Same group (sync)**: Merge by deduplicating on event ID. New events are appended, existing ones skipped. Replay all events to rebuild state.
- **New group**: Create a new group with a fresh ID, import all events as-is.

For the initial implementation, support **import as new group** only. This avoids merge complexity (chain conflicts, concurrent edits) while still covering the primary use case: backup/restore and sharing group data.

### Changes

| File | Change |
|---|---|
| `elm.json` | Add `elm/file` dependency |
| `src/Storage.elm` | Add `importGroup` function (save summary + events) |
| `src/GroupExport.elm` | New module: `encode` (group + events → JSON), `decoder` (JSON → group + events) |
| `src/Page/Home.elm` | Add "Export" button per group, "Import group" button |
| `src/Main.elm` | Handle export (load events, encode, trigger download) and import (file select, decode, validate, save) messages |
| `translations/messages.{en,fr}.json` | Labels: "Export group", "Import group", "Import successful", "Import failed" |

### Implementation Steps

1. `elm install elm/file` to add the dependency
2. Create `src/GroupExport.elm` with encode/decode functions using existing codecs
3. **Export flow**:
   - User clicks "Export" on a group card in Home
   - Main loads group events from IndexedDB via `Storage.loadGroupEvents`
   - Encode group summary + events as JSON
   - Trigger browser download via `File.Download.string` (filename: `partage-{groupName}.json`)
4. **Import flow**:
   - User clicks "Import group" on Home page
   - `File.Select.file ["application/json"]` opens file picker
   - Decode file contents with `GroupExport.decoder`
   - Validate: check format version, non-empty events, valid event structure
   - Generate new group ID (UUIDv4) to avoid conflicts
   - Save summary + events to IndexedDB via existing Storage functions
   - Navigate to the imported group
5. Add translation keys

### Future: Merge Import

A later iteration could support merging into an existing group:
- Deduplicate events by ID
- Detect chain conflicts (concurrent edits to same entry/member)
- Show merge report (new events count, conflicts)
- Let user confirm before applying

This is out of scope for the initial implementation.

---

## Implementation Order

1. **Settlement preferences** first — smaller scope, touches fewer files, no new dependencies
2. **Group export/import** second — needs new dependency, new module, more complex flow
