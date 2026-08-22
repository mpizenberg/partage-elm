# Feedback.one SDK (vendored)

`core.min.js` is a pinned copy of <https://sdk.feedback.one/v0/core.min.js>,
copied to `dist/feedback-one.js` and loaded only when someone opens the form.
Upstream serves that URL `no-cache` and updates it in place, so loading it live
would hand a third party a standing remote-code channel into an origin that
holds decrypted group data.

Running it is not free either: it replaces `customElements` with its own
registry implementation for the whole page, which is why it is fetched on
demand rather than shipped in the startup bundle. Elements defined before it
loads keep working — only `customElements.get` stops returning the original
class.

Re-vendor deliberately, and re-check before doing so that it still sends
nothing beyond the four `postMessage` payloads (page URL, user agent, reporter
email, screenshot) and still contains no `indexedDB` access.

| | |
| --- | --- |
| Version | 0.6.2 (first line of the file) |
| Fetched | 2026-08-22 |
| SHA-256 | `b0535454138005cc880efa2139ac56440907858a589af71f55bed60bc2d950f5` |
