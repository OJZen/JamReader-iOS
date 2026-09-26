# JamReader Agent Guide

Applies to this repository. Keep this file as the task entry point; detailed guidance belongs in `docs/`.

## Start

1. Run `git status --short --branch` and inspect existing diffs; preserve unrelated and user-authored work.
2. Read [project context](docs/project-context.md), then [development workflow](docs/development-workflow.md).
3. Use the [documentation index](docs/README.md) for task-specific references. Read the relevant maintenance pitfalls before reader, persistence, import, remote, cache, or navigation work.

## Rules

- Make the smallest complete change. Avoid speculative abstractions, duplicate paths, and broad rewrites.
- Optimize for responsiveness and bounded memory/I/O; keep scanning, networking, extraction, and image decoding off the main thread.
- Prefer Apple frameworks, then established dependencies. Discuss new dependencies first.
- Keep gestures in UIKit and preserve the reader, data-ownership, security-scope, cache, and navigation boundaries in the project context.
- Preserve native iPhone/iPad behavior, accessibility, and all four localizations.
- Verify implementation claims against code and tests. If intended behavior is unclear, ask instead of guessing or changing runtime behavior to match prose.
- Update the owning document when behavior, commands, or ownership changes. Remove superseded guidance; do not duplicate it in this file.

## Finish

- Follow the workflow's [validation matrix](docs/development-workflow.md#validation-by-change-type) and [handoff checks](docs/development-workflow.md#review-and-handoff). Report what ran and what was skipped; commit or push only when requested.
- Keep task artifacts on the external project disk under `.xcodebuild/` or `CODEX_BUILD_ARTIFACTS_ROOT`, and remove task output no longer needed. Follow the workflow's repository hygiene rules; never delete runtime/user data or local MuPDF inputs as build cleanup.
