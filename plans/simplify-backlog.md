# Simplification backlog

- **Main/group ownership:** `Main.elm` and `Page/Group.elm` are 2k–3k-line coordinators. Before splitting files, look for state that can be made impossible or an ownership boundary that deletes message/config plumbing; file-size refactors alone do not qualify.
- **Repeated small utilities:** filename sanitization, `allJust`, localized month/date labels, other calendar helpers, and several view helpers have duplicate implementations. Absorb them when an owning module is already being changed; a miscellaneous-utils module would merely relocate complexity.
