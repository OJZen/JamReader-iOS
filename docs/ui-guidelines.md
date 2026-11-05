# JamReader UI Guidelines

Use these requirements when changing UI. They do not imply that every manual accessibility or device scenario below has been verified.

Product scope, user flows, data boundaries, and the protected reader interaction contract live in [design requirements](design-requirements.md). Keep the protected navigation components unchanged as specified in [reader rules](design-system/03-reader.md#原样保留不在设计范围). The [design system](design-system/README.md) owns visual values and component rules; [implementation decisions](design-system/05-batches.md) explain differences from static mockups.

## Product Character

- Native, quiet, content-first, and predictable. Prefer system navigation, controls, materials, typography, and semantic colors.
- Keep hierarchy clear with spacing and type before adding cards, borders, badges, or explanatory copy.
- Show only text that helps the next decision. Empty, error, permission, and destructive states may explain recovery; ordinary screens should stay concise.
- Reuse `JamReader/SharedUI/DesignTokens.swift` and existing `JamReader/SharedUI/Components/` before creating another visual language.

## Platform Adaptation

- iPhone uses compact navigation and one focused task per screen.
- iPad uses the existing UIKit split-view shell, persistent sidebars, keyboard/pointer affordances, and wider content where it improves scanning—not a stretched iPhone layout.
- Width decisions use the current container and traits, never a device model or `UIScreen.main.bounds`. Test split view, rotation, and multitasking.
- Sidebar selection uses `JamReader/SharedUI/Components/SidebarSelectionStyle.swift`; update its appearance centrally when redesigning, while preserving clear selection, spacing, a full-row hit target, and semantic colors.
- Sheets use system presentation through the existing coordinator/components. Every cancellable flow needs an obvious dismissal path, including loading, import, and error states.

## Interaction

- Keep reader paging, zoom, pan, dismissal, and gesture arbitration in UIKit. UI polish must not alter reader viewport geometry or create a second reader path.
- Keep primary actions easy to find and destructive actions explicit. Follow the [entry and reuse rules](design-system/02-architecture.md#入口安排与页面复用).
- Use animation to explain a state change, not decorate it. Respect Reduce Motion and avoid animating large layout changes or high-frequency updates.
- Preserve existing cancellation paths for long-running work; show a cancel action only when the operation supports it. Transparent overlays must not block unrelated controls.
- Minimum targets, VoiceOver labels/traits, Dynamic Type, keyboard focus, pointer hover, and selection state are part of the interaction—not follow-up polish.

## Surfaces And States

- Prefer system grouped lists/forms for settings and management; use cards only when grouping or preview hierarchy is materially clearer.
- Lists and grids must remain responsive with large libraries and remote directories. Reuse UIKit-backed high-frequency surfaces and bound thumbnail/prefetch work.
- Loading should preserve context when possible. Empty states offer one useful next action; error states preserve the real error and a recovery action.
- Use semantic colors and materials so light/dark mode, contrast, and iPad selection remain coherent. Do not encode state with color alone.
- Brand and status colors are asset colors exposed through `DesignTokens.swift`; usage rules live in [design foundations](design-system/00-foundations.md#颜色).
- Settings uses the General, Reading, Library, and Storage categories defined by `SettingsHomePane` on every size. iPhone starts from the category list; iPad presents that list as a persistent sidebar and restores its selected detail. Expose only enforceable global defaults; leave one-off or context-specific choices in their owning flow. Open Storage management directly, without duplicate overview, summary, or management layers.

## Change Checklist

For UI, sheet, or navigation changes, review:

- compact iPhone and regular-width iPad layouts
- iPad split view, rotation, multitasking, keyboard, and pointer behavior
- light/dark mode, Dynamic Type, Reduce Motion, and VoiceOver
- English, Simplified Chinese, Traditional Chinese (Taiwan), and Japanese text expansion
- loading, empty, error, cancellation, dismissal, and destructive confirmation paths

Reader-specific changes additionally require the focused reader tests and device checks in [`development-workflow.md`](development-workflow.md) and [`maintenance-pitfalls.md`](maintenance-pitfalls.md).
