# JamReader

JamReader is a native comic reader for iPhone and iPad with local, SMB, and WebDAV library support.

## Highlights

- Mobile-first library and reader experience for iOS and iPadOS
- Local library import, browsing, search, tags, reading lists, and metadata editing
- Continue reading across local libraries, with collection filters and grid/list views
- Remote browsing over `SMB` and `WebDAV`, with saved folders, history, and offline copies
- Paged and vertical comic reading, with bookmarks and shared display defaults
- Reader support for:
  - image folders
  - `CBZ / ZIP`
  - `CBR / RAR`
  - `CB7 / 7Z / ARJ`
  - `CBT / TAR`
  - `PDF` when MuPDF is linked into the build
  - `EPUB`

## Project Status

The core local-library, remote-browsing, and reading flows are implemented. Ongoing work prioritizes reliability, performance, and native iPhone/iPad UX.

## Development

Open `JamReader.xcodeproj` in Xcode. Canonical build, test, validation, artifact-location, and MuPDF instructions live in [the development workflow](docs/development-workflow.md).

## Developer Context

- [Agent entry point](AGENTS.md)
- [Documentation index](docs/README.md)

## UI/UX Design

- [Product requirements and user flows](docs/design-requirements.md)
- [Design system and implementation decisions](docs/design-system/README.md)
