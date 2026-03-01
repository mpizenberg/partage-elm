# Plan: Local Features — Entry Form Enhancements, Multi-Currency, Activity Feed

## Context

The entry form currently supports single payer and equal-share beneficiaries only. The domain model (`Entry.Payer`, `Entry.Beneficiary` with `ShareBeneficiary`/`ExactBeneficiary`) already supports the full range — the form just doesn't expose it. Multi-currency is similarly ready in the domain (`ExpenseData.defaultCurrencyAmount`, `Currency` type) but the form hardcodes the group's default currency. The activity feed has a placeholder tab and a stub `Domain.Activity` module.

All 5 features are independent of server sync.

## Step 1: Unequal shares

Allow different share counts per beneficiary (e.g., 2 shares for adults, 1 for kids).

- `src/Page/NewEntry.elm`:
  - `beneficiaryIds : Set Member.Id` → `beneficiaries : Dict Member.Id Int` (memberId → shares, default 1)
  - New `Msg`: `InputBeneficiaryShares Member.Id String`
  - `ToggleBeneficiary`: insert with shares=1 / remove
  - `ExpenseOutput.beneficiaryIds` → `beneficiaries : List { memberId : Member.Id, shares : Int }`
  - `outputToKind`: use actual share values instead of hardcoded 1
  - `initFromEntry`: extract share values from existing `ShareBeneficiary` entries
  - View: small numeric input next to each selected beneficiary checkbox
- `src/Submit.elm` `newEntry`: use `output.beneficiaries` with real shares
- Translations: `newEntrySharesLabel`

## Step 2: Exact amount split

Toggle between shares-based and exact-amount beneficiary split.

- `src/Page/NewEntry.elm`:
  - New type: `SplitMode = ShareSplit | ExactSplit`
  - `ModelData`: add `splitMode : SplitMode`, `exactAmounts : Dict Member.Id String`
  - New `Msg`: `InputSplitMode SplitMode`, `InputExactAmount Member.Id String`
  - Validation: when ExactSplit, sum of exact amounts must equal total `amountCents`
  - `ExpenseOutput`: change `beneficiaries` to `split : SplitData` where:
    ```
    type SplitData
        = ShareSplitData (List { memberId, shares })
        | ExactSplitData (List { memberId, amount })
    ```
  - `outputToKind`: create `ShareBeneficiary` or `ExactBeneficiary` based on mode
  - `initFromEntry`: detect mode from existing beneficiaries (all Share → ShareSplit, all Exact → ExactSplit)
  - View: radio toggle (Shares / Exact) above beneficiary list. Exact mode: amount input per beneficiary, remaining amount display.
- Translations: `newEntrySplitMode`, `newEntrySplitShares`, `newEntrySplitExact`, `newEntryExactRemaining`, `newEntryExactMismatch`

## Step 3: Multiple payers

Split who paid among multiple members with per-payer amounts.

- `src/Page/NewEntry.elm`:
  - New type: `PayerMode = SinglePayer | MultiPayer`
  - `ModelData`: add `payerMode : PayerMode`, `payers : Dict Member.Id String` (raw amount strings)
  - New `Msg`: `InputPayerMode PayerMode`, `TogglePayer Member.Id`, `InputPayerAmount Member.Id String`
  - Validation: when MultiPayer, sum of payer amounts must equal total `amountCents`
  - `ExpenseOutput.payerId` → `payers : List { memberId : Member.Id, amount : Int }`
  - `outputToKind`: map payers list to `Entry.Payer` records
  - `initFromEntry`: single payer → SinglePayer; multiple → MultiPayer with amounts
  - View: toggle "Single / Multiple". Single: existing dropdown. Multi: checkboxes + amount inputs, remaining display.
- `src/Submit.elm` `newEntry`: use `output.payers` directly
- Translations: `newEntryPayerMode`, `newEntryPayerSingle`, `newEntryPayerMultiple`, `newEntryPayerRemaining`, `newEntryPayerMismatch`

## Step 4: Multi-currency entries

Allow entries in non-default currencies with manual exchange rate.

- `src/Domain/Currency.elm`:
  - Expand `Currency` type: add JPY, AUD, CAD, CNY, SEK, NZD, MXN, SGD, HKD, NOK, KRW, TRY, INR, RUB, BRL, ZAR
  - Add `allCurrencies : List Currency`, `currencyCode : Currency -> String`
  - Update encoders/decoders
  - Note: JPY/KRW have precision 0 — verify `Format.elm` handles this
