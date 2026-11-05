# ScreenAddComics

Add Comics flow: Library Home [+] and the empty-state button open the same sheet.

1. Describe three methods by purpose: Import Comics (copy) / Use Existing Folder (no copy) / New Empty Library. All three cards behave alike: tap the whole card to continue.
2. Next in Import Comics: choose a destination first (Imported Comics by default, remembering the last choice afterward; read-only libraries are unavailable with a reason), then use the two bottom buttons to Choose Files or Choose Folder and open the system file picker. File / folder choice appears only once.
3. Show TaskBanner during copying and indexing, with cancellation. Open the target library on completion; the result banner shows actual counts as specified in [TaskBanner](../TaskBanner/README.md).
- Library content page ⋯ → Import Here uses the current library and folder directly, without asking for a destination again.
- Reuse duplicate content automatically; do not draw overwrite confirmation.
