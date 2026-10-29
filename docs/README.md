# JamReader Documentation

Start with [`AGENTS.md`](../AGENTS.md), then read `project-context.md` and `development-workflow.md`. Read the remaining pages only when relevant to the task.

For product and UI/UX design, start with the Chinese [design requirements](design-requirements.md). It separates current capabilities, redesign requirements, and protected reader behavior; it is not a screenshot-based visual audit. The approved redesign solution — information architecture, tokens, component rules, page mockups, and the batched implementation plan — lives in [design-system/](design-system/README.md).

## Ownership

| Document | Owns |
| --- | --- |
| [Root README](../README.md) | Product capabilities and supported formats |
| [Design requirements](design-requirements.md) | Designer-facing requirements, user flows, redesign scope, and reader interaction constraints |
| [Design system](design-system/README.md) | Approved redesign: information architecture, entry placement, `tokens.json` values, component and page specs, batched implementation plan |
| [Project context](project-context.md) | Architecture, data ownership, code entry points, and task routing |
| [Development workflow](development-workflow.md) | Build/test commands, CI boundaries, artifacts, validation, and handoff |
| [Maintenance pitfalls](maintenance-pitfalls.md) | Failure modes, diagnostic checks, and manual regression scenarios |
| [UI guidelines](ui-guidelines.md) | iPhone/iPad visual, interaction, sheet, and accessibility requirements |
| [Logging strategy](logging-strategy.md) | Logging categories, privacy limits, and diagnostic tracing |

Maintenance sections 2–3 cover library/import, 4 and 10 remote/cache, 5–9 reader/UI/navigation, 11 formats, and 12 manual regression. Local-library SQL checks and test entry points are in section 2.

Verify current implementation claims against code, tests, and static guards; distinguish UI requirements and historical symptoms from verified runtime behavior. Update the owning page instead of adding a second explanation. Remove plans, audits, generated output, and stale handoffs when they no longer guide a current decision; Git keeps the history.
