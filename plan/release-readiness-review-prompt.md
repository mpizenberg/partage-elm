# Partage release-readiness review prompt

## Progress

- Scope agreed with the owner and translated into the executable review prompt below.
- Scope revised by the owner.

## Decisions

- Review the current working tree, not Git history or backward compatibility. This keeps the review focused on the first release candidate.
- Treat the self-hosted Node.js and SQLite relay as the production target. Cloudflare-only deployment behavior is not a release criterion, except where shared code or protocol behavior affects the self-hosted target.
- Review dependencies only at the integration and surface-risk level. Do not inspect dependency or vendored source internals.
- Keep runtime tests local and isolated. Never open, copy, modify, delete, or otherwise touch the existing relay database files.
- Write findings only; do not implement fixes or create commits. This separates diagnosis from remediation.

## Prompt to execute

You are performing an exhaustive release-readiness review of Partage. Work autonomously until the report is complete unless genuinely blocked by a decision only the owner can make.

Repository:

`/Users/piz/git/mpizenberg/partage-elm`

Read `CLAUDE.md` completely before doing any work and obey its repository guidance. Review the current working tree as it exists at the start of the review. Do not review Git history or compare branches.

### Outcome

Decide whether this application is ready for its first production release and explain why. Produce a rigorous, evidence-backed review at:

`plan/release-readiness-review.md`

The review is for the project owner. It must include an executive go/no-go assessment, clearly separated release blockers, all other credible findings, positive assurance about important areas that were checked successfully, limitations, and a staged remediation plan.

This is a review-only task:

- Do not implement fixes.
- Do not modify application source, tests, documentation, configuration, lockfiles, generated assets, or existing data.
- Do not make commits.
- The only repository file you may create or update is `plan/release-readiness-review.md`.
- Temporary test scripts, logs, profiles, databases, and fixtures must live in a uniquely created temporary directory.
- Run commands that may create caches or generated output from an isolated temporary mirror, not the repository itself.
- At the end, verify and report whether the working-tree state differs from its initial state. Never revert pre-existing user changes.

### Product and release context

Partage is a local-first bill-splitting PWA. Its application state is stored in IndexedDB, synchronized through a relay, and derived from an immutable event log. Identity continuity, deterministic event replay, offline behavior, and correct financial calculations are core product guarantees.

The release target is:

- Current working tree only.
- First public release; no backward-compatibility requirement.
- Self-hosted Node.js relay with SQLite.
- Locally served Elm/browser application.
- No production or live deployment testing.
- Browsers and devices that are most widely used at review time. Establish and state a practical current support matrix using up-to-date sources; include desktop and mobile Chrome, Safari, Firefox, and Edge where materially used.
- Normal usage: 2–20 members per group, 1–2 devices per member, and 2–15 groups per person.
- Where event-volume or relay-fleet limits are not specified, infer reasonable release expectations from the specification, configured quotas, and normal multi-year use. State the assumption.
- WCAG 2.2 AA is the accessibility target.
- `docs/SPECIFICATION.md` is intended to be authoritative.

Review English as the principal UI language. Do not conduct an exhaustive translation or linguistic review. Still report missing translation keys, broken language switching, obvious truncation/layout failures, or functional differences caused by localization if encountered.

### Scope

Review:

