# Design Decisions

[Design requirements](../design-requirements.md) owns business capabilities, workflows, and data boundaries. This chapter keeps only the rationale for interface decisions; entries, components, and values stay in their owning documents.

| Decision | Reason | Rules |
| --- | --- | --- |
| Separate local Library and Remote entries | File ownership, progress, and management capabilities differ; offline saving must not be treated as local import | [Information architecture](02-architecture.md) |
| Organize Add Comics by purpose | Users first choose to copy files, use an existing folder, or create an empty library, then choose the target | [Add Comics](components/ScreenAddComics/README.md) |
| Choose one of two Continue Reading locations | Avoid showing the same comics twice, even with only one library | [ContinueReading](components/ContinueReading/README.md) |
| Combine collection filtering and search | Keep the collection scope and explain current conditions in empty results | [FilterChips](components/FilterChips/README.md) |
| Tap covers to read; use More to manage | Reading needs no intervening detail page; lightweight actions stay separate from deletion | [MoreMenu](components/MoreMenu/README.md) |
| Separate jam fills from tappable text | Brighten accent text in dark mode while preserving white-text contrast on solid buttons | [Colors](00-foundations.md#colors) |
| Express status with icons and text | Color is secondary; reading cache must not appear as explicit offline saving | [StatusBadge](components/StatusBadge/README.md) |
| Group reader tools by page and comic | The display panel lists only effective controls; page-number entries do not duplicate protected navigation | [Reader](03-reader.md) |
| Adapt navigation by window width | Narrow windows focus on the current page; wide windows show source and content together | [Window adaptation](06-iphone-duo.md) |

See [state requirements](../design-requirements.md#page-states) for page states and [maintenance and review](../design-requirements.md#8-maintenance-and-review) for feature boundaries. See [implementation decisions and capability limits](05-batches.md) for differences from static mockups and environment adaptation not yet connected.
