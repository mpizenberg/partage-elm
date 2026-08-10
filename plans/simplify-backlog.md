# Simplification backlog

- **Main/group ownership:** Relay creation, invitation acceptance, and active-workspace loading now have explicit owners/states. The next concrete opportunity is serializing group notification mutation so rapid toggles and archive completion cannot race. After that, reassess catalog ownership; file-size refactors alone do not qualify.
- **Repeated small utilities:** filename sanitization, `allJust`, localized month/date labels, other calendar helpers, and several view helpers have duplicate implementations. Absorb them when an owning module is already being changed; a miscellaneous-utils module would merely relocate complexity.
