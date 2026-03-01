# Plan: Refactor Members to Chain-Based Model (like Entries)

## Context

Members are currently stored as a flat `Dict Member.Id MemberState` keyed by device member ID, with each device in a replacement chain being a separate dict entry. This is inconsistent with how entries work (keyed by rootId, grouping all versions). Since member replacement represents the same person on a new device, the semantic identity is the root ID — just like entries. This refactoring aligns the two models and simplifies balance computation (no more `resolveMemberRootId` for entries).

## Step 1: Domain types — `Domain/Event.elm`

Rename event payload fields from `memberId` to `rootId` for events that target the person (not the device):

- `MemberRenamed { memberId, oldName, newName }` → `MemberRenamed { rootId, oldName, newName }`
- `MemberRetired { memberId }` → `MemberRetired { rootId }`
- `MemberUnretired { memberId }` → `MemberUnretired { rootId }`
- `MemberMetadataUpdated { memberId, metadata }` → `MemberMetadataUpdated { rootId, metadata }`

**Also change:**
- `MemberReplaced { previousId, newId }` → `MemberReplaced { rootId, previousId, newId }` — `rootId` identifies the chain, `previousId` is the member being replaced (analogous to `previousVersionId` in entries), `newId` is the new device member

**Leave unchanged:**
- `MemberCreated { memberId, ... }` — this is the new device/chain ID

Update encoders: JSON field `"memberId"` → `"rootId"` for the 4 changed payloads. Add `"rootId"` encoding to `MemberReplaced`.

Update decoders: use `Decode.field "rootId"` directly (no backward compat — database will be erased).

## Step 2: Domain types — `Domain/GroupState.elm`

### New types

Replace `MemberState` with `MemberChainState` + `MemberInfo`:

```elm
type alias MemberChainState =
    { rootId : Member.Id
    , name : String
    , isRetired : Bool
    , metadata : Member.Metadata
    , currentMember : MemberInfo
    , allMembers : Dict Member.Id MemberInfo
    }

type alias MemberInfo =
    { id : Member.Id
    , previousId : Maybe Member.Id
    , depth : Int
    , memberType : Member.Type
    }
```

Chain-level fields: `name`, `isRetired`, `metadata` (describe the person).
Device-level fields: `id`, `previousId`, `depth`, `memberType` (describe the device identity).
Removed: `isActive` (= `not isRetired`), `isReplaced` (no chain-level concept).

Change `GroupState.members` from `Dict Member.Id MemberState` to `Dict Member.Id MemberChainState` (keyed by rootId).

### Rewrite event handlers

- `applyMemberCreated`: create a new chain with `rootId = memberId`, `depth = 0`
- `applyMemberRenamed`: `Dict.get data.rootId`, update `chain.name`
- `applyMemberRetired`: `Dict.get data.rootId`, set `isRetired = True`
- `applyMemberUnretired`: `Dict.get data.rootId`, set `isRetired = False`
- `applyMemberReplaced`: adds a new device member to an existing chain, with entry-like validations:
  1. `Dict.get data.rootId` → chain must exist
  2. `data.previousId` must exist in `chain.allMembers`
  3. `data.previousId` must not equal `data.newId` (self-replacement)
  4. `data.newId` must not already exist in `chain.allMembers` (duplicate)
  5. Compute `depth = prev.depth + 1`
  6. Create `MemberInfo` for newId (memberType = Real), insert into `allMembers`
  7. Pick `currentMember` via `pickCurrentMember` (deepest wins, ID breaks ties — like `pickVersion` for entries)

  No prior `MemberCreated` is needed for the new device — `MemberReplaced` implicitly creates the device member within the chain (analogous to how `EntryModified` creates a new version within an entry).
- `applyMemberMetadataUpdated`: `Dict.get data.rootId`, update `chain.metadata`

### Update query functions

- `activeMembers`: filter `not << .isRetired` (was `.isActive`)
- `resolveMemberName`: `Dict.get rootId` → `chain.name` (same as before but dict is now keyed by rootId)
- `resolveMemberRootId`: first check `Dict.member deviceId state.members`, else scan `allMembers` dicts. Only needed for current user identity resolution (device publicKeyHash → rootId)

### Update `recomputeBalances`

Remove `resolveMemberRootId` argument — entries already use rootIds.

## Step 3: Simplify `Domain/Balance.elm`

