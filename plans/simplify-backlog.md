# Simplification backlog

- **Relay test discovery:** the bare `node --test` command counts `test/helpers.js` as an empty test file. When the relay test layout is next touched, move support code outside automatic discovery or use an explicit cross-platform test pattern.
- **Main/group ownership:** `Main.elm` and `Page/Group.elm` are 2k–3k-line coordinators. Before splitting files, look for state that can be made impossible or an ownership boundary that deletes message/config plumbing; file-size refactors alone do not qualify.
- **Repeated small utilities:** filename sanitization, `allJust`, localized month/date labels, other calendar helpers, and several view helpers have duplicate implementations. Absorb them when an owning module is already being changed; a miscellaneous-utils module would merely relocate complexity.
- **UUID v4 state:** `Infra.IdGen` uses `Random.step UUID.generator` even though elm-uuid recommends its four-seed `UUID.step` API for stronger v4 generation. A change would thread a different generator state through `Main`, `Page.Group`, and `GroupOps`; redesign that state once rather than shielding individual calls.