- Elm frontend architecture, update/view flow, state transitions, forms, routing, domain logic, and error handling.
- Financial correctness: expenses, transfers, income, arbitrary splits, currency conversion, rounding, balances, settlement generation, stable settlements, member linking/merging, filtering, import/export, and audit history.
- Browser JavaScript integration and every Elm port boundary.
- IndexedDB storage, migration/current-schema behavior, transactions, failure recovery, quota behavior, and persistence assumptions.
- Event protocol ordering, replay, pagination, retry, deduplication, idempotency, concurrency, compaction, malformed-data recovery from honest faults, and deterministic convergence.
- Offline behavior, reconnection, multi-device and multi-tab behavior, WebSockets, background/visibility transitions, service worker, installability, update lifecycle, caching, and push notifications.
- The self-hosted Node.js/Hono/SQLite relay, including HTTP and WebSocket behavior, storage semantics, concurrency, limits, retention, maintenance, admin surface, static serving, and failure paths.
- Tests, lint/review rules, formatting, builds, build-time configuration, generated-code boundaries, and CI/release reproducibility.
- Self-hosted operational readiness: configuration, reverse-proxy routing assumptions, startup/shutdown, SQLite durability and locking, migrations, backup/restore guidance, retention, disk exhaustion, observability, deployment, rollback, and recovery documentation.
- UX and WCAG 2.2 AA: keyboard use, focus, semantic structure, accessible names, forms/errors, contrast, motion, responsive layouts, touch targets, destructive actions, empty/loading/error/offline states, and recovery paths.
- Privacy and legal-readiness issue spotting: data minimization, client-side personal/payment data, server-visible metadata, logs, retention/deletion, disclosures, export/removal behavior, and GDPR-oriented risk. Clearly state that this is not legal advice.
- Consistency among implementation, `docs/SPECIFICATION.md`, README, deployment/storage documentation, and observable behavior.

Treat honest failures and accidental malformed data as in scope. Consider, among other relevant cases:

- Corrupt, truncated, duplicated, reordered, or replayed events caused by faults.
- Unknown/newer event shapes, stale local state, identity re-linking, and device recovery.
- Concurrent edits, clock skew, interrupted sync, partial writes, retry storms, pagination boundaries, and compaction races.
- A faulty relay returning inconsistent, oversized, or stale content.
- Malformed imports/exports, unexpectedly large files, accidental resource exhaustion, and invalid URLs.
- Browser storage eviction, private browsing restrictions, lost keys, service-worker upgrade failures, and unsupported Web APIs.

### Explicit exclusions

- Do not inspect implementation internals in `node_modules/` or vendored Elm packages.
- Do not review generated artifacts such as `dist/` or generated `src/Translations.elm` as authored source. You may validate generated output behavior when needed.
- Do not inspect or use local relay database contents.
- Do not assess Cloudflare Workers/Durable Objects deployment readiness. Cloudflare-specific files matter only when they expose a contradiction in shared protocol behavior or documentation relevant to the Node/SQLite release.
- Do not perform a comprehensive translation-quality review.
- Do not conduct a formal legal compliance audit.
- Do not conduct cybersecurity review or report cybersecurity findings.
- Do not require backward compatibility with an earlier release.

Perform only a lightweight dependency review:

- Check declared versions, lockfile consistency, runtime compatibility, and obvious unmaintained/deprecated integration risk using authoritative current sources.
- Review how dependencies are configured and trusted by this application.
- Do not recursively audit dependency code.
- Do not change versions, regenerate lockfiles, or install anything.

### Machine and data safety requirements

Protect the machine and repository throughout the review:

- Never connect to, probe, or modify a production/live deployment or non-loopback service.
- Do not upload source code, data, keys, database contents, or build artifacts to any external service.
- Internet access is allowed only for relevant current documentation, browser support information, standards, and dependency compatibility/maintenance information. Prefer primary and authoritative sources and cite them in the report.
- Do not run `pnpm install`, `npm install`, `npx`, `elm install`, package upgrades, or any other command that installs or changes dependencies.
- Inspect scripts before executing them. Use only dependencies already present.
- Do not change machine-level configuration, global caches intentionally, credentials, firewall settings, browser profiles, or unrelated processes.
- Do not use destructive commands. Clean up only processes and temporary resources you created, and only when their exact identity is known. It is acceptable to leave a clearly identified temporary directory rather than risk deleting the wrong target.
- Keep resource tests bounded. Do not intentionally exhaust disk, memory, CPU, file descriptors, sockets, or network bandwidth. Simulate limits with small configured thresholds or test doubles.
- Never open, read, copy, migrate, vacuum, write, delete, or point a process at:
  - `packages/relay/data/relay.db`
  - `packages/relay/data/relay.db-shm`
  - `packages/relay/data/relay.db-wal`
