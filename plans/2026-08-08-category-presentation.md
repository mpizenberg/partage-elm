# Centralize entry category presentation

## Progress

- Increment 1 complete: `Domain.Entry` owns category order and `UI.Categories` owns the exhaustive localized label/emoji mapping; all presentation call sites now use them, the existing codec fuzzer reuses the canonical list, and the production build, formatting, lint, and all 343 Elm tests pass. Net non-plan source reduction: 36 lines.

## Goal

Give expense categories one presentation owner for localized labels, emoji, and display order, while preserving the independent Entries and Activity renderers.

## Increment

1. Add the canonical category order to `Domain.Entry`, add `UI.Categories` as the exhaustive presentation mapping, replace category cases and hand-written lists in Entries, Activity, filters, and the expense form, remove the completed backlog item, validate, and commit.

## Decisions

- Keep category existence and order in `Domain.Entry`, and localized labels and emoji in `UI.Categories`. Alternative: let the UI module own both. Reason: this follows the existing `Domain.PaymentMethod`/`UI.PaymentMethods` boundary and keeps presentation out of the wire-format domain.
- Do not add category presentation tests. Alternative: pin the category list and labels in a dedicated test. Reason: the user explicitly prefers compiler exhaustiveness for this mechanical presentation mapping.
