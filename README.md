# JamReader

JamReader is a native comic reader for iPhone and iPad with local, SMB, and WebDAV library support.

## Highlights

- Mobile-first library and reader experience for iOS and iPadOS
- Local library import, browsing, search, tags, reading lists, and metadata editing
- Remote browsing over `SMB` and `WebDAV`, with saved folders, history, and offline copies
- Reader support for:
  - image folders
  - `CBZ / ZIP`
  - `CBR / RAR`
  - `CB7 / 7Z / ARJ`
  - `CBT / TAR`
  - `PDF`
  - `EPUB`

## Project Status

This project is in late-stage active development. The core reading and library flows are already runnable, with the current focus on polish, stability, and final UX refinement.

## Build

Open in Xcode:

```bash
open JamReader.xcodeproj
```

CLI build:

```bash
xcodebuild \
  -project JamReader.xcodeproj \
  -scheme JamReader \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/jamreader-derived-data \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Gesture architecture check:

```bash
./scripts/check_no_swiftui_gestures.sh
```