- Any relay runtime must receive an explicit `RELAY_DB` path inside a fresh temporary directory. Do not rely on the relay's default path.
- Bind test servers to loopback only and choose an available non-privileged port. Confirm the binding behavior before starting them.
- Use a fresh disposable browser profile and synthetic test data for browser checks. Never use a personal browser profile.
- Do not follow application links to arbitrary external destinations during testing.
- Do not expose secrets in terminal output or the report. Use synthetic secrets only.

For tests and builds that may write caches or generated files, create a temporary mirror of the working tree. Exclude `.git`, all `node_modules`, `elm-stuff`, `dist`, and `packages/relay/data` while copying. Link the already-installed root and relay `node_modules` into the mirror read-only in intent; do not install or update them. Copy the generated `src/Translations.elm` only as a required build input. Keep all generated output, caches, test databases, logs, and browser profiles within that temporary tree. Do not copy any existing relay database.

If a useful test cannot be performed safely under these constraints, do not perform it. Record the limitation and use static reasoning or existing tests instead.

The owner cannot scroll the terminal. Keep each progress update and terminal excerpt below roughly 50 lines. Put long command output and working notes in the temporary directory, and put substantive results in the report file.

### Review method

Be systematic rather than sampling only interesting files.

1. Record the initial Git status and environment versions.
2. Inventory all in-scope tracked files and map major components, trust boundaries, persisted data, protocol flows, and build/deployment paths.
3. Read all repository-authored specification and operational documentation.
4. Establish a traceability checklist from every major section of `docs/SPECIFICATION.md` to implementation and tests. Use it to detect missing, partial, contradictory, and undocumented behavior.
5. Inspect every in-scope repository-authored source/configuration file. Maintain a private coverage ledger so no module is silently skipped.
6. Construct a concise failure model covering persisted state, process/browser boundaries, offline transitions, partial operations, availability risks, and recovery expectations.
7. Trace critical flows end to end, across Elm, ports, storage, network protocol, relay, and replay:
   - first launch and identity creation;
   - group creation and joining;
   - event creation, persistence, push, pull, replay, and compaction;
   - offline edits and concurrent multi-device convergence;
   - member claim/re-link/merge and device/member recovery;
   - financial entry lifecycle and settlement;
   - export/import and device/group recovery;
   - archiving/removal, relay retention, and rehydration;
   - PWA install/update and push lifecycle;
   - admin/operations and relay recovery.
8. Run the existing quality gates from the isolated temporary mirror after inspecting their definitions. At minimum, where safely supported:
   - `pnpm format:check`
   - `pnpm lint`
   - `pnpm test`
   - `pnpm -C packages/relay test`
   - the optimized production build
9. Preserve full outputs in the temporary directory. In the report, give command, exit status, relevant summary, and any important skipped check. A passing suite is evidence, not proof of correctness.
10. Add focused, bounded runtime experiments only where they can confirm or refute a material hypothesis. Temporary scripts and fixtures must stay outside tracked source.
11. If browser automation is available without installing anything, exercise representative desktop and narrow mobile viewports, keyboard-only navigation, offline/reconnect behavior, storage persistence, service-worker update behavior, main error states, and core financial flows. Inspect console and network failures. If automation is unavailable, perform the strongest safe substitute and document the limitation.
12. For distributed and financial invariants, use edge cases and property-style reasoning even where existing tests pass. Check whether important invariants are actually asserted.
13. Validate the self-hosted relay with isolated temporary SQLite databases, including clean startup, restart persistence, concurrent requests, accidentally malformed/oversized requests, retention/maintenance behavior where safely simulatable, WebSocket lifecycle, and graceful failure.
14. Check current authoritative external information only where time-sensitive: Web API/browser support, WCAG references, Node/SQLite operational behavior, and dependency compatibility/maintenance.
15. Re-read findings against source and tests before reporting them. Attempt a safe disconfirmation. Distinguish observed fact, source-derived reasoning, and inference.
16. Finish with a final Git-status comparison and confirm that no source or existing data was modified.

Do not stop after automated checks. The central task is careful review and reasoning.

### Release-readiness criteria

At minimum, treat the following as release blockers when credible and applicable:

