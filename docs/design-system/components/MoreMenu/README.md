# MoreMenu

More centralizes comic, library, and server management actions. Local trailing `ellipsis` and long press share one menu; swipes use shortcuts from it.

## Local Comics
Three quick actions at the top (Favorite / Mark as Read / Tags & Lists), followed by Rating (submenu: 1–5 stars, Clear Rating), Edit Metadata, Info, and a separated Delete Comic last. Quick-action text changes with state (favorited → Unfavorite, read → Mark as Unread). System menus cannot contain a tappable star row, so ratings use a submenu.

## Remote Comics
Tapping the cover reads, so do not repeat Reading in the menu. Group remaining actions by intent and state the destination in subtitles:
1. **On This Device**: Save Offline Copy becomes Remove Local Copy once available offline; older copies offer Update Copy / Open Older Local Copy / Remove Local Copy.
2. **Local library**: Import to Library… → choose target library and scope.
3. Info.
Remote comics do not offer favorites, ratings, or metadata editing, which remote content does not support.

## Rules
- Delete/Remove always stays in the final group with a subtitle stating consequences.
- Do not duplicate entries with the same scope as the page's shortcut area.

⋯ and long press use the same system menu (`LibraryComicMenuContent`), with `ControlGroup` for quick actions. Swipes contain only shortcuts from those actions: leading Mark as Read / Mark as Unread; trailing Favorite / Unfavorite and Delete (still with confirmation). Rating, Edit Metadata, and Info appear only in ⋯ and long press. Tag and reading-list pages also offer Remove from Tag / Remove from Reading List, stating that the comic stays in the library.
