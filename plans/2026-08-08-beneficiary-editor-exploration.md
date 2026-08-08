# Expense/income beneficiary editor exploration

## Progress

- Exploration complete: the two editors contain roughly 173 identical lines and differ only in their localized hint plus an expense-only `Shares` column label added after Income shipped. Consolidation is worthwhile and should remain on the backlog.

## Question

Would one beneficiary editor delete real duplication without introducing a generic, mode-heavy abstraction?

## Findings

`ExpenseView.beneficiariesField` and `IncomeView.beneficiariesField` duplicate the same state reads, exact-total validation, split-mode toggle, member rows, proportional amount preview, exact-amount inputs, share stepper, and validation errors. The compared blocks total 363 lines: Income's 174-line block is identical to Expense's except for one hint, while Expense has 15 additional lines for a `Shares` label.

The underlying state and messages are already shared. Both views use `Shared.ModelData`, `Shared.Msg`, `SplitMode`, `data.beneficiaries`, and `data.exactAmounts`; no callbacks or model adapters are required.

There are only two presentation differences:

1. The hint is genuinely entry-kind-specific: expenses describe who benefited, while income describes who should receive a share.
2. Expense shows a `Shares` label above share steppers; Income does not. Git history shows Income was copied from the then-identical Expense editor, then the label was added only to Expense in the later translation/wording commit `8832ad3`. Because the row controls and share semantics remain identical, this looks like duplication-driven drift rather than an intentional product distinction.

`Page.Group.NewEntry.Shared` is the natural owner. It already owns `ModelData`, `Msg`, split types, shared form fields, and every import required by the editor. A new generic UI module or callback-based component would add an unnecessary boundary.

## Options

### 1. Drop the backlog item

This leaves roughly 174 lines duplicated and requires every beneficiary UI or validation change to be made twice. The later one-sided `Shares` label demonstrates that this risk has already materialized. Not recommended.

### 2. Extract only rows and steppers

This removes some duplication but leaves the editor structure, toggle, total validation, and errors duplicated. It also creates more seams than moving the coherent field. Not recommended.

### 3. Move the complete editor to `Shared`

Expose one `beneficiariesField` and have Expense and Income pass their localized hint. This removes approximately 160–175 non-plan lines without changing state, update logic, messages, or renderer architecture. Recommended.

For strict behavior preservation, the function could also accept whether to show the `Shares` label. The cleaner result is to show the label for Income too and parameterize only the hint; that is a small visible consistency fix and should be approved explicitly before implementation.

## Recommendation

Keep the backlog item and implement option 3 as one increment. Do not generalize the editor over arbitrary models or messages. Resolve the `Shares` label drift first: preferably display it for both entry kinds, otherwise preserve it with one explicit configuration field.

## Decisions

- Keep and narrow the backlog item rather than dropping it. Alternative: tolerate the duplication. Reason: the common behavior is nearly exact, shares existing state/messages, and has already drifted once.
- Prefer `Page.Group.NewEntry.Shared` over a new beneficiary component module. Alternative: introduce `BeneficiaryEditor.elm`. Reason: `Shared` already owns the form types, helpers, and dependencies, so a new boundary would not buy independence.
- Do not extract only low-level row/stepper helpers. Alternative: leave two field wrappers. Reason: it preserves duplicated validation and structure while adding seams.
- Recommend treating Income's missing `Shares` label as accidental drift, but leave that visible behavior change for explicit approval. Alternative: add a configuration field solely to preserve the mismatch. Reason: both editors have identical share semantics and history shows the label was added to only one copy later.
