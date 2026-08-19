# Simplification backlog

- **Summary durability failures:** Ordinary active-group summary saves publish optimistic workspace/catalog state but ignore IndexedDB failure, so memory can remain ahead of durable state until reload. Define one rollback, retry, or visible-failure policy without weakening the serialized mutation queue.
- **First imported group persistence:** Compressed-file import bypasses `requestPersistOnFirstGroup` even though the helper's contract says create, import, and join should ask the browser to protect the origin after the first group. Route successful import through the same policy.
- **Repeated small utilities:** filename sanitization, `allJust`, localized month/date labels, other calendar helpers, and several view helpers have duplicate implementations. Absorb them when an owning module is already being changed; a miscellaneous-utils module would merely relocate complexity.
- **Push subscriptions are never refreshed:** a group topic is registered only when the notification toggle is used, so a rotated push endpoint silently stops delivering until the user toggles again. Re-register subscribed groups whenever a fresh push subscription arrives.
