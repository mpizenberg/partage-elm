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

## Before the deploy

- [ ] **In-app changelog entry.** Add one only when it helps an existing user
      understand a changed app workflow, feature, behaviour, or handling of
      their local/group data. Public marketing pages, SEO/discovery,
      operator metrics, deployment/build work, and internal changes get no
      entry even when publicly visible. Relevant entries live in
      `src/Changelog.elm` plus `translations/messages.{en,fr}.ftl`, dated the
      day they ship; use one or two sentences, one entry per batch, and never
      reuse a date. It is the only changelog; there is no `CHANGELOG.md`.

## Core flows

- [ ] **First use.** Fresh profile → open the localized home, then enter the app.
      `/groups` generates and persists an identity before showing its controls;
      create a group and reload. The identity and group remain, with no regeneration
      or empty home.
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
      a second device/profile in the same group. While offline, those entries and
      their activity items carry the not-synced badge, and it survives a reload;
      it clears once they push.
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

## Cross-domain deployment move (only when migration is configured)

- [ ] **Configuration order.** The destination serves the expected
      `MIGRATION_SOURCE` before the source is frozen; the source serves
      `MIGRATION_TARGET` and `readOnly:true` together. Both `/api/config`
      responses report the image commit being tested.
- [ ] **Installed-PWA CSP.** Install/open the source PWA before the migration
      configuration is live, then apply the offered update and seed successfully
      without clearing site data. This proves the target-origin CSP reached the
      cached shell.
- [ ] **Active, archived, and post-freeze history.** Move an active group and an
      opted-in archive after creating one local entry on the frozen source. The
      destination receives the complete history; the archive hydrates once when
      opened and then remains network-idle.
- [ ] **Two members and repeat application.** Migrate a second member with a
      different local tail, then reload the destination and apply the first
      handoff code again. Both histories converge, existing destination groups
      are skipped, and destination relay growth reflects only missing events
      rather than another full shared log.
- [ ] **Transport boundaries.** Exercise one-tap `postMessage` from
      desktop/Android and the code path on iOS when available. The iOS browser
      refuses application until the destination is opened as its installed app.
      Push is absent until granted again on the destination origin.

## Operator dashboard (only if the relay is run with `ADMIN_SECRET` set)

- [ ] **Growth funnel.** Create one one-device group, one group used from two
      devices, and one three-device group with at least ten stored records. On
      `/admin`, the invite-spread buckets and real-use proxy match; actor ids are
      described as devices and records as a proxy, never as people or decrypted
      events.
- [ ] **History and cohorts.** The creation-cohort row counts those groups under
      their UTC Monday week and marks the current week immature. Restart the
      relay, then confirm the new funnel level snapshots render in the selected
      30/90/365-day growth trends; older dates correctly have no backfilled
      funnel history.
- [ ] **Landing referrers.** Open the site once directly, once from an external
      page, and once through a same-origin link. The dashboard total increases
      twice, only the external hostname appears, and its percentage uses both
      counted landings as the denominator; assets and API requests change
      neither number.

## Notifications (only if the relay is run with `PUSH_SERVER_URL` set)

- [ ] **Enable.** The home notification control appears; enabling prompts for
      permission and, once granted, subscribes.
- [ ] **Per-group toggle.** A group's notification toggle subscribes/unsubscribes;
      an action by another member delivers a notification with the correct
      event-specific text in the active language (RR-005).
- [ ] **Localized notification body.** With the app in French, a notification
      renders the French sentence with French number formatting; an amount in a
      zero-decimal currency (JPY) renders without decimals.
- [ ] **Decryption fallback.** A notification for a group whose key is absent
      locally (or a payload the service worker cannot decrypt) shows the
      constant "Partage / New activity · Nouvelle activité" fallback, never the
      raw payload and never nothing.
- [ ] **Home activity marker.** With the app closed, a notification for a
      group marks that group's card on the home list; the marked card opens the
      Activity tab, the marker clears, and the group's OS notifications close
      (confirm `getNotifications` works on an iOS device).
- [ ] **In-visit markers.** While a group is open, another member's new entry
      arrives with a left-border mark in the entries tab and a marked feed item
      under a "new activity" delimiter; the viewer's own events never mark.
- [ ] **New groups notify by default.** With notifications enabled, a group
      created or joined on this device is subscribed on its first open without
      touching the toggle, and another member's action delivers a notification.
      Turning the toggle off keeps it off across reopens.
