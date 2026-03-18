#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="/Volumes/Ju/Projects/ios/yacreader"
TARGET_DIR="$PROJECT_ROOT/yacreader"

if ! command -v rg >/dev/null 2>&1; then
  echo "[check_no_swiftui_gestures] ripgrep (rg) is required." >&2
  exit 2
fi

PATTERN='\.gesture\(|\.simultaneousGesture\(|\.highPriorityGesture\(|onTapGesture\(|DragGesture\(|MagnificationGesture\(|RotationGesture\(|LongPressGesture\('

matches="$(rg -n "$PATTERN" "$TARGET_DIR" || true)"

if [[ -n "$matches" ]]; then
  echo "[check_no_swiftui_gestures] Found forbidden SwiftUI gesture APIs. Use UIKit gesture recognizers instead." >&2
  echo "$matches" >&2
  exit 1
fi

echo "[check_no_swiftui_gestures] OK: no SwiftUI gesture APIs found under $TARGET_DIR."
