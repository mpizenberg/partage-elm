# Push notifications

Why the notification path has this shape, so a later change does not undo a
guarantee by accident. The guarantees are in
[SPECIFICATION.md](SPECIFICATION.md#push-notification-exception), the
configuration in [DEPLOY.md](DEPLOY.md).

The constraint behind all of it: the push service reads whatever the payload
says in cleartext, and before this design that meant the group name, the actor,
the event kind, and the group id — the *same* identifier the relay and invite
links use, so one operator running both could join push-side names to relay-side
traffic.

## Why the pieces are what they are

- **The group key, not a derived subkey.** The vendored WebCrypto has no HKDF,
  the group key already protects this content, and random 96-bit IVs make
  cross-context reuse a non-issue at this scale.
- **Trial decryption, not a key hint.** A truncated fingerprint is one more
  stable per-group identifier on the wire, and a device holds few groups.
- **Padding to fixed buckets**, or ciphertext length leaks the description and
  group-name length; the 4 KB web-push limit leaves ample room.
- **SHA-256 with a domain separator, not HMAC.** None in the vendored WebCrypto,
  and length extension would only let a topic holder mint further strings —
  topics are addresses, not authenticators. *Uncertain: revisit if the package
  gains HMAC.*
- **A key and parameters, not a sentence.** The recipient owns their language,
  and rendering every shipped one into the ciphertext would grow the payload per
  language and let the sender's build decide which languages exist.
- **Locale config in the stored bundle, not `Intl`**, so a notification cannot
  format differently from the app. Likewise a multi-event sync appends `+N`
  rather than counting in prose, which would need CLDR plural categories in the
  service worker.
- **One `ActivityPhrase` type for the feed and the notification.** A
  representation only the service worker used would rot quietly; this puts every
  template on a daily screen and makes a new event kind a compile error. Elm
  cannot check the placeholder-sample list for completeness, so a missing phrase
  falls back to the generic line.

## The degraded path

Cleartext carries only what the intermediaries already know: the app name, the
opaque topic (which restores per-group stacking), a bilingual call to action —
localizing it would leak a per-topic hint about the subscriber.

| Situation | Result |
|---|---|
| Transform throws (no key, decrypt failure, IDB error), or a stale service worker mid-rollout | The constant cleartext |
| Transform never settles (IDB hangs) | Nothing from us; Chromium substitutes "site updated in the background", iOS shows nothing |
| Service worker never starts (iOS) | Nothing; iOS has no placeholder |

Row three is why the transform carries a short timeout: it is the only failure
mode yielding nothing rather than something.

**`legacy: true` stays; Declarative Web Push is refused.** Declarative rendering
(Safari ≥ 18.4) bypasses the service worker, so it can only display the
cleartext. Revisit only as an opt-out trading the guarantee for iOS delivery.

## Markers

A group syncs only while it is open, so the home marker's coverage is exactly
push's: no push service, a denied permission, or iOS without an installed PWA
means no home marker. Per-item marks need no storage — foreign events always
arrive during the visit that displays them. Only what a push writes while the
app is closed persists, in its own store rather than on `Group.Summary`, which
`summarize` rebuilds and exports embed verbatim.

Newness is arrival, not authored time: an offline member's events sort into the
middle of the history — precisely the case the feature exists for — so a
delimiter alone would be dishonest and each unseen item is marked too. Markers
clear on open rather than exit, since `visibilitychange` and tab close are
unreliable on mobile PWAs and a killed app would stay marked forever; that is
honest only because a marked card opens the activity tab.

## Subscription state

A subscription lives in two places: the flag on `Group.Summary` this device
stores, and the topic registered with the push server. A group new to this
device starts subscribed — the group you just created or joined is the one you
want to hear about — and the toggle records a departure from that default, so
turning it off stays off.

Opening a group is where the two are reconciled. A group born subscribed has no
registered topic yet, and nothing outside the group can derive one: the topic
needs the group key and the member's root id, which means replaying the group.
So neither the home screen nor an arriving push subscription can register it —
they can only re-register topics already stored. Best-effort and idempotent,
retried on every open until it lands.

## Runtime configuration

- **The relay serves the push URL but does not proxy push traffic.** A proxy
  would make push pure server-side config, but it collapses two parties into
  one: the relay already sees group traffic, and correlating that with blinded
  topics is exactly what blinding buys.
- **Over `/api/config`, not injected into `index.html`**, so online clients can
  refresh runtime settings without rebuilding the frontend. Because the shell
  is precached with its CSP headers, the relay also stamps CSP-affecting config
  into the served service worker's cache identity; changing the push origin
  therefore arrives as an ordinary app update instead of leaving an installed
  client enforcing the old CSP.
- **The last known URL is cached locally**, or the push surfaces pop in late on
  every launch and are absent when the app starts offline.
- **Configuration is re-fetched whenever connectivity returns.** The fetch must
  remain: a long-lived client has to discover a changed migration/freeze state
  and a VAPID rotation. An offline fallback may resolve cached push only; it
  cannot clear known deployment-wide settings. If the resolved push setup is
  unchanged, the client does not persist the URL, subscribe again, read every
  topic, or re-register them.

## Legacy-topic residual

Before blinded topics shipped, registrations used the plaintext group id and
member root id. The client no longer publishes to those addresses and no longer
carries a cleanup path, so a device that stayed dormant through the transition
may leave one registered until the external push service prunes it. This is an
accepted metadata residual, not an active notification channel; push-service
retention is outside this repository.

## Rejected

1. **Wake-up-only push, the service worker pulling from the relay** — strongest
   on paper, but decoding, replay, name resolution and bearer derivation in
   JavaScript is a second copy of the domain for no confidentiality gain.
2. **Sending from the relay** — it would learn affected members and store
   subscriptions, concentrating metadata in the operator's other service.
3. **One shared topic per group** — makes membership clustering explicit and
   wakes every member for every event, so non-affected devices show nothing,
   inviting the background-update notice and silent-push penalties.
4. **A per-recipient key** — every group-key holder already reads everything.
5. **Per-recipient shares** ("your share: 14,20 €") — built, then reverted: one
   plaintext per recipient makes encryptions scale with member count, while one
   shared payload would disclose group size through ciphertext length.
6. **A terse-notification preference** — both platforms already hide locked-screen content.

## Deferred

- **A `limit` parameter on the relay pull endpoint.** A pull returns nothing or
  up to 200 records / 4 MB, so polling every group at launch is out of the
  question; `limit` makes it a one-row peek — ~10 lines, exposing nothing new —
  letting the home screen mark groups with no push service at all.
- **Epoch-rotating topics**, defeating long-term subscription-to-topic linkage
  at the cost of periodic re-registration and unbounded subscription rows.
