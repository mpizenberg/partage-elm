# Fix review findings 1 and 19 — sync triggers and quiet sync errors

Fixes two findings from `plan/REVIEW_2026-07-19.md`:

- **Finding 1 (S0):** the offline → reconnect flow never pushes the queue or
  resubscribes; the spec-promised ~100 s periodic flush does not exist.
- **Finding 19 (S2):** every offline edit triggers an untranslated red
  "Sync: Network error" toast even though the local save succeeded.

Order matters: 19 lands first so the periodic timer never ships with
toast-per-tick spam.

## Progress

1. Done — network-shaped sync failures silent; other sync failures toast via
   translated `toastSyncError` (EN/FR) and still log to ErrorLog.

## Increments

1. **Finding 19 — quiet, translated sync errors.** Network-shaped sync
   failures (`Http.NetworkError`, `Http.Timeout`) become fully silent — no
   toast, no error log; they are expected while offline and retried by the
   increment-2 triggers. All other sync failures keep toasting, through a
   translated `toastSyncError` message with the technical detail appended.
2. **Finding 1 — reconnect and periodic sync triggers.**
   - `CameOnline` triggers a sync for the loaded group (keeping the existing
     server-creation path when the group was never synced).
   - JS WS `onopen` after a reconnect notifies Elm through the existing
     `onServerEvent` port, producing a normal authenticated pull.
   - A ~100 s `Time.every` tick in `Page.Group.subscription`, active while a
     group is loaded, triggers a sync. It no-ops when a sync is already in
     flight. Deliberately not gated on `isOnline`: `navigator.onLine` is
     unreliable, and failed attempts are silent after increment 1.

## Decisions

- Network-shaped sync failures produce no ErrorLog entry either (not just no
  toast). Alternative — log with dedup or once-per-transition — rejected as
  complexity; with the periodic timer, logging each failure would add ~36
  entries/hour while offline. Reversible cheaply if diagnostics are missed.
- Timeout is classified as network-shaped alongside NetworkError: on flaky
  mobile links a timeout is the common presentation of "effectively offline".
- Toast translation scope: the toast wrapper sentence is translated; the
  technical detail from `Server.errorToString` stays English inside it.
  Translating every error branch was rejected — these toasts are now rare
  (non-network failures only) and the detail is diagnostic.