- [ ] **Unavailable state.** With the push server unreachable, enabling shows the
      unavailable message instead of doing nothing (RR-006).
- [ ] **Push disabled deployment.** With `PUSH_SERVER_URL` unset on the relay, the
      home control and the per-group toggles are absent everywhere.
- [ ] **Repointed push server.** Change `PUSH_SERVER_URL` and restart the relay:
      an already-open client offers the update — the new URL rewrites the CSP,
      and with it the service worker's cache name — and once applied, a client
      that had notifications enabled re-subscribes and still receives another
      member's action, without clearing site data. Run this one on an
      **installed PWA**, the only client with no hard-reload escape hatch from a
      stale cached shell.

## Feedback (only if the relay is run with `FEEDBACK_PROJECT_ID` set)

- [ ] **Feedback tab.** The grey tab on the right edge is present on the home
      screen, inside a group, and on the About page. Its background fades from
      60% opacity on the left to opaque at the edge, leaving covered content
      faintly visible while its white icon stays clear; it opens the form in the
      app's language, both after switching language in this session and after a
      reload that restored the saved one — the widget takes its locale from
      `<html lang>`, so a language that stops at the Elm side shows an English
      form to a French reader. The form
      must render, not sit empty: the vendor serves it with `frame-ancestors`
      naming the project's registered domains, so a host that was never
      registered is blocked from framing it.
- [ ] **Fetched on demand.** With the network panel open, `/feedback-one.js` is
      requested when the form is first opened, not on load, and opening it a
      second time neither re-fetches nor mounts a second widget.
- [ ] **Secret-carrying screens.** Open an invite link (`/join/…#…`) and a
      notification landing: no feedback tab while the fragment is in the
      address bar; it reappears once the join completes.
- [ ] **Mobile screenshot.** On a phone, the form's screenshot button fails
      with the vendor's English message and the report still submits without
      it (no mobile browser has `getDisplayMedia`); on desktop it captures.
- [ ] **Reporter prefill.** With an email saved in the local profile (About →
      your profile), the form's reporter field arrives filled in. Clear the
      email from the profile, reopen: the field is empty again, including in a
      session that had already sent a report.
- [ ] **Report an issue.** On `/error-log`, "Report this issue" copies the debug
      report and opens the form in one gesture — the copied JSON pastes into the
      description. The copy and share buttons beside it still work on their own.
- [ ] **Idea from the changelog.** `/changelog` opens with the "what should we
      build next?" card, above the first entry, and its button opens the form.
- [ ] **A prompt banner.** In a group of five or more claimed members with ten or
      more entries, recording the transfer that clears the settlement plan raises
      a green banner. Its button opens the form; dismissing hides it; leaving the
      group hides it and returning brings it back. It does not appear again for
      that group — About → dev mode → "Reset feedback prompts" makes every
      question askable again.
- [ ] **Offline.** With the browser offline, the same moment raises no banner
      (the form is a remote iframe and would open empty).
- [ ] **Unconfigured deployment.** With `FEEDBACK_PROJECT_ID` unset on the
      relay, no tab anywhere, no report or idea button, no banner, and no
      `<feedback-one>` element in the DOM; setting it and restarting the relay
      brings them back without a rebuild.

## Accessibility and i18n

- [ ] **Accessible names.** With a screen reader (VoiceOver / NVDA / Orca), the
      add-entry button and the icon-only buttons announce a meaningful name, not
      "button" (RR-004).
- [ ] **Language switch.** Toggle English ⇄ French: the UI updates and
      `document.documentElement.lang` changes to match (inspect `<html lang>`).
- [ ] **Toast feedback.** A toast (e.g. "copied", or a sync error) is announced by
      the screen reader and does not block clicking the tab bar underneath it.

## Metadata and browser security

- [ ] **CSP console pass.** Keep the browser console open while creating a
      group (blob proof-of-work worker), opening an invite QR, fetching an
      exchange rate, importing/exporting, enabling push, and opening feedback.
      No required worker, connection, frame, image, or download is blocked by
      CSP.
- [ ] **Static home and metadata.** `/` negotiates to `/en/` or `/fr/`; both
      localized homes work without Elm, link to each other, and enter the app at
      `/groups`. In their served source, canonical, language-alternate, and Open
      Graph URLs point at the deployed host. The relay substitutes them per request;
      a static-host build must bake them via `CANONICAL_ORIGIN` (RR-012).
- [ ] **Manifest.** `dist/manifest.webmanifest` installs cleanly and includes
      `categories` and portrait `orientation`.
