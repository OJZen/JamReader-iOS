#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET_DIR="$PROJECT_ROOT/JamReader"

if ! command -v rg >/dev/null 2>&1; then
  echo "[check_no_swiftui_gestures] ripgrep (rg) is required." >&2
  exit 2
fi

# Match API tokens instead of requiring `(` so trailing-closure forms such as
# `.onTapGesture { ... }` cannot bypass the guard.
PATTERN='\.(gesture|simultaneousGesture|highPriorityGesture|onTapGesture|onLongPressGesture)\b|\b(DragGesture|MagnificationGesture|MagnifyGesture|RotationGesture|RotateGesture|LongPressGesture|TapGesture|SpatialTapGesture)[[:space:]]*\('

if ! rg -q "$PATTERN" <<<'View().onTapGesture { action() }'; then
  echo "[check_no_swiftui_gestures] Internal error: the guard pattern missed its trailing-closure sentinel." >&2
  exit 2
fi

matches=""
if matches="$(rg -n "$PATTERN" "$TARGET_DIR")"; then
  :
else
  status=$?
  if [[ "$status" -ne 1 ]]; then
    echo "[check_no_swiftui_gestures] ripgrep failed with status $status." >&2
    exit "$status"
  fi
fi

if [[ -n "$matches" ]]; then
  echo "[check_no_swiftui_gestures] Found forbidden SwiftUI gesture APIs. Use UIKit gesture recognizers instead." >&2
  echo "$matches" >&2
  exit 1
fi

echo "[check_no_swiftui_gestures] OK: no SwiftUI gesture APIs found under $TARGET_DIR."
