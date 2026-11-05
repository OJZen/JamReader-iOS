# ReaderDisplayPanel

Display settings panel (`Aa`): adjust the current view with immediate visual feedback.

## Structure

- Compact width uses a system sheet whose height follows content; regular width opens a popover from `Aa`, 380pt wide by default or 520pt at accessibility text sizes.
- Both use solid `surface` backgrounds so comics do not show through and impair control readability.
- Reading Mode uses illustrated cards; other settings use segmented controls and switches. At accessibility text sizes, cards stack vertically and segments become menus.
- The [reader control table](../../03-reader.md#display-panel-control-visibility) owns visibility. Show First Page Alone is a switch for page-pairing preference; Fit Mode keeps Original, with Reset Rotation after rotating.
- Footnotes explain the scope of shared defaults and current-session rotation; see [reader requirements](../../../design-requirements.md#5-comic-reader-protected-and-editable-areas).
- Close the bottom panel with ×, swipe down, or another tap on `Aa`. Content behind it remains interactive; tapping outside does not close it. Close the popover by tapping outside or `Aa` again. Both support the VoiceOver escape gesture (`accessibilityPerformEscape`).

## Protection

Opening the panel does not move or rearrange the bottom navigation list / right-side track.