Remove the `(Member.Id -> Member.Id)` resolver parameter from:
- `computeBalances` — signature becomes `List Entry -> Dict Member.Id MemberBalance`
- `computeEntryPaid`, `computeEntryOwed`, `computeBeneficiarySplit`, `computeSharesSplit`, `distributeProportionally` — all drop the resolver, use member IDs directly (they're already rootIds)

## Step 4: Update consumers

### `src/Main.elm`
- `dummyMemberState` → `dummyMemberChainState` with new type shape
- `entryFormConfig`: `activeMembers` returns `MemberChainState`, map `.rootId` for both `id` and `rootId` (or simplify Config, see NewEntry below)
- `handleMemberDetailOutput`: `Event.MemberRenamed { rootId = data.memberId, ... }`, `Event.MemberRetired { rootId = ... }`, etc.
- `submitMemberMetadata`: `Event.MemberMetadataUpdated { rootId = output.memberId, ... }`
- `initPagesIfNeeded` member detail: `Dict.get memberId loaded.groupState.members` still works (memberId from URL is rootId)

### `src/Page/NewEntry.elm`
- `view : I18n -> List GroupState.MemberState -> ...` → `List GroupState.MemberChainState -> ...`
- Internal helpers (`payerField`, `beneficiariesField`, `beneficiaryCheckbox`, `memberDropdown`): same change. Access patterns `.rootId` and `.name` stay the same on `MemberChainState`.
- `Config.activeMembers`: simplify from `List { id : Member.Id, rootId : Member.Id }` to `List { rootId : Member.Id }` since `id` = `rootId` now. Update `init` and `initFromEntry` accordingly.

### `src/Page/MemberDetail.elm`
- `ModelData.member` type: `MemberState` → `MemberChainState`
- `infoSection`: `member.memberType` → `member.currentMember.memberType`
- Everything else (`.rootId`, `.name`, `.isRetired`, `.metadata`) stays the same

### `src/Page/Group/MembersTab.elm`
- `List.filter .isActive` → `List.filter (not << .isRetired)`
- Access patterns `.rootId`, `.name` unchanged

### `src/UI/Components.elm`
- `memberRow` type: `GroupState.MemberState` → `GroupState.MemberChainState`
- `config.member.memberType` → `config.member.currentMember.memberType`

### `src/Domain/Member.elm`
- Remove unused `Member` type alias (lines 27-37) — it mirrors the old `MemberState`

## Step 5: Update tests

### `tests/GroupStateTest.elm`
- Event construction: `MemberRenamed { memberId = ... }` → `MemberRenamed { rootId = ... }`, same for Retired/Unretired
- Member assertions: `.isActive` → `not .isRetired`, `.memberType` → `.currentMember.memberType`
- Remove `.isReplaced` and `.isActive` assertions
- Replacement tests rewrite — test the chain mechanics:
  - Valid replacement: `currentMember.id` is the new device ID, `allMembers` has both devices
  - Chain preserves rootId through replacements
  - `previousId` links correctly in the chain
  - Concurrent replacement: deeper chain wins, ID breaks ties (like entry conflict resolution)
  - Error scenarios: self-replacement ignored, rootId not found ignored, previousId not in chain ignored, duplicate newId ignored
- "ignores unretire for replaced member" test: rethink — after replacement the chain is still active (not retired), unretire is a no-op

### `tests/BalanceTest.elm`
- All `Balance.computeBalances identity [ entry ]` → `Balance.computeBalances [ entry ]` (~11 occurrences)

### `tests/CodecTest.elm`
- Update payload fuzzers: `MemberRenamed { rootId = ..., ... }`, `MemberRetired { rootId = ... }`, etc.

## Step 6: Cleanup

- Remove old `MemberState` export from `GroupState.elm`
- Remove `Member.Member` type from `Domain/Member.elm`
- Verify build: `pnpm build`
- Run tests: `pnpm test`

## Verification

1. `pnpm build` — compiles with `--optimize`
2. `pnpm test` — all tests pass
3. Manual: create group, add members, create entries, check balances display correctly

## Files to modify
- `src/Domain/Event.elm` — payload field renames + encoder/decoder changes
- `src/Domain/GroupState.elm` — new types, rewritten handlers, updated queries
- `src/Domain/Balance.elm` — remove resolver parameter
- `src/Domain/Member.elm` — remove unused `Member` type
- `src/Main.elm` — dummyMemberState, entryFormConfig, handleMemberDetailOutput, submitMemberMetadata
- `src/Page/NewEntry.elm` — view signature, Config type
- `src/Page/MemberDetail.elm` — MemberChainState
- `src/Page/Group/MembersTab.elm` — isActive → not isRetired
- `src/UI/Components.elm` — memberRow type
- `tests/GroupStateTest.elm` — member tests rewrite
- `tests/BalanceTest.elm` — remove identity resolver
- `tests/CodecTest.elm` — payload fuzzers
