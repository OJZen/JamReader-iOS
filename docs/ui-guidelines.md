# JamReader UI Guidelines

This is the current implementation-facing UI contract. It consolidates and supersedes the former design/Figma handoff documents for repository work; code and tested behavior remain authoritative.

## Product Character

- Native, quiet, content-first, and predictable. Prefer system navigation, controls, materials, typography, and semantic colors.
- Keep hierarchy clear with spacing and type before adding cards, borders, badges, or explanatory copy.
- Show only text that helps the next decision. Empty, error, permission, and destructive states may explain recovery; ordinary screens should stay concise.
- Reuse `JamReader/SharedUI/DesignTokens.swift` and existing `JamReader/SharedUI/Components/` before creating another visual language.

## Platform Adaptation

- iPhone uses compact navigation and one focused task per screen.
- iPad uses the existing UIKit split-view shell, persistent sidebars, keyboard/pointer affordances, and wider content where it improves scanning—not a stretched iPhone layout.
- Width decisions use the current container and traits, never a device model or `UIScreen.main.bounds`. Test split view, rotation, and multitasking.
- Sidebar selection uses `JamReader/SharedUI/Components/SidebarSelectionStyle.swift`; preserve its inset rounded shape, breathing room, full-row hit target, and semantic fill.
- Sheets use system presentation through the existing coordinator/components. Every cancellable flow needs an obvious dismissal path, including loading, import, and error states.

## Interaction

- Keep reader paging, zoom, pan, dismissal, and gesture arbitration in UIKit. UI polish must not alter reader viewport geometry or create a second reader path.
- Keep primary actions easy to find and destructive actions explicit. Do not duplicate the same action across a card, toolbar, tab, and context menu.
- Use animation to explain a state change, not decorate it. Respect Reduce Motion and avoid animating large layout changes or high-frequency updates.
- Preserve cancellation for network, import, indexing, and other long-running work. Transparent overlays must not block unrelated controls.
- Minimum targets, VoiceOver labels/traits, Dynamic Type, keyboard focus, pointer hover, and selection state are part of the interaction—not follow-up polish.

## Surfaces And States

- Prefer system grouped lists/forms for settings and management; use cards only when grouping or preview hierarchy is materially clearer.
- Lists and grids must remain responsive with large libraries and remote directories. Reuse UIKit-backed high-frequency surfaces and bound thumbnail/prefetch work.
- Loading should preserve context when possible. Empty states offer one useful next action; error states preserve the real error and a recovery action.
- Use semantic colors and materials so light/dark mode, contrast, and iPad selection remain coherent. Do not encode state with color alone.
- Settings uses an Overview plus Reading, Library, Storage, and About. Keep summaries short; put details in the destination screen or confirmation dialog.

## Change Checklist

For UI, sheet, or navigation changes, review:

- compact iPhone and regular-width iPad layouts
- iPad split view, rotation, multitasking, keyboard, and pointer behavior
- light/dark mode, Dynamic Type, Reduce Motion, and VoiceOver
- English, Simplified Chinese, Traditional Chinese (Taiwan), and Japanese text expansion
- loading, empty, error, cancellation, dismissal, and destructive confirmation paths
- main-thread work, task cancellation, list/grid reuse, and bounded image work

Reader-specific changes additionally require the focused reader tests and device checks in [`development-workflow.md`](development-workflow.md) and [`maintenance-pitfalls.md`](maintenance-pitfalls.md).
