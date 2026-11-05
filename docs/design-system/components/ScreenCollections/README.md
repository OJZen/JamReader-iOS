# ScreenCollections

Collection pages reuse the same layout in `LibrarySpecialCollectionView` / `LibraryOrganizationCollectionDetailView`.

- Title: collection name; subtitle: owning library and count; search stays within the current collection.
- Favorites, Recently Added, Tags, and Reading Lists content pages use [FilterChips](../FilterChips/README.md) with current-collection search. Continue Reading is already In Progress and shows no filters.
- Tags and Reading Lists are two pages with the same structure, entered from their respective Tags and Reading Lists collection cards; do not combine them into one page again.
- Create (+); Edit enters editing mode for renaming, color changes, and deletion. Long press / swipe are shortcuts to the same actions.
- Sort on Tags and Reading Lists (Name / Most Comics / Fewest Comics) stays to the right of the list section title, matching sort in the Comics section. The navigation bar has only Edit and +.
- Recently Added has a trailing navigation-bar time-range menu (7 / 14 / 30 / 90 days), sharing the Settings preference.
- Copy: Remove from Tag, not Delete. Delete Tag confirmation states “Comics are not deleted”.
