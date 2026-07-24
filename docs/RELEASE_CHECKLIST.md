# Release checklist

CI covers Elm domain logic and the relay protocol, but not real browser and PWA
behaviour — IndexedDB transactions, service-worker lifecycle, multi-tab queues,
time/visibility handling, and accessible DOM output. This is the manual pass that
covers that gap before a release. Run it on a **build served the way it will
ship** (same-origin relay, `pnpm build:optimize`), not the dev hot-reload server.

**Scope.** Two browsers — desktop **Chromium** and **Firefox** — plus **one
installed PWA** (Android Chrome or desktop Chromium). WebKit/iOS is a manual
best-effort when a device is available. Use a fresh profile so first-run state is
real.

## Core flows

- [ ] **First use.** Fresh profile → open the app → the welcome screen generates
      an identity, then create a group. Reload: the identity and group are still
      there (no re-generation, no empty home).
- [ ] **Add each entry kind.** Add an expense, a transfer, and an income; confirm
      the balance and activity log update and survive a reload.
- [ ] **Persistence across reload.** Add a few entries, hard-reload mid-session;
      nothing added is lost and balances match.
- [ ] **Edit and delete.** Edit an entry and delete another; the activity log
      shows the specific action and balances recompute.
- [ ] **Import / export.** Export a group to `.partage`, re-import it into a fresh
      profile, confirm it matches. Importing an oversized file shows the
      "too large" error rather than freezing the tab.

## Sync and multi-tab

- [ ] **Offline → reconnect.** Go offline (devtools), add entries, come back
      online; the offline banner clears and the queued entries push and appear on
      a second device/profile in the same group.
- [ ] **Two-tab queue.** Open the same group in two tabs; add entries in each
      within the same sync window; after both sync, no entry is dropped from either
      tab (the unpushed-queue race, RR-002).
- [ ] **Reconnect resync.** Join the group from a second profile and confirm it
      pulls the full history, then stays live-updated over the WebSocket.
- [ ] **Day rollover.** With the app left open across local midnight (or the
      device clock advanced), date-relative labels and "today" refresh without a
      manual reload (RR-003).

## PWA lifecycle

- [ ] **Install and standalone.** Install the PWA; it launches in standalone mode
      (no browser chrome) at the groups screen.
- [ ] **Service-worker update.** Ship a new build; an open client surfaces the
      update prompt and applies it without a manual cache clear.
- [ ] **Offline shell.** With the app installed and previously loaded, launch it
      offline; the shell loads and shows the offline state rather than a browser
      error.

## Notifications (only if `PUSH_SERVER_URL` is set at build)

- [ ] **Enable.** The home notification control appears; enabling prompts for
      permission and, once granted, subscribes.
- [ ] **Per-group toggle.** A group's notification toggle subscribes/unsubscribes;
      an action by another member delivers a notification with the correct
      event-specific text in the active language (RR-005).
- [ ] **Unavailable state.** With the push server unreachable, enabling shows the
      unavailable message instead of doing nothing (RR-006).
- [ ] **Push disabled build.** With `PUSH_SERVER_URL` unset, the home control and
      the per-group toggles are absent everywhere.

## Accessibility and i18n

- [ ] **Accessible names.** With a screen reader (VoiceOver / NVDA / Orca), the
      add-entry button and the icon-only buttons announce a meaningful name, not
      "button" (RR-004).
- [ ] **Language switch.** Toggle English ⇄ French: the UI updates and
      `document.documentElement.lang` changes to match (inspect `<html lang>`).
- [ ] **Toast feedback.** A toast (e.g. "copied", or a sync error) is announced by
      the screen reader and does not block clicking the tab bar underneath it.

## Metadata (self-host)

- [ ] **Canonical / social tags.** In the built `dist/index.html`, the canonical
      and Open Graph URLs point at `CANONICAL_ORIGIN` (the deploy's own host, or
      the project site by default), not a stale host (RR-012).
- [ ] **Manifest.** `dist/manifest.webmanifest` installs cleanly and includes
      `categories` and portrait `orientation`.
