# Simplification backlog

- **Relay storage adapters:** SQLite and Durable Object adapters repeat schema and quota/compaction flow. Investigate whether a shared storage kernel can delete more than the adapter boundary costs; do not abstract over genuinely different transaction APIs.
- **Main/group ownership:** `Main.elm` and `Page/Group.elm` are 2k–3k-line coordinators. Before splitting files, look for state that can be made impossible or an ownership boundary that deletes message/config plumbing; file-size refactors alone do not qualify.
- **Repeated small utilities:** filename sanitization, `allJust`, localized month/date labels, other calendar helpers, and several view helpers have duplicate implementations. Absorb them when an owning module is already being changed; a miscellaneous-utils module would merely relocate complexity.
- **UUID v4 state:** `Infra.IdGen` uses `Random.step UUID.generator` even though elm-uuid recommends its four-seed `UUID.step` API for stronger v4 generation. A change would thread a different generator state through `Main`, `Page.Group`, and `GroupOps`; redesign that state once rather than shielding individual calls.
