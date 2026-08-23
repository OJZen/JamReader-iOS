# JamReader Documentation

Start with the root [`AGENTS.md`](../AGENTS.md), then read:

- [`project-context.md`](project-context.md) for current architecture, flows, ownership, and task routing.
- [`development-workflow.md`](development-workflow.md) for repository hygiene, build/test commands, validation, and handoff.

Runtime code, tests, and static guards win if documentation drifts. Most tasks need no other document.

## Read On Demand

- [`maintenance-pitfalls.md`](maintenance-pitfalls.md): known regressions and high-risk checks. Sections 2–3 cover library/import, 4 and 10 remote/cache, 5–9 reader/UI/navigation, 11 formats, and 12 manual regression.
- [`ui-guidelines.md`](ui-guidelines.md): current iPhone/iPad visual, interaction, sheet, and accessibility constraints.
- [`logging-strategy.md`](logging-strategy.md): logging categories, privacy boundaries, and noise policy.
- [`native-library-static-validation-checklist.md`](native-library-static-validation-checklist.md): extra checks for local-library persistence, import, indexing, or deletion.

## Ownership

- Product capabilities: root `README.md`.
- Architecture and state ownership: `project-context.md`.
- Commands and engineering procedure: `development-workflow.md`.
- Repeated failures: `maintenance-pitfalls.md`.
- UI intent: `ui-guidelines.md`.

Update the owning page instead of adding a second explanation. Remove completed plans, audits, generated output, and stale handoffs when they no longer guide a current decision; Git keeps the history.
