# Agent instructions

## Context hygiene across long sessions

You cannot measure your own token usage or trigger compaction — don't try. Instead, make compaction (automatic or manual) lossless by keeping state on disk:

- Keep planning documents in a `plans/` folder at the repo root, one document per task or feature, named `YYYY-MM-DD-short-slug.md` after the day the work starts so the folder sorts chronologically. Living documents that outlive a single task (a standing backlog, a reusable prompt) keep a bare descriptive name instead.
- Work in the discrete increments defined by the plan document governing the current task; commit at each increment boundary.
- Maintain a short **Progress** section at the top of that plan document: one line per completed increment, plus any deviation from the plan. Update it when an increment lands.
- In a long session, a completed increment is the natural compaction point — finish it, update Progress, commit, then suggest the user run `/compact`.

## Decision reporting

Some choices you make while working are worth surfacing even though they didn't block you. Record them so they can be reviewed rather than discovered later.

- Log a decision whenever you: pick between viable alternatives, resolve an ambiguity in the plan, deviate from the plan, introduce a dependency or pattern not already in the codebase, or defer/skip something the plan implied.
- Do not log routine mechanics — naming, formatting, obvious refactors, or anything the plan already specifies.
- Write each entry as: what was decided, the alternative(s) not taken, and the one-line reason. Include a reversibility note when undoing it later would be costly.
- Append entries to a **Decisions** section in the plan document as they occur, and repeat them in the increment's commit message or summary so they surface without opening the file.
- Flag anything you are uncertain about explicitly rather than presenting it as settled; if a decision materially changes scope or architecture, raise it in the chat at the increment boundary instead of only logging it.

## Keep the codebase lean

Every diff should leave the repo simpler, or at least no more complex. Removing is as valuable as adding.

- **Swap rule:** when a change replaces X with Y, deleting X is part of the change — old code paths, obsolete tests, stale docs and comments, finished TODOs, all in the same diff. Never keep the old thing "for compatibility" unless explicitly asked.
- **Bug fixes kill the cause.** No special-case `if` shielding a symptom; re-derive the design so the bug can't exist.
- **Comments:** never narrate what the next line does. A comment earns its place only by stating a constraint the code can't express. If a refactor makes a comment stale, it dies in that refactor.
- **No breadcrumbs.** Comments must read for someone with only the source in context — no "as discussed", "per the plan", links to plan files, or step numbers. Process belongs in the plan document or commit message.
- **Reuse before adding:** scan for an existing helper or concept before introducing a new one. Two names for one idea is a bug.
- **Adding can be subtraction.** A new abstraction or generalization earns its place when it deletes more than it adds — absorbs special cases, replaces several ad-hoc mechanisms with one principled one. Judge it by net effect on the system, not the diff of the file it lands in.
- **Old behavior is not sacred.** When a simplification justifies breaking behavior, propose it deliberately: name what changes, who could notice, and why the simpler shape wins. Tests pinning behavior nobody depends on die with that behavior; a kept test guards what the project still promises.
- **Docs are testimony, not ground truth.** Respect high-level goals and character, but detailed claims in docs and comments may be wrong, or right about code that no longer exists — the more technical they get, the less they deserve trust. When doc and code disagree, investigate; never preserve complexity because a comment claims it's needed.
- If something in the code surprised you or was hard to follow, that's a bad abstraction — fix it if it's in the area you're already changing, otherwise log it in the simplify backlog (below). Don't launch drive-by refactors outside the current task's scope; the backlog is where that pressure goes.
- Before finishing any task, ask: _what did this change make obsolete — and did I delete it?_

## The system rots between tasks

Diff-level hygiene cannot prevent it: complexity accumulates in the seams no single task owns, and each task, scoped to itself, never touches them. Give that work a destination and a trigger:

- Maintain `plans/simplify-backlog.md` as a living document. Every surprise, duplicated concept, bad abstraction, or "this fought me" moment becomes one line there. A flag without a destination evaporates at the next compaction.
- Before starting a task, check the backlog for the area about to be touched. If clearing an entry first would make the task smaller or safer, propose doing it first: make the change easy, then make the easy change.
- When entries cluster around one area, propose a dedicated simplification task with its own plan document. The largest reductions are redesigns unreachable by in-task steps — a data model that makes an error class unrepresentable, a boundary redrawn so three modules become one. These never happen unless they are scheduled as work.
