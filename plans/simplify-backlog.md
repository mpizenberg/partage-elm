# Simplification backlog

- **Main/group ownership:** Relay creation now lives with Page.Group sync. The next concrete seam is invitation acceptance: replace Main's `pendingJoinAction` and direct `loadedGroup` inspection with one completed pre-navigation workflow. After that, reassess explicit workspace loading state, push mutation, and catalog ownership; file-size refactors alone do not qualify.
- **Repeated small utilities:** filename sanitization, `allJust`, localized month/date labels, other calendar helpers, and several view helpers have duplicate implementations. Absorb them when an owning module is already being changed; a miscellaneous-utils module would merely relocate complexity.
