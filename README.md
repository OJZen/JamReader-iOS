# YACReader iOS (SwiftUI + UIKit)

An iOS-first port of desktop YACReader + YACReaderLibrary, focused on mobile reading and library management workflows.

## Current runnable scope

- Local library import and registry management
- Library browsing (folders, list/grid, search, filters)
- Special collections (`Reading`, `Favorites`, `Recent`)
- Tags and reading lists (browse/create/edit/remove membership)
- Reader support for `PDF`, `CBZ/ZIP`, `TAR/CBT`, `RAR/CBR/7Z/CB7/ARJ`
- Reading progress, bookmarks, favorite, read/unread, rating
- Quick metadata editing in reader and library quick actions
- Batch metadata updates (including batch rating/reset rating)
- Embedded `ComicInfo.xml` import workflows

## Build and run

Open project in Xcode:

```bash
open /Volumes/Ju/Projects/ios/yacreader/yacreader.xcodeproj
```

CLI build (no code signing):

```bash
xcodebuild \
  -project /Volumes/Ju/Projects/ios/yacreader/yacreader.xcodeproj \
  -scheme yacreader \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/yacreader-derived-data \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Gesture architecture guard (no SwiftUI gestures; UIKit recognizers only):

```bash
/Volumes/Ju/Projects/ios/yacreader/scripts/check_no_swiftui_gestures.sh
```

## Quick validation checklist

1. Add/open a local library folder.
2. Open one comic from browser into reader.
3. Verify page turning, progress persistence, and bookmarks.
4. Toggle favorite/read state and set rating from reader controls.
5. Use library quick actions to set rating and edit metadata.
6. Use selection mode and run batch metadata update with rating.

## Local test assets

Put large archives under `res/` for manual tests (for example `1.zip`, `2.rar`).
These files are intentionally ignored by git to keep repository size under control.

## Notes

- `YACReaderLibraryServer` is intentionally out of scope.
- Design and interaction follow mobile-first behavior, not 1:1 desktop UI parity.
- Detailed migration progress is tracked in:
  - `docs/ios-migration-plan.md`
