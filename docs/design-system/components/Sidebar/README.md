# Sidebar

iPad sidebar: show Source and collections together using UIKit split view (the existing shell).

## Rules
- Use split view's default width; rows are at least 44 high. Selected rows use `fill` and `radius-md`, changed centrally in `SidebarSelectionStyle.swift`.
- Library section: combined Continue Reading, My Libraries list (type icons: In App `books.vertical`, Linked Folder `folder.badge.link`, Imported Comics `tray`).
- Selecting a library shows its collections section. Remote sidebar: Servers / Offline Shelf / Saved Folders; Settings sidebar: General / Reading / Library / Storage.
- ⌘1/2/3 switches areas; focus and pointer interactions use system controls. See [iPhone Duo](../../06-iphone-duo.md#library--remote--settings) for window adaptation.