- Incorrect balances, settlements, currency amounts, ownership resolution, or audit history under supported use.
- Loss, silent corruption, irrecoverability contrary to the documented model, or deterministic-convergence failure.
- A normal install, first-use, group creation/join, sync, offline/reconnect, or self-hosted deployment path that does not work on the practical browser/runtime support matrix.
- A readily reachable crash, persistent broken state, or resource failure under normal stated scale.
- A critical accessibility barrier preventing a core flow for keyboard or assistive-technology users.
- Missing operational prerequisites that make self-hosting materially unreliable or unrecoverable.
- A serious contradiction between the authoritative specification and shipped behavior that affects correctness, durability, accessibility, privacy disclosures, or a core advertised feature.

Evaluate preconditions, affected users/data, frequency, detectability, recoverability, and confidence.

Use these severities:

- **Critical:** widespread, unrecoverable data loss or corruption.
- **High:** major correctness/reliability/accessibility failure affecting core use or requiring release delay.
- **Medium:** meaningful defect or risk with limited conditions, workaround, or blast radius.
- **Low:** real but modest reliability, UX, accessibility, maintainability, or operational issue.
- **Informational:** useful hardening or clarity improvement without a demonstrated defect.

Mark `Release blocker: Yes/No` separately from severity. A finding may be important without blocking release.

### Evidence standard

Report all credible findings, including low-severity and maintainability issues, but do not pad the report with generic advice.

Every finding must contain:

- Stable ID and concise title.
- Severity and whether it blocks release.
- Confidence: high, medium, or low.
- Affected component and user/operational scenario.
- Exact repository evidence with file paths and line numbers.
- Relevant specification section or statement, when applicable.
- Reproduction or triggering sequence when practical.
- Observed behavior versus expected behavior.
- Concrete impact, prerequisites, blast radius, detectability, and recovery implications.
- Root cause.
- Remediation direction, without implementing it.
- A focused verification/test recommendation for the eventual fix.
- External citation near the claim if the finding depends on current outside information.

For findings established only by reasoning, say so. Label uncertain hypotheses and do not present them as confirmed defects. Consolidate symptoms sharing one root cause. Do not copy secrets or sensitive local values into the report.

Positive assurance must also be specific: identify important invariants and failure paths checked, the evidence used, and the remaining limitation.

### Required report structure

Write `plan/release-readiness-review.md` with:

1. **Review metadata**
   - Date, reviewed commit/worktree state, environment, target, and scope.
2. **Executive summary**
   - Clear `GO`, `CONDITIONAL GO`, or `NO-GO`.
   - Short rationale, blocker count, finding counts by severity, and top risks.
3. **Release blockers**
   - Compact table followed by full findings.
4. **Non-blocking findings**
   - Ordered by severity and then risk.
5. **Specification conformance**
   - Major-section coverage and discrepancies.
6. **Privacy disclosures and data lifecycle**
   - Data minimization, local/server-visible data, retention/export/removal behavior, and legal-readiness caveat. Explicitly state that cybersecurity assurance is excluded.
7. **Correctness, synchronization, and data durability**
8. **Self-hosted operational readiness**
9. **UX, accessibility, browser, and PWA assessment**
10. **Tests, tooling, dependencies, and maintainability**
11. **Positive assurance**
12. **Validation performed**
   - Commands, runtime/browser scenarios, results, and retained temporary artifact location if any.
13. **Coverage and limitations**
   - Areas/files reviewed, exclusions, unavailable tools, untested scenarios, and assumptions.
14. **Prioritized remediation plan**
   - Release blockers first, then short-term and post-release work. Do not provide code changes.
15. **Final release checklist**
   - Concrete criteria that must be satisfied before release.

Keep the executive summary concise, but make the evidence sections detailed enough that another engineer can reproduce and fix each confirmed issue without rediscovering it.

Before finishing:

- Reconcile every count and severity between the summary and findings.
- Confirm every finding has evidence and remediation direction.
- Confirm all explicit exclusions and unperformed checks are disclosed.
- Confirm the report contains no secrets or personal/local database data.
- Confirm no existing database was touched.
- Confirm the final working-tree state and disclose any unexpected change.
- Do not commit the report.
