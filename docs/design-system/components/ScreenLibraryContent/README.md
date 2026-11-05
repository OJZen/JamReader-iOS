# ScreenLibraryContent

Library content page: browse folder levels and a comic grid (grid by default, switchable to list).

## Structure (Top to Bottom; Collections Only at Root)
Search (see [local-library capabilities](../../../design-requirements.md#local-libraries) for scope and limits) → 2×2 collection entries → folders → comics.
- Sort sits to the right of the Comics section title (Name / Recently Added / Recently Opened…), with quick filters below (All / Unread / In Progress / Read / With Bookmarks). Filters affect only comics in the current folder; folders remain visible. In Progress also stays within the current folder and is not the whole-library Continue Reading collection.
- Root Continue Reading hero-card visibility follows [ContinueReading](../ContinueReading/README.md#placement-and-scope); when shown, it sits between collection entries and folders.

## Toolbar (Same at Root and in Subfolders)
- Select · ⋯. In ⋯, in order: Import Here… / Grid · List / Import Comic Info… / Refresh & Scan / Library Info.
- In read-only linked folders, disable Import Here and add “The folder is read-only” as the menu subtitle. The empty-folder action is also Import Here.
- Recently Added Period is removed from this page's menu; it appears only in Settings and Recently Added.
- Scan progress and maintenance records no longer occupy a Status section. Use TaskBanner while running and Library Info for results.
- Library Info collects Rename, storage location, read-only / permission explanations, last scan results, and library removal or deletion.

Import Here… is a submenu (Choose Files… / Choose Folder…). Whole-library refresh and metadata import remain available in subfolders. There is no in-place reauthorization entry; see [capability limits](../../05-batches.md#library-and-import).

## Import Comic Info (ComicInfo)
Use one Import Comic Info… entry: first choose scope (Selected Comics / Current List / This Folder and Subfolders / Entire Library), then Fill Empty Fields / Overwrite Existing Fields.
