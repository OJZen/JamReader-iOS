# JamReader Agent Guide

## Start

1. Run `git status --short --branch`; preserve unrelated and user-authored work.
2. Read `docs/project-context.md`, then `docs/development-workflow.md`.
3. For reader, persistence, import, remote, cache, or navigation work, read only the relevant section of `docs/maintenance-pitfalls.md`.

Use `docs/README.md` for optional references. Runtime code, tests, and static guards are authoritative.

## Rules

- Make the smallest complete change. Avoid speculative abstractions, duplicate paths, and broad rewrites.
- Optimize for responsiveness and bounded memory/I/O; keep scanning, networking, extraction, and image decoding off the main thread.
- Prefer Apple frameworks, then established dependencies. Discuss new dependencies first.
- Keep gestures in UIKit and preserve the reader, data-ownership, security-scope, cache, and navigation boundaries in `docs/project-context.md`.
- Preserve native iPhone/iPad behavior, accessibility, and all four localizations.
- Keep one owner for each documented fact. Update it and remove superseded plans or guidance.

## Finish

- Keep build and task artifacts on the external project disk under `.xcodebuild/` or `CODEX_BUILD_ARTIFACTS_ROOT`; use system temporary directories only for small tool-managed files and leave no task output there.
- Remove obsolete files and rebuildable task artifacts. Never delete runtime/user data or commit generated data, credentials, samples, or local MuPDF files.
- Run the narrowest relevant tests, `./scripts/check_project_static_guards.sh`, and `git diff --check`. Run `./scripts/build_ios.sh` for source/project changes and report skipped simulator or device checks.
