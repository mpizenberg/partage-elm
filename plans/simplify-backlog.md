# Simplification backlog

- **Main/group ownership:** Relay creation, invitation acceptance, active-workspace loading, and group notification mutation now have explicit owners/states. Reassess summary-catalog ownership next, but move it only if the remaining API becomes demonstrably smaller; file-size refactors alone do not qualify.
- **Repeated small utilities:** filename sanitization, `allJust`, localized month/date labels, other calendar helpers, and several view helpers have duplicate implementations. Absorb them when an owning module is already being changed; a miscellaneous-utils module would merely relocate complexity.
