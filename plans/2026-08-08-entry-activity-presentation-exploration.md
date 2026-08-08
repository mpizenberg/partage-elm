# Explore entry/activity presentation sharing

## Progress

- Exploration complete: the whole-view abstraction is not worthwhile; two small presentation policies can be centralized independently, while the audit exposed allocation-detail correctness gaps that should be handled as a focused Activity task.

## Goal

Determine whether the first simplification-backlog item identifies a net simplification while preserving the deliberate distinction between the polished current-entry view and the dense exhaustive activity audit.

## Increments

1. Inventory exact duplication, intentional differences, and correctness drift; compare concrete extraction shapes by ownership, coupling, and approximate line/concept delta. Record a recommendation without changing the backlog item or production code, then commit the exploration.

## Findings

### Intentional independence

- Entries groups current ledger entries by their business `Date`, presents polished summaries and rich expandable details, and owns edit/duplicate/delete actions.
- Activity groups immutable events by timestamp in the viewer's time zone, presents dense actor/action summaries, and owns old/new diff rendering for entry, member, and group events.
- Their row typography, beneficiary layout, summaries, grouping inputs, deleted-entry behavior, and interaction models differ deliberately. Sharing either complete renderer would require mode flags or callbacks that cost more than the duplicated traversal.

### Duplication that does not justify a shared entry renderer

- `EntriesTab.entryContent` and `ActivityTab.entryDetailRows` each select description, date, money, participants, category, notes, and attachments for the three entry kinds. A shared component would still need separate rich/compact party rendering and a separate Activity diff path; a shared presentation record would mostly duplicate `Entry.Kind`.
- `detailRow` is structurally similar but intentionally uses different typography. Date grouping operates on different meanings. Payer/beneficiary name extraction is too small to justify a module by itself.
- The attachment-list helpers are currently exact copies, but moving roughly 15 lines is only worthwhile opportunistically in an existing owning component.

### Independent simplifications that are worthwhile

- Category presentation has no owner: the nine category-to-translation cases exist three times, while emoji/name pairs are also repeated in the entry form and Entries filter. A domain-specific UI presentation registry, following `UI.PaymentMethods`, would collapse three exhaustive mappings to one and centralize icon/name policy for an estimated 30–40 net-line reduction without coupling the tabs.
- Localized month names are exhaustively mapped twice. A date-presentation owner could let both tabs retain their separate grouping while sharing only conversion of a `Date` to localized long/short labels, removing roughly one 40-line mapping. This fits the existing repeated-small-utilities backlog more than an entry/activity abstraction.

### Correctness drift exposed by the audit

- Activity compares full payer records but formats only member names. A change from `Alice 60 / Bob 40` to `Alice 50 / Bob 50` therefore renders `Alice, Bob → Alice, Bob`.
- Activity likewise compares full beneficiaries but formats only names. Share-count or exact-amount changes involving the same members render identical old and new values. Added-entry snapshots also omit those allocations.
- Entries shows beneficiary allocations but omits payer amounts, despite supporting arbitrary multi-payer splits.
- Income change detection emits the internal key `receivedBy`, but `ActivityTab.translateField` has no matching translation branch, so the collapsed summary exposes that identifier.
- A change only to `defaultCurrencyAmount` appears in the expanded diff but is absent from the collapsed changed-field list. Expense `location` is preserved in the model/export but is not shown or diffed anywhere; the current new-entry and Splitwise-import paths set it to `Nothing`, while imported group history can preserve an older value, so its intended status needs a product decision.
- There are no Activity-domain or tab-presentation tests covering these cases.

## Recommendation

Drop the current broad backlog item rather than implementing a shared entry renderer. Replace it with a focused Activity audit-fidelity task for allocation values, translated change labels, default-currency changes, and explicit disposition of `location`; decide separately whether Entries should show multi-payer allocations. Keep category and localized-date ownership as small simplifications, either as a narrow replacement item or under the existing repeated-small-utilities item.

Do not change the standing backlog until the user chooses among those follow-ups.

## Decisions

- Treat the two tabs as intentionally independent renderers. Alternative: investigate a common visual component. Reason: Entries presents final ledger state while Activity presents event history and diffs; shared layout would couple distinct density and information goals.
- Recommend removing the broad sharing item. Alternative: retain it with narrower wording. Reason: the viable reductions are independent category/date policies, while the important cross-tab findings are correctness issues rather than evidence for a shared renderer.
