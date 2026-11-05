# ReaderMoreMenu

Reader More menu: grouped by Pages / This Comic.

- **Pages**: thumbnail overview (reuses `ReaderThumbnailBrowserSheet`), Bookmarks (submenu: one jumpable row per bookmark, Remove Bookmark last), Save to Photos (handles authorization and failure).
- **Page-number jumping stays out of the menu**: tap the bottom page-number capsule (compact entry in vertical mode) to open the existing `ReaderPageJumpOverlay`. This is its only entry, matching protected-component behavior.
- **This Comic**: local comics reuse management actions from [MoreMenu](../MoreMenu/README.md#local-comics), excluding deletion; Mark as Read / Mark as Unread moves reading position and explains it with Toast. Remote comics keep only Info.
- Section titles: Pages appears normally; This Comic starts with a row of quick actions, so the system menu omits its title and keeps only the separator.
- Determine capability by document: page counts enable thumbnails and bookmarks; image-sequence pages can save to Photos. PDF / EPUB rendered pages also support these; EPUB web mode hides unsupported actions.
