# RR-003 / RR-004 fixes

Addresses two blockers from `plan/release-readiness-review.md`.

## Progress

- I1 — app-level clock replaces event-derived `currentTime`. Lint clean, 291 tests pass.
- I2 — accessible names on icon-only controls. Lint clean, 291 tests pass; labels and
  `aria-expanded` verified present in the optimized build in both languages.
  Deviation: also named the error-log button in `Main`, an icon-only control of the
  same class that the review did not list.

## Context

**RR-003.** `currentTime` is seeded once from the JS flag (`Main.elm`) and afterwards
only advances when a locally authored event completes, via the
`Page.Group.UpdateCurrentTime` output carrying `envelope.clientTimestamp`. The
100-second group timer discards the `Time.Posix` it receives. A session left open
across midnight therefore serves yesterday's date to every time-derived value.

Blast radius is wider than the review recorded. Beyond the new-entry date default,
the exchange-rate cache date and the last-synced display, the stale clock also feeds:

- `IdGen.v7 ctx.currentTime` — the timestamp prefix of every generated event id
  (`GroupOps.elm:541,573,609,636,660`),
- `Entry.newMetadata … ctx.currentTime` — an entry's `createdAt` audit field
  (`GroupOps.elm:466`),
- `Group.createdAt` / `lastSyncedAt` (`GroupOps.elm:251,254,480,483`),
- `ErrorLog` timestamps (`Main.elm:320`).

Envelope `clientTimestamp` is unaffected: it comes from `ConcurrentTask.Time.now`
at signing time and is already correct.

**RR-004.** `iconButton` renders an SVG and takes no label. `fab` accepts a `label`
field and never renders it. Both produce controls with an empty accessible name;
the FAB is the primary route to creating an entry. `Ui.Input.button` does emit a
real `<button>` and the FAB is a real `<a href>`, so keyboard operability is fine —
this is a naming defect only (WCAG 2.2 SC 4.1.2, Level A).

## Increments

### I1 — app-level clock

Make `currentTime` a clock owned by `Main`, not a value derived from the event log.

- `Main`: `Time.every` tick plus `Browser.Events.onVisibilityChange`; regaining
  visibility performs a fresh `Time.now` so a resumed PWA is correct immediately
  rather than at the next tick.
- Delete `Page.Group.UpdateCurrentTime`, its two emission sites and Main's handler.
  The clock supersedes it.

### I2 — accessible names

- `iconButton` takes a mandatory `label`, rendered as `aria-label`.
- `fab` renders the `label` it already accepts.
- `filterToggleButton` takes a `label` and reports `aria-expanded`.
- Localized keys in `translations/messages.{en,fr}.ftl`; reuse `mergeSwapButton`
  for the merge swap control.

## Decisions

**I1 — clock interval of 60 s.** Alternatives: a 1–10 s tick, or fetching `Time.now`
on demand at the start of every time-sensitive action. Chose 60 s because it bounds
staleness at a cost comparable to the group sync tick already running at 100 s,
while on-demand fetching would thread a task through every form entry point for a
value only used at day granularity.

**I1 — `Browser.Events.onVisibilityChange` rather than a JS port.** `public/index.js`
already listens for `visibilitychange` to flush usage bytes, so a port was available.
Used the `elm/browser` subscription instead: no new port boundary, no JS change.

**I2 — `Ui.Accessibility.description` rather than a local helper.** Wrote an
`ariaLabel` helper in `UI.Components` first, then found elm-ui already ships the
identical function, documented for exactly this case. Dropped the local one.

**I2 — `UI.Shell`'s back control left alone.** It is a button whose contents are a
chevron *and* the page title, so its accessible name is the title rather than
empty. Adding `description "Back"` would drop the visible text out of the
accessible name and break SC 2.5.3 (Label in Name), so the current reading is the
conformant one.

**I1 — deleted `UpdateCurrentTime` instead of keeping it alongside the clock.**
Consequence: `Group.Summary.lastSyncedAt` now carries wall-clock time rather than
the last authored event's `clientTimestamp`. That value is only rendered as
relative "last synced" text, and the new reading matches the field's name.
