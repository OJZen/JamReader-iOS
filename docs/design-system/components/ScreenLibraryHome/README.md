# ScreenLibraryHome

Library Home (iPhone).

- Page background is `bg-grouped`; the library list and Continue Reading hero card use `surface`.
- Top Continue Reading visibility follows [ContinueReading](../ContinueReading/README.md#placement-and-scope) placement settings; when hidden, start directly with My Libraries.
- The whole hero card is one button (one VoiceOver element). Continue is a visual hint, not a second tap target.
- My Libraries: type icons distinguish In App / Linked Folder / Imported Comics; the secondary row shows count and storage method; read-only and authorization-needed states use StatusBadge.
- Library Rename, Info, Remove / Delete live in the content page's ⋯ → Library Info; home-row long press reuses those actions.
- Top-right [+] opens the Add Comics sheet. Hide [+] in the empty state, whose button provides the same entry. Or Connect a NAS Server opens Add Server in Remote.