- `src/Page/NewEntry.elm`:
  - `Config`: add `defaultCurrency : Currency`
  - `ModelData`: add `currency : Currency`, `defaultCurrencyAmount : String`
  - New `Msg`: `InputCurrency Currency`, `InputDefaultCurrencyAmount String`
  - Conditional field: when `currency /= defaultCurrency`, show "Amount in {defaultCurrency}" input
  - `ExpenseOutput` and `TransferOutput`: add `currency`, `defaultCurrencyAmount : Maybe Int`
  - `initFromEntry`: load currency and defaultCurrencyAmount from entry
  - View: currency dropdown near amount field
- `src/Submit.elm`: use output's currency instead of hardcoding `loaded.summary.defaultCurrency`
- `src/Page/EntryDetail.elm`: show both amounts when defaultCurrencyAmount is set
- `src/UI/Components.elm` `entryCard`: show currency if different from group default
- `tests/CodecTest.elm`: fuzzers for new Currency variants
- Translations: `newEntryCurrencyLabel`, `newEntryDefaultCurrencyAmountLabel`

## Step 5: Activity feed

Display audit trail of all group events with human-readable descriptions.

- `src/Domain/Activity.elm` (rewrite):
  ```elm
  type alias Activity =
      { eventId : Event.Id
      , timestamp : Time.Posix
      , actorId : Member.Id
      , detail : Detail
      }

  type Detail
      = EntryAddedDetail { description : String, amount : Int, currency : Currency }
      | EntryModifiedDetail { description : String }
      | EntryDeletedDetail { description : String }
      | EntryUndeletedDetail { description : String }
      | MemberJoinedDetail { name : String, memberType : Member.Type }
      | MemberReplacedDetail { name : String }
      | MemberRenamedDetail { oldName : String, newName : String }
      | MemberRetiredDetail { name : String }
      | MemberUnretiredDetail { name : String }
      | MemberMetadataUpdatedDetail { name : String }
      | GroupMetadataUpdatedDetail

  fromEvents : GroupState -> List Event.Envelope -> List Activity
  ```
  Builds activity list from events (newest first). Uses GroupState for entry description lookup on delete/undelete events.

- `src/Page/Group/ActivitiesTab.elm` (rewrite):
  - `view : I18n -> (Member.Id -> String) -> List Activity -> Ui.Element msg`
  - Each activity: actor name, action text (translated with interpolation), relative or absolute timestamp

- `src/Page/Group.elm`:
  - Build activities from `loaded.events` + `loaded.groupState`, pass to ActivitiesTab

- Translations: ~12 keys for activity descriptions (EN + FR):
  `activityEntryAdded`, `activityEntryModified`, `activityEntryDeleted`, `activityEntryUndeleted`, `activityMemberJoined`, `activityMemberJoinedVirtual`, `activityMemberReplaced`, `activityMemberRenamed`, `activityMemberRetired`, `activityMemberUnretired`, `activityMemberMetadataUpdated`, `activityGroupMetadataUpdated`

## Implementation order

1 → 2 → 3 → 4 → 5 (steps 1-3 build on each other in the same files; 4 is orthogonal; 5 is independent)

## Files modified

| File | Steps |
|---|---|
| `src/Page/NewEntry.elm` | 1, 2, 3, 4 |
| `src/Submit.elm` | 1, 3, 4 |
| `src/Domain/Currency.elm` | 4 |
| `src/Domain/Activity.elm` | 5 |
| `src/Page/Group/ActivitiesTab.elm` | 5 |
| `src/Page/Group.elm` | 5 |
| `src/Page/EntryDetail.elm` | 4 |
| `src/UI/Components.elm` | 4 |
| `src/Format.elm` | 4 (0-precision currencies) |
| `tests/CodecTest.elm` | 4 |
| `translations/messages.en.json` | 1, 2, 3, 4, 5 |
| `translations/messages.fr.json` | 1, 2, 3, 4, 5 |

## Verification

After each step:
1. `pnpm build` — compiles with --optimize
2. `pnpm test` — all tests pass
3. Manual: create group, add entries exercising the new feature, verify balances are correct
