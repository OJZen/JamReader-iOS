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
  - `PDF` when MuPDF is linked into the build
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
./scripts/build_ios.sh
```

`scripts/build_ios.sh` auto-links MuPDF when an iPhoneOS arm64 build is available
at `.mupdf/mupdf-1.27.2`, or at the path provided by `MUPDF_ROOT`. Without that
local artifact the app still builds, but PDF reader support falls back to the
"MuPDF engine is not linked" message.

Gesture architecture check:

```bash
./scripts/check_no_swiftui_gestures.sh
```

Supported format policy check:

```bash
./scripts/check_supported_formats_consistency.sh
```

## Maintenance Notes

- [Maintenance pitfalls and regression checklist](docs/maintenance-pitfalls.md)
