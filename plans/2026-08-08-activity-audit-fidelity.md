# Restore Activity audit fidelity

## Progress

- Increment 1 complete: Activity changed fields are typed and exhaustive; converted amounts, locations, and income receivers are tracked and localized; 343 Elm tests and elm-review pass.
- Increment 2 complete: dense Activity details now include payer amounts and beneficiary allocations in both snapshots and diffs; preserved locations appear in Entries and Activity; the production build, formatting, lint, and all 343 Elm tests pass.

## Goal

Make the dense Activity feed faithfully identify entry modifications without coupling its renderer to the polished Entries view.

## Increments

1. Replace stringly changed-field identifiers with an exhaustive Activity field type; include default-currency-only and location changes, add localized labels, and cover domain change detection with tests.
2. Render payer amounts and beneficiary allocations in compact Activity snapshots and diffs, display preserved expense locations, validate the full Elm suite, and commit.

## Decisions

- Use a closed `Domain.Activity.ChangedField` type rather than adding one missing `"receivedBy"` string branch. Alternative: retain strings and patch the translation function. Reason: the compiler should force every new tracked field to receive a display label; this removes the cause of the drift.
- Treat `defaultCurrencyAmount` as an amount change. Alternative: introduce a separate changed-field label. Reason: it is the default-currency expression of the same amount, and the expanded diff already groups both values.
- Display a preserved expense `location` in both final entry details and Activity, and track its old/new value. Alternative: leave the dormant field export-only. Reason: imported history can contain a known value, and neither a final-state view nor an exhaustive audit should silently discard known data.
- Keep Entries' payer presentation unchanged in this task. Alternative: introduce shared allocation presentation immediately. Reason: Activity has a correctness requirement to expose old/new allocations; changing the polished current-entry design is a separate product choice.
