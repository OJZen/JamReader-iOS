# ReaderTopBar

Reader top bar (`ReaderTopBar`). Overlays content without changing comic dimensions when shown/hidden.

## Structure
- Left: Back (44pt circular `reader-chrome`).
- Center: title in `reader-title`, plain text, not a capsule; a capsule looks tappable, but the title is not. A top gradient scrim (`jr-rscrim`) fades with tools to keep the title readable over light pages, without occupying layout or changing content.
- **No page number**: page number and percentage already appear in the protected bottom page-number capsule (compact entry in vertical mode); do not repeat them in the top bar.
- Right: one three-button capsule: bookmark (toggles the current page, solid jam color when added), `Aa` display settings (tap again to close), `…` More. The former separate Browse Pages and Save to Photos buttons move into More, reducing the top bar from 4 buttons to 3.
- At the bookmark limit, use a one-step replacement Alert; see [reader requirements](../../../design-requirements.md#5-comic-reader-protected-and-editable-areas) for behavior and count limits.
- Keep Latin glyphs for `Aa` so SF Symbols does not substitute Chinese/Japanese glyphs.

## Must Not Change
Keep tap regions, display timing, and animation curves (`AppAnimation.chromeToggle`). Tools respect the safe area.

No page calls the static mockup's cross-comic navigation capsule; see [implementation decisions](../../05-batches.md#reader).
