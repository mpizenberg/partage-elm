Make this project smaller and simpler without making it weaker. Your deliverable is a system with fewer concepts: measure success in code removed, special cases dissolved, and decisions a future reader no longer has to make.

Think at two scales, and don't let the small crowd out the large:

1. **Local** — delete what's dead, duplicated, or unreachable: unused exports, stale docs, comments that restate the code, flexibility nobody used, tests that only pin behavior nobody depends on. Collapse N things that are really one thing.
2. **Systemic** — step back and study the architecture as a whole. The largest simplifications are re-designs that no sequence of small safe steps can reach: a data model that makes a whole error class unrepresentable, a boundary redrawn so three modules become one, an assumption removed so half the branching disappears. Actively look for these; propose them even when they're bold.

Building is a valid instrument of subtraction. Introduce a new abstraction or generalization when it lets you delete more than it adds — when it absorbs special cases, makes the code more robust, or replaces several ad-hoc mechanisms with one principled one. Judge additions by net effect on the system, not by the diff of the file they land in.

Treat documentation as testimony, not ground truth. Respect the project's high-level goals and character, but individual docs and comments were written by someone who may have been wrong, or right about code that no longer exists — and the more technical and detailed they get, the less they deserve trust. When docs and code disagree, investigate; don't preserve complexity just because a comment claims it's needed. Every doc comment that survives must earn its place: concise, and critical to understanding *why* something is the way it is — the code already says what and how.

Rules:
- Behavior may change when the simplification justifies it — preserving everything forever guarantees complexity only grows. But breakage must be deliberate, not accidental: name what changes, who could notice, and why the simpler shape is worth it.
- Tests serve the goal, not the past. Remove tests with the behavior they pin; keep and adapt those guarding what the project still promises.
- Simpler beats shorter. Never trade readability for line count, and never add an abstraction that merely relocates complexity — code golf and speculative frameworks are both growth in disguise.

---

Compact version:

> Make the project smaller and simpler without making it weaker — fewer concepts, not just fewer lines. Work at two scales: locally, delete dead code, stale docs, unused flexibility, and tests pinning obsolete behavior, and collapse duplication; systemically, study the whole architecture for re-designs unreachable by small steps — redrawn boundaries, data models that make error classes unrepresentable. Building is a valid instrument of subtraction: add an abstraction or generalization when it deletes more than it adds or makes the system more robust. Treat docs as testimony, not ground truth — respect high-level intent, but challenge detailed claims, especially where they disagree with the code; a surviving doc comment must earn its place by concisely explaining *why*, not what. Behavior may change when justified, but deliberately — name what breaks and why it's worth it. Simpler beats shorter; judge every change by its net effect on the whole system.
