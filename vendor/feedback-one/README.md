# Feedback.one SDK (vendored)

`core.min.js` is a pinned copy of <https://sdk.feedback.one/v0/core.min.js>,
copied to `dist/feedback-one.js` and loaded only when someone opens the form.
Upstream serves that URL `no-cache` and updates it in place, so loading it live
would hand a third party a standing remote-code channel into an origin that
holds decrypted group data. The initial integration did not establish whether
upstream permits redistributing a pinned copy; treat that permission as
unresolved and confirm the current terms before re-vendoring.

Running it is not free either: it replaces `customElements` with its own
registry implementation for the whole page, which is why it is fetched on
demand rather than shipped in the startup bundle. Elements defined before it
loads keep working — only `customElements.get` stops returning the original
class.

What keeps a pinned copy working is that the SDK and the hosted form negotiate
by *major* version: the iframe it opens is `form.feedback.one/v0/<projectId>`
and every `postMessage` carries `version: 0`. Anything upstream changes behind
that contract — form fields, spam handling, styling — reaches users without a
re-vendor, because only the SDK is pinned and the form itself is remote. What a
pinned copy cannot survive is a breaking change *inside* the 0.x line, or `v0`
being retired; both show up as a form that fails to load or misbehaves when
opened, never as a broken app.

Re-vendor deliberately, and re-check before doing so that it still sends
nothing beyond the four `postMessage` payloads (page URL, user agent, reporter
email, screenshot), still contains no `indexedDB` access, and still addresses a
form path this project has looked at.

| | |
| --- | --- |
| Version | 0.6.2 per the banner; the constant it reports as `sdkVersion` still reads 0.6.1 |
| Fetched | 2026-08-22 |
| SHA-256 | `b0535454138005cc880efa2139ac56440907858a589af71f55bed60bc2d950f5` |
