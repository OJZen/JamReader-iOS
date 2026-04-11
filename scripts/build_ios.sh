#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$PROJECT_ROOT/JamReader.xcodeproj"
DERIVED_DATA_PATH="/tmp/jamreader-derived-data"

echo "[build_ios] Cleaning previous build artifacts..."
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme JamReader \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  clean

echo "[build_ios] Building JamReader..."
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme JamReader \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  build

echo "[build_ios] Build completed successfully."
