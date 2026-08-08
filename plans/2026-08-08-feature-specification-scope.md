# Feature specification scope

## Progress

- Audit and rewrite complete: the specification is now a 287-line shipped-product contract instead of a 1,497-line mix of contract, implementation, protocol, rationale, and roadmap. Neighboring links and obsolete numbered source-comment references were updated or removed. Production build, 343 Elm tests, 106 relay Node tests, 39 relay Worker tests, elm-review, elm-format, Markdown link validation, and diff checks pass.

## Goal

Turn `docs/SPECIFICATION.md` into the current product contract: what users can do, what data and security guarantees Partage makes, and the constraints integrations must preserve. Remove implementation testimony, protocol duplication, rejected alternatives, and speculative roadmap material that drift independently of the code.

## Increment

1. Audit the existing claims against the product and neighboring documentation; rewrite the specification around current observable behavior and security constraints; update inbound documentation links whose anchors become obsolete; remove the completed backlog item; validate internal links and formatting; commit.

## Scope boundary

Keep:

- Product principles and user-observable workflows.
- Data semantics that define balances, history, identity, convergence, import/export, and collaboration.
- Privacy, cryptographic, compromise-response, retention, and recovery guarantees.
- Relay boundary constraints that an alternative implementation must preserve.

Remove:

- Source-level types, store layouts, routing tables, UI component names, exact batching cadence, and server database/API tables.
- Algorithm narration where only the outcome is a product promise.
- Rejected-design history, performance testimony, and not-yet-shipped ideas.
- Repeated lists and details already owned by deployment or storage/performance documentation.

## Decisions

- Rewrite the document instead of patching individual stale statements. Alternative: update each drifted detail in place. Reason: the mixed document roles are the cause of drift; correcting testimony would preserve that cause. Reversible by git history.
- Keep a concise relay contract in the feature specification, but leave endpoint/schema/operator details to source, tests, and `docs/DEPLOY.md`. Alternative: retain Appendix C as a protocol reference. Reason: it already omits live fields and duplicates an independently changing implementation boundary.
- State that a relay can correlate the same device identifier across groups. Alternative: preserve the old claim that the relay cannot correlate a user across groups. Reason: `actorId` is the stable public-key hash and is visible to a shared relay, so the old privacy guarantee was false.
- Treat labelled URL attachments, CSV export, and English Splitwise CSV import as shipped contract, while documenting stored expense locations as display-only compatibility data. Alternative: retain the future/out-of-scope lists and the old entry-field table. Reason: those lists contradicted current forms and import/export paths.
