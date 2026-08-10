# Simplification backlog

- **Main/group ownership:** Relay creation and invitation acceptance now have single owners. The next concrete opportunity is replacing Page.Group's ambiguous `Maybe LoadedGroup` with explicit workspace loading/missing/failure states while preserving deliberate background sync. After that, reassess push mutation and catalog ownership; file-size refactors alone do not qualify.
- **Repeated small utilities:** filename sanitization, `allJust`, localized month/date labels, other calendar helpers, and several view helpers have duplicate implementations. Absorb them when an owning module is already being changed; a miscellaneous-utils module would merely relocate complexity.
