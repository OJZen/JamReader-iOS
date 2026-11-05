# TaskBanner

Progress / result banner for local imports and scans, shown in a bottom content `safeAreaInset`. Do not add a task center.

## Rules

- Show task, target, and existing counts; show a fraction when progress is known, otherwise an in-progress state.
- Local file import can cancel with ×; scanning cannot, so omit ×. ComicInfo metadata import keeps its existing form and result notices, with no running cancellation entry.
- Local import results show imported / unsupported / failed, not newly added / already existing; see [capability limits](../../05-batches.md#library-and-import) for why.
- A clean success with a dismissal callback disappears after 4 seconds. Results with skips or failures remain until dismissed manually. The caller supplies target actions according to context.
- Completing an import from Library Home opens the target library and shows the result banner there.
- Remote import uses the global overlay from `RemoteBackgroundImportController`, keeping progress and cancellation available while navigating within the app. Offline saving uses the remote directory's task card, currently without cancellation or per-comic download states; see [remote limits](../../05-batches.md#remote-and-storage).
- Do not promise resumption after app exit.
