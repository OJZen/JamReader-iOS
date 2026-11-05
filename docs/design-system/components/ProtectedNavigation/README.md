# ProtectedNavigation

**Protected components.** Reuse the paged bottom thumbnail navigation list (`ReaderBottomBar` + `ReaderThumbnailScrubber`, including its page-number capsule and floating preview) and vertical right-side thumbnail navigation list (`ReaderVerticalThumbnailRail`) unchanged.

## Constraints

- Do not change position, dimensions, spacing, thumbnail style, corners (13 / ≤8), enlargement and lift animation, visibility, touch handling, or page jumps.
- This card only illustrates code values (compact: thumbnails 40×58, items 46×76, frame height 100; track container 136pt, interaction width 68pt), not a new design.
- Shared tokens must not affect them indirectly; see [reader protection scope](../../03-reader.md#preserve-unchanged-outside-design-scope) for current references and isolation rules.
- Nearby tools and their animations must not squeeze or move them.
- See [reader requirements](../../../design-requirements.md#5-comic-reader-protected-and-editable-areas) for drag preview, page jumps on release, cancellation, and touch handling when hidden.

## iPhone Duo: Environment Adaptation Only

Tiers follow [environment adaptation rules](../../06-iphone-duo.md#protected-navigation-lists--environment-adaptation-only), with values and interactions unchanged. Half-folded container constraints are not connected; do not treat [ScreenDuoReader](../ScreenDuoReader/README.md) illustrations as current capabilities. See [implementation limits](../../05-batches.md#environment-adaptation-not-yet-connected) for gaps.
